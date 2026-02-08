package com.visionclaw.android.viewmodel

import android.graphics.Bitmap
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.visionclaw.android.audio.AudioManager
import com.visionclaw.android.service.gemini.GeminiConfig
import com.visionclaw.android.service.gemini.GeminiLiveService
import com.visionclaw.android.service.gemini.ToolCallStatus
import com.visionclaw.android.service.openclaw.OpenClawBridge
import com.visionclaw.android.service.openclaw.ToolCallRouter
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * ViewModel managing the Gemini Live AI session: WebSocket connection,
 * audio I/O, video frame forwarding, and tool-call orchestration.
 *
 * Equivalent to iOS GeminiSessionViewModel.swift.
 */
@HiltViewModel
class GeminiSessionViewModel @Inject constructor() : ViewModel() {

    private val _isGeminiActive = MutableStateFlow(false)
    val isGeminiActive: StateFlow<Boolean> = _isGeminiActive.asStateFlow()

    private val _connectionState = MutableStateFlow(GeminiLiveService.ConnectionState.DISCONNECTED)
    val connectionState: StateFlow<GeminiLiveService.ConnectionState> = _connectionState.asStateFlow()

    private val _isModelSpeaking = MutableStateFlow(false)
    val isModelSpeaking: StateFlow<Boolean> = _isModelSpeaking.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    private val _userTranscript = MutableStateFlow("")
    val userTranscript: StateFlow<String> = _userTranscript.asStateFlow()

    private val _aiTranscript = MutableStateFlow("")
    val aiTranscript: StateFlow<String> = _aiTranscript.asStateFlow()

    private val _toolCallStatus = MutableStateFlow<ToolCallStatus>(ToolCallStatus.Idle)
    val toolCallStatus: StateFlow<ToolCallStatus> = _toolCallStatus.asStateFlow()

    private val geminiService = GeminiLiveService()
    private val openClawBridge = OpenClawBridge()
    private var toolCallRouter: ToolCallRouter? = null
    private val audioManager = AudioManager()
    private var lastVideoFrameTime: Long = 0L
    private var stateObservationJob: Job? = null

    var streamingMode: StreamSessionViewModel.StreamingMode = StreamSessionViewModel.StreamingMode.GLASSES

    fun startSession() {
        if (_isGeminiActive.value) return

        if (!GeminiConfig.isConfigured) {
            _errorMessage.value =
                "Gemini API key not configured. Set GEMINI_API_KEY in local.properties."
            return
        }

        _isGeminiActive.value = true

        // Wire audio capture → Gemini
        audioManager.onAudioCaptured = { data ->
            // Phone mode: mute mic while model speaks to prevent echo
            if (streamingMode == StreamSessionViewModel.StreamingMode.PHONE &&
                geminiService.isModelSpeaking.value
            ) return@onAudioCaptured
            geminiService.sendAudio(data)
        }

        geminiService.onAudioReceived = { data -> audioManager.playAudio(data) }
        geminiService.onInterrupted = { audioManager.stopPlayback() }

        geminiService.onTurnComplete = {
            _userTranscript.value = ""
        }

        geminiService.onInputTranscription = { text ->
            _userTranscript.value += text
            _aiTranscript.value = ""
        }

        geminiService.onOutputTranscription = { text ->
            _aiTranscript.value += text
        }

        geminiService.onDisconnected = { reason ->
            if (_isGeminiActive.value) {
                stopSession()
                _errorMessage.value = "Connection lost: ${reason ?: "Unknown error"}"
            }
        }

        // Fresh OpenClaw session
        openClawBridge.resetSession()
        toolCallRouter = ToolCallRouter(openClawBridge, viewModelScope)

        geminiService.onToolCall = { toolCall ->
            for (call in toolCall.functionCalls) {
                toolCallRouter?.handleToolCall(call) { response ->
                    geminiService.sendToolResponse(response)
                }
            }
        }

        geminiService.onToolCallCancellation = { cancellation ->
            toolCallRouter?.cancelToolCalls(cancellation.ids)
        }

        // Observe service state changes
        stateObservationJob = viewModelScope.launch {
            while (isActive) {
                delay(100)
                _connectionState.value = geminiService.connectionState.value
                _isModelSpeaking.value = geminiService.isModelSpeaking.value
                _toolCallStatus.value = openClawBridge.lastToolCallStatus.value
            }
        }

        // Setup audio
        audioManager.setupAudioSession(
            usePhoneMode = streamingMode == StreamSessionViewModel.StreamingMode.PHONE
        )

        // Connect to Gemini
        viewModelScope.launch {
            val setupOk = geminiService.connect()

            if (!setupOk) {
                val msg = geminiService.errorMessage.value ?: "Failed to connect to Gemini"
                _errorMessage.value = msg
                geminiService.disconnect()
                stateObservationJob?.cancel()
                _isGeminiActive.value = false
                _connectionState.value = GeminiLiveService.ConnectionState.DISCONNECTED
                return@launch
            }

            // Start mic capture
            try {
                audioManager.startCapture()
            } catch (e: Exception) {
                _errorMessage.value = "Mic capture failed: ${e.localizedMessage}"
                geminiService.disconnect()
                stateObservationJob?.cancel()
                _isGeminiActive.value = false
                _connectionState.value = GeminiLiveService.ConnectionState.DISCONNECTED
            }
        }
    }

    fun stopSession() {
        toolCallRouter?.cancelAll()
        toolCallRouter = null
        audioManager.stopCapture()
        geminiService.disconnect()
        stateObservationJob?.cancel()
        stateObservationJob = null
        _isGeminiActive.value = false
        _connectionState.value = GeminiLiveService.ConnectionState.DISCONNECTED
        _isModelSpeaking.value = false
        _userTranscript.value = ""
        _aiTranscript.value = ""
        _toolCallStatus.value = ToolCallStatus.Idle
    }

    fun sendVideoFrameIfThrottled(bitmap: Bitmap) {
        if (!_isGeminiActive.value ||
            _connectionState.value != GeminiLiveService.ConnectionState.READY
        ) return
        val now = System.currentTimeMillis()
        if (now - lastVideoFrameTime < GeminiConfig.VIDEO_FRAME_INTERVAL_MS) return
        lastVideoFrameTime = now
        geminiService.sendVideoFrame(bitmap)
    }

    fun clearError() {
        _errorMessage.value = null
    }

    override fun onCleared() {
        super.onCleared()
        stopSession()
    }
}
