package com.visionclaw.android.service.openclaw

import android.util.Log
import com.visionclaw.android.service.gemini.GeminiFunctionCall
import com.visionclaw.android.service.gemini.ToolCallStatus
import kotlinx.coroutines.*
import org.json.JSONArray
import org.json.JSONObject

/**
 * Routes Gemini tool calls to OpenClaw and manages in-flight tasks.
 * Equivalent to iOS ToolCallRouter.swift.
 */
class ToolCallRouter(
    private val bridge: OpenClawBridge,
    private val scope: CoroutineScope,
) {

    private val inFlightTasks = mutableMapOf<String, Job>()

    fun handleToolCall(
        call: GeminiFunctionCall,
        sendResponse: (JSONObject) -> Unit,
    ) {
        val callId = call.id
        val callName = call.name

        Log.i(TAG, "Received: $callName (id: $callId) args: ${call.args}")

        val job = scope.launch {
            val taskDesc = call.args["task"] as? String ?: call.args.toString()
            val result = bridge.delegateTask(taskDesc, callName)

            if (!isActive) {
                Log.i(TAG, "Task $callId was cancelled, skipping response")
                return@launch
            }

            Log.i(TAG, "Result for $callName (id: $callId): $result")

            val response = buildToolResponse(callId, callName, result)
            sendResponse(response)

            inFlightTasks.remove(callId)
        }

        inFlightTasks[callId] = job
    }

    fun cancelToolCalls(ids: List<String>) {
        for (id in ids) {
            inFlightTasks[id]?.let { job ->
                Log.i(TAG, "Cancelling in-flight call: $id")
                job.cancel()
                inFlightTasks.remove(id)
            }
        }
        bridge.setToolCallStatus(ToolCallStatus.Cancelled(ids.firstOrNull() ?: "unknown"))
    }

    fun cancelAll() {
        for ((id, job) in inFlightTasks) {
            Log.i(TAG, "Cancelling in-flight call: $id")
            job.cancel()
        }
        inFlightTasks.clear()
    }

    private fun buildToolResponse(
        callId: String,
        name: String,
        result: com.visionclaw.android.service.gemini.ToolResult,
    ): JSONObject {
        return JSONObject().apply {
            put("toolResponse", JSONObject().apply {
                put("functionResponses", JSONArray().put(
                    JSONObject().apply {
                        put("id", callId)
                        put("name", name)
                        put("response", result.responseValue())
                    }
                ))
            })
        }
    }

    companion object {
        private const val TAG = "ToolCallRouter"
    }
}
