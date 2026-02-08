package com.visionclaw.android.service.openclaw

import android.util.Log
import com.visionclaw.android.service.gemini.GeminiConfig
import com.visionclaw.android.service.gemini.ToolCallStatus
import com.visionclaw.android.service.gemini.ToolResult
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.*
import java.util.concurrent.TimeUnit

/**
 * HTTP client for the OpenClaw gateway.
 * Equivalent to iOS OpenClawBridge.swift.
 */
open class OpenClawBridge {

    private val _lastToolCallStatus = MutableStateFlow<ToolCallStatus>(ToolCallStatus.Idle)
    val lastToolCallStatus: StateFlow<ToolCallStatus> = _lastToolCallStatus.asStateFlow()

    private val client = OkHttpClient.Builder()
        .readTimeout(120, TimeUnit.SECONDS)
        .writeTimeout(30, TimeUnit.SECONDS)
        .build()

    private var sessionKey: String = newSessionKey()

    fun resetSession() {
        sessionKey = newSessionKey()
        Log.i(TAG, "New session: $sessionKey")
    }

    fun setToolCallStatus(status: ToolCallStatus) {
        _lastToolCallStatus.value = status
    }

    /** Delegate a task to the OpenClaw gateway. */
    open suspend fun delegateTask(task: String, toolName: String = "execute"): ToolResult {
        _lastToolCallStatus.value = ToolCallStatus.Executing(toolName)

        val url = "${GeminiConfig.openClawHost}:${GeminiConfig.openClawPort}/v1/chat/completions"

        val body = JSONObject().apply {
            put("model", "openclaw")
            put("messages", JSONArray().put(
                JSONObject().apply {
                    put("role", "user")
                    put("content", task)
                }
            ))
            put("stream", false)
        }

        val request = Request.Builder()
            .url(url)
            .post(body.toString().toRequestBody("application/json".toMediaType()))
            .addHeader("Authorization", "Bearer ${GeminiConfig.openClawGatewayToken}")
            .addHeader("Content-Type", "application/json")
            .addHeader("x-openclaw-session-key", sessionKey)
            .build()

        return withContext(Dispatchers.IO) {
            try {
                val response = client.newCall(request).execute()
                val responseBody = response.body?.string() ?: ""
                val code = response.code

                if (code !in 200..299) {
                    Log.w(TAG, "Chat failed: HTTP $code - ${responseBody.take(200)}")
                    _lastToolCallStatus.value = ToolCallStatus.Failed(toolName, "HTTP $code")
                    return@withContext ToolResult.Failure("Agent returned HTTP $code")
                }

                val json = try { JSONObject(responseBody) } catch (_: Exception) { null }
                val content = json?.optJSONArray("choices")
                    ?.optJSONObject(0)
                    ?.optJSONObject("message")
                    ?.optString("content", null)

                if (content != null) {
                    Log.i(TAG, "Agent result: ${content.take(200)}")
                    _lastToolCallStatus.value = ToolCallStatus.Completed(toolName)
                    ToolResult.Success(content)
                } else {
                    Log.i(TAG, "Agent raw: ${responseBody.take(200)}")
                    _lastToolCallStatus.value = ToolCallStatus.Completed(toolName)
                    ToolResult.Success(responseBody)
                }
            } catch (e: Exception) {
                Log.e(TAG, "Agent error: ${e.localizedMessage}")
                _lastToolCallStatus.value = ToolCallStatus.Failed(toolName, e.localizedMessage ?: "Unknown")
                ToolResult.Failure("Agent error: ${e.localizedMessage}")
            }
        }
    }

    companion object {
        private const val TAG = "OpenClaw"

        private fun newSessionKey(): String {
            val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US)
            sdf.timeZone = TimeZone.getTimeZone("UTC")
            return "agent:main:glass:${sdf.format(Date())}"
        }
    }
}
