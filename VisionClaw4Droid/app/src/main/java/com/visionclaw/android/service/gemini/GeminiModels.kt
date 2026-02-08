package com.visionclaw.android.service.gemini

import org.json.JSONArray
import org.json.JSONObject

/** Parsed function call from Gemini's toolCall message. */
data class GeminiFunctionCall(
    val id: String,
    val name: String,
    val args: Map<String, Any?>,
)

/** Parsed toolCall wrapper containing one or more function calls. */
data class GeminiToolCall(
    val functionCalls: List<GeminiFunctionCall>,
) {
    companion object {
        fun fromJson(json: JSONObject): GeminiToolCall? {
            val toolCall = json.optJSONObject("toolCall") ?: return null
            val calls = toolCall.optJSONArray("functionCalls") ?: return null
            val list = mutableListOf<GeminiFunctionCall>()
            for (i in 0 until calls.length()) {
                val c = calls.getJSONObject(i)
                val id = c.optString("id", "").takeIf { it.isNotEmpty() } ?: continue
                val name = c.optString("name", "").takeIf { it.isNotEmpty() } ?: continue
                val argsObj = c.optJSONObject("args")
                val argsMap = argsObj?.toMap() ?: emptyMap()
                list.add(GeminiFunctionCall(id, name, argsMap))
            }
            return if (list.isNotEmpty()) GeminiToolCall(list) else null
        }
    }
}

/** Parsed toolCallCancellation from Gemini. */
data class GeminiToolCallCancellation(
    val ids: List<String>,
) {
    companion object {
        fun fromJson(json: JSONObject): GeminiToolCallCancellation? {
            val cancellation = json.optJSONObject("toolCallCancellation") ?: return null
            val idsArr = cancellation.optJSONArray("ids") ?: return null
            val list = mutableListOf<String>()
            for (i in 0 until idsArr.length()) {
                list.add(idsArr.getString(i))
            }
            return if (list.isNotEmpty()) GeminiToolCallCancellation(list) else null
        }
    }
}

/** Tool result returned to Gemini after OpenClaw execution. */
sealed class ToolResult {
    data class Success(val result: String) : ToolResult()
    data class Failure(val error: String) : ToolResult()

    fun responseValue(): JSONObject = when (this) {
        is Success -> JSONObject().put("result", result)
        is Failure -> JSONObject().put("error", error)
    }
}

/** UI-facing status of the current tool call. */
sealed class ToolCallStatus {
    data object Idle : ToolCallStatus()
    data class Executing(val name: String) : ToolCallStatus()
    data class Completed(val name: String) : ToolCallStatus()
    data class Failed(val name: String, val error: String) : ToolCallStatus()
    data class Cancelled(val name: String) : ToolCallStatus()

    val displayText: String
        get() = when (this) {
            is Idle -> ""
            is Executing -> "Running: $name..."
            is Completed -> "Done: $name"
            is Failed -> "Failed: $name - $error"
            is Cancelled -> "Cancelled: $name"
        }

    val isActive: Boolean get() = this is Executing
}

/** Tool declarations sent in the Gemini setup message. */
object ToolDeclarations {
    fun allDeclarations(): JSONArray = JSONArray().put(execute)

    private val execute: JSONObject
        get() = JSONObject().apply {
            put("name", "execute")
            put("description",
                "Your only way to take action. You have no memory, storage, or ability to do " +
                "anything on your own -- use this tool for everything: sending messages, searching " +
                "the web, adding to lists, setting reminders, creating notes, research, drafts, " +
                "scheduling, smart home control, app interactions, or any request that goes beyond " +
                "answering a question. When in doubt, use this tool.")
            put("parameters", JSONObject().apply {
                put("type", "object")
                put("properties", JSONObject().apply {
                    put("task", JSONObject().apply {
                        put("type", "string")
                        put("description",
                            "Clear, detailed description of what to do. Include all relevant context: " +
                            "names, content, platforms, quantities, etc.")
                    })
                })
                put("required", JSONArray().put("task"))
            })
            put("behavior", "BLOCKING")
        }
}

/** Utility: JSONObject → Map */
fun JSONObject.toMap(): Map<String, Any?> {
    val map = mutableMapOf<String, Any?>()
    for (key in keys()) {
        map[key] = opt(key)
    }
    return map
}
