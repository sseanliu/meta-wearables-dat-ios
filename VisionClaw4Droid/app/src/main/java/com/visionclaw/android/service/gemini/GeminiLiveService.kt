package com.visionclaw.android.service.gemini

import android.graphics.Bitmap
import android.util.Base64
import android.util.Log
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import okhttp3.*
import org.json.JSONArray
import org.json.JSONObject
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/**
 * WebSocket client for the Gemini Live API.
 * Equivalent to iOS GeminiLiveService.swift.
 */
class GeminiLiveService {

    enum class ConnectionState {
        DISCONNECTED, CONNECTING, SETTING_UP, READY, ERROR
    }

    private val _connectionState = MutableStateFlow(ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<ConnectionState> = _connectionState.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _isModelSpeaking = MutableStateFlow(false)
    val isModelSpeaking: StateFlow<Boolean> = _isModelSpeaking.asStateFlow()

    // Callbacks
    var onAudioReceived: ((ByteArray) -> Unit)? = null
    var onTurnComplete: (() -> Unit)? = null
    var onInterrupted: (() -> Unit)? = null
    var onDisconnected: ((String?) -> Unit)? = null
    var onInputTranscription: ((String) -> Unit)? = null
    var onOutputTranscription: ((String) -> Unit)? = null
    var onToolCall: ((GeminiToolCall) -> Unit)? = null
    var onToolCallCancellation: ((GeminiToolCallCancellation) -> Unit)? = null

    // Latency tracking
    private var lastUserSpeechEnd: Long = 0L
    private var responseLatencyLogged = false

    private var webSocket: WebSocket? = null
    private val client = OkHttpClient.Builder()
        .readTimeout(java.time.Duration.ofSeconds(30))
        .build()
    private val sendExecutor = Executors.newSingleThreadExecutor()
    private var connectContinuation: CancellableContinuation<Boolean>? = null
    private var timeoutJob: Job? = null

    suspend fun connect(): Boolean {
        val url = GeminiConfig.websocketUrl() ?: run {
            _connectionState.value = ConnectionState.ERROR
            _errorMessage.value = "No API key configured"
            return false
        }

        _connectionState.value = ConnectionState.CONNECTING

        return suspendCancellableCoroutine { cont ->
            connectContinuation = cont

            val request = Request.Builder().url(url).build()
            webSocket = client.newWebSocket(request, object : WebSocketListener() {
                override fun onOpen(webSocket: WebSocket, response: Response) {
                    _connectionState.value = ConnectionState.SETTING_UP
                    sendSetupMessage()
                }

                override fun onMessage(webSocket: WebSocket, text: String) {
                    handleMessage(text)
                }

                override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                    resolveConnect(false)
                    _connectionState.value = ConnectionState.DISCONNECTED
                    _isModelSpeaking.value = false
                    onDisconnected?.invoke("Connection closed (code $code: $reason)")
                }

                override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                    val msg = t.localizedMessage ?: "Unknown error"
                    resolveConnect(false)
                    _connectionState.value = ConnectionState.ERROR
                    _errorMessage.value = msg
                    _isModelSpeaking.value = false
                    onDisconnected?.invoke(msg)
                }
            })

            // Timeout after 15 seconds
            timeoutJob = CoroutineScope(Dispatchers.Default).launch {
                delay(15_000)
                resolveConnect(false)
                if (_connectionState.value == ConnectionState.CONNECTING ||
                    _connectionState.value == ConnectionState.SETTING_UP
                ) {
                    _connectionState.value = ConnectionState.ERROR
                    _errorMessage.value = "Connection timed out"
                }
            }
        }
    }

    fun disconnect() {
        timeoutJob?.cancel()
        timeoutJob = null
        webSocket?.close(1000, null)
        webSocket = null
        onToolCall = null
        onToolCallCancellation = null
        _connectionState.value = ConnectionState.DISCONNECTED
        _isModelSpeaking.value = false
        resolveConnect(false)
    }

    fun sendAudio(data: ByteArray) {
        if (_connectionState.value != ConnectionState.READY) return
        sendExecutor.execute {
            val base64 = Base64.encodeToString(data, Base64.NO_WRAP)
            val json = JSONObject().apply {
                put("realtimeInput", JSONObject().apply {
                    put("audio", JSONObject().apply {
                        put("mimeType", "audio/pcm;rate=${GeminiConfig.INPUT_AUDIO_SAMPLE_RATE}")
                        put("data", base64)
                    })
                })
            }
            webSocket?.send(json.toString())
        }
    }

    fun sendVideoFrame(bitmap: Bitmap) {
        if (_connectionState.value != ConnectionState.READY) return
        sendExecutor.execute {
            val baos = ByteArrayOutputStream()
            bitmap.compress(Bitmap.CompressFormat.JPEG, GeminiConfig.VIDEO_JPEG_QUALITY, baos)
            val base64 = Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
            val json = JSONObject().apply {
                put("realtimeInput", JSONObject().apply {
                    put("video", JSONObject().apply {
                        put("mimeType", "image/jpeg")
                        put("data", base64)
                    })
                })
            }
            webSocket?.send(json.toString())
        }
    }

    fun sendToolResponse(response: JSONObject) {
        sendExecutor.execute {
            webSocket?.send(response.toString())
        }
    }

    // -- Private --

    private fun resolveConnect(success: Boolean) {
        timeoutJob?.cancel()
        val cont = connectContinuation
        connectContinuation = null
        if (cont?.isActive == true) {
            cont.resume(success) {}
        }
    }

    private fun sendSetupMessage() {
        val setup = JSONObject().apply {
            put("setup", JSONObject().apply {
                put("model", GeminiConfig.model)
                put("generationConfig", JSONObject().apply {
                    put("responseModalities", JSONArray().put("AUDIO"))
                    put("thinkingConfig", JSONObject().put("thinkingBudget", 0))
                })
                put("systemInstruction", JSONObject().apply {
                    put("parts", JSONArray().put(JSONObject().put("text", GeminiConfig.systemInstruction)))
                })
                put("tools", JSONArray().put(
                    JSONObject().put("functionDeclarations", ToolDeclarations.allDeclarations())
                ))
                put("realtimeInputConfig", JSONObject().apply {
                    put("automaticActivityDetection", JSONObject().apply {
                        put("disabled", false)
                        put("startOfSpeechSensitivity", "START_SENSITIVITY_HIGH")
                        put("endOfSpeechSensitivity", "END_SENSITIVITY_LOW")
                        put("silenceDurationMs", 500)
                        put("prefixPaddingMs", 40)
                    })
                    put("activityHandling", "START_OF_ACTIVITY_INTERRUPTS")
                    put("turnCoverage", "TURN_INCLUDES_ALL_INPUT")
                })
                put("inputAudioTranscription", JSONObject())
                put("outputAudioTranscription", JSONObject())
            })
        }
        webSocket?.send(setup.toString())
    }

    private fun handleMessage(text: String) {
        val json = try { JSONObject(text) } catch (_: Exception) { return }

        // Setup complete
        if (json.has("setupComplete")) {
            _connectionState.value = ConnectionState.READY
            resolveConnect(true)
            return
        }

        // GoAway
        if (json.has("goAway")) {
            val seconds = json.optJSONObject("goAway")
                ?.optJSONObject("timeLeft")?.optInt("seconds", 0) ?: 0
            _connectionState.value = ConnectionState.DISCONNECTED
            _isModelSpeaking.value = false
            onDisconnected?.invoke("Server closing (time left: ${seconds}s)")
            return
        }

        // Tool call
        GeminiToolCall.fromJson(json)?.let { toolCall ->
            Log.i(TAG, "Tool call received: ${toolCall.functionCalls.size} function(s)")
            onToolCall?.invoke(toolCall)
            return
        }

        // Tool call cancellation
        GeminiToolCallCancellation.fromJson(json)?.let { cancellation ->
            Log.i(TAG, "Tool call cancellation: ${cancellation.ids.joinToString()}")
            onToolCallCancellation?.invoke(cancellation)
            return
        }

        // Server content
        val serverContent = json.optJSONObject("serverContent") ?: return

        if (serverContent.optBoolean("interrupted", false)) {
            _isModelSpeaking.value = false
            onInterrupted?.invoke()
            return
        }

        val modelTurn = serverContent.optJSONObject("modelTurn")
        val parts = modelTurn?.optJSONArray("parts")
        if (parts != null) {
            for (i in 0 until parts.length()) {
                val part = parts.getJSONObject(i)
                val inlineData = part.optJSONObject("inlineData")
                if (inlineData != null) {
                    val mimeType = inlineData.optString("mimeType", "")
                    if (mimeType.startsWith("audio/pcm")) {
                        val base64Data = inlineData.optString("data", "")
                        if (base64Data.isNotEmpty()) {
                            val audioData = Base64.decode(base64Data, Base64.NO_WRAP)
                            if (!_isModelSpeaking.value) {
                                _isModelSpeaking.value = true
                                if (lastUserSpeechEnd > 0 && !responseLatencyLogged) {
                                    val latency = System.currentTimeMillis() - lastUserSpeechEnd
                                    Log.i(TAG, "Latency: ${latency}ms (user speech end -> first audio)")
                                    responseLatencyLogged = true
                                }
                            }
                            onAudioReceived?.invoke(audioData)
                        }
                    }
                }
                val textContent = part.optString("text", "")
                if (textContent.isNotEmpty()) {
                    Log.i(TAG, textContent)
                }
            }
        }

        if (serverContent.optBoolean("turnComplete", false)) {
            _isModelSpeaking.value = false
            responseLatencyLogged = false
            onTurnComplete?.invoke()
        }

        serverContent.optJSONObject("inputTranscription")?.let { tx ->
            val txt = tx.optString("text", "")
            if (txt.isNotEmpty()) {
                Log.i(TAG, "You: $txt")
                lastUserSpeechEnd = System.currentTimeMillis()
                responseLatencyLogged = false
                onInputTranscription?.invoke(txt)
            }
        }
        serverContent.optJSONObject("outputTranscription")?.let { tx ->
            val txt = tx.optString("text", "")
            if (txt.isNotEmpty()) {
                Log.i(TAG, "AI: $txt")
                onOutputTranscription?.invoke(txt)
            }
        }
    }

    companion object {
        private const val TAG = "GeminiLive"
    }
}
