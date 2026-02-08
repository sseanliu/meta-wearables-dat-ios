package com.visionclaw.android.service.gemini

import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for Gemini data models: parsing, serialization, status display.
 * These run on the JVM — no emulator needed.
 */
class GeminiModelsTest {

    // ---- GeminiToolCall parsing ----

    @Test
    fun `parse valid toolCall with one function`() {
        val json = JSONObject().apply {
            put("toolCall", JSONObject().apply {
                put("functionCalls", JSONArray().put(
                    JSONObject().apply {
                        put("id", "call_123")
                        put("name", "execute")
                        put("args", JSONObject().put("task", "search for cats"))
                    }
                ))
            })
        }

        val toolCall = GeminiToolCall.fromJson(json)
        assertNotNull(toolCall)
        assertEquals(1, toolCall!!.functionCalls.size)
        assertEquals("call_123", toolCall.functionCalls[0].id)
        assertEquals("execute", toolCall.functionCalls[0].name)
        assertEquals("search for cats", toolCall.functionCalls[0].args["task"])
    }

    @Test
    fun `parse toolCall with multiple functions`() {
        val json = JSONObject().apply {
            put("toolCall", JSONObject().apply {
                put("functionCalls", JSONArray()
                    .put(JSONObject().apply {
                        put("id", "call_1")
                        put("name", "execute")
                        put("args", JSONObject().put("task", "task one"))
                    })
                    .put(JSONObject().apply {
                        put("id", "call_2")
                        put("name", "execute")
                        put("args", JSONObject().put("task", "task two"))
                    })
                )
            })
        }

        val toolCall = GeminiToolCall.fromJson(json)
        assertNotNull(toolCall)
        assertEquals(2, toolCall!!.functionCalls.size)
        assertEquals("call_1", toolCall.functionCalls[0].id)
        assertEquals("call_2", toolCall.functionCalls[1].id)
    }

    @Test
    fun `parse toolCall with empty args`() {
        val json = JSONObject().apply {
            put("toolCall", JSONObject().apply {
                put("functionCalls", JSONArray().put(
                    JSONObject().apply {
                        put("id", "call_456")
                        put("name", "execute")
                        // no args key
                    }
                ))
            })
        }

        val toolCall = GeminiToolCall.fromJson(json)
        assertNotNull(toolCall)
        assertTrue(toolCall!!.functionCalls[0].args.isEmpty())
    }

    @Test
    fun `return null for non-toolCall message`() {
        val json = JSONObject().put("serverContent", JSONObject())
        assertNull(GeminiToolCall.fromJson(json))
    }

    @Test
    fun `return null for toolCall without functionCalls`() {
        val json = JSONObject().put("toolCall", JSONObject())
        assertNull(GeminiToolCall.fromJson(json))
    }

    @Test
    fun `skip function calls missing id or name`() {
        val json = JSONObject().apply {
            put("toolCall", JSONObject().apply {
                put("functionCalls", JSONArray()
                    .put(JSONObject().apply {
                        put("id", "good")
                        put("name", "execute")
                    })
                    .put(JSONObject().apply {
                        put("id", "")  // empty id
                        put("name", "execute")
                    })
                    .put(JSONObject().apply {
                        put("id", "also_good")
                        // missing name
                    })
                )
            })
        }

        val toolCall = GeminiToolCall.fromJson(json)
        assertNotNull(toolCall)
        assertEquals(1, toolCall!!.functionCalls.size)
        assertEquals("good", toolCall.functionCalls[0].id)
    }

    // ---- GeminiToolCallCancellation ----

    @Test
    fun `parse valid cancellation`() {
        val json = JSONObject().apply {
            put("toolCallCancellation", JSONObject().apply {
                put("ids", JSONArray().put("call_1").put("call_2"))
            })
        }

        val cancel = GeminiToolCallCancellation.fromJson(json)
        assertNotNull(cancel)
        assertEquals(listOf("call_1", "call_2"), cancel!!.ids)
    }

    @Test
    fun `return null for non-cancellation message`() {
        val json = JSONObject().put("setupComplete", JSONObject())
        assertNull(GeminiToolCallCancellation.fromJson(json))
    }

    // ---- ToolResult ----

    @Test
    fun `success result has correct JSON`() {
        val result = ToolResult.Success("task completed")
        val json = result.responseValue()
        assertEquals("task completed", json.getString("result"))
        assertFalse(json.has("error"))
    }

    @Test
    fun `failure result has correct JSON`() {
        val result = ToolResult.Failure("something broke")
        val json = result.responseValue()
        assertEquals("something broke", json.getString("error"))
        assertFalse(json.has("result"))
    }

    // ---- ToolCallStatus ----

    @Test
    fun `idle status has empty display text`() {
        assertEquals("", ToolCallStatus.Idle.displayText)
        assertFalse(ToolCallStatus.Idle.isActive)
    }

    @Test
    fun `executing status shows running`() {
        val status = ToolCallStatus.Executing("search")
        assertEquals("Running: search...", status.displayText)
        assertTrue(status.isActive)
    }

    @Test
    fun `completed status shows done`() {
        val status = ToolCallStatus.Completed("search")
        assertEquals("Done: search", status.displayText)
        assertFalse(status.isActive)
    }

    @Test
    fun `failed status shows error`() {
        val status = ToolCallStatus.Failed("search", "timeout")
        assertEquals("Failed: search - timeout", status.displayText)
        assertFalse(status.isActive)
    }

    @Test
    fun `cancelled status shows name`() {
        val status = ToolCallStatus.Cancelled("search")
        assertEquals("Cancelled: search", status.displayText)
        assertFalse(status.isActive)
    }

    // ---- ToolDeclarations ----

    @Test
    fun `declarations contain execute tool`() {
        val decls = ToolDeclarations.allDeclarations()
        assertEquals(1, decls.length())
        val exec = decls.getJSONObject(0)
        assertEquals("execute", exec.getString("name"))
        assertTrue(exec.has("parameters"))
        assertTrue(exec.has("description"))
    }

    @Test
    fun `execute tool has task parameter`() {
        val exec = ToolDeclarations.allDeclarations().getJSONObject(0)
        val params = exec.getJSONObject("parameters")
        assertEquals("object", params.getString("type"))
        assertTrue(params.getJSONObject("properties").has("task"))
        val required = params.getJSONArray("required")
        assertEquals("task", required.getString(0))
    }

    // ---- JSONObject.toMap() ----

    @Test
    fun `toMap converts JSON object to map`() {
        val json = JSONObject()
            .put("key1", "value1")
            .put("key2", 42)
            .put("key3", true)
        val map = json.toMap()
        assertEquals("value1", map["key1"])
        assertEquals(42, map["key2"])
        assertEquals(true, map["key3"])
    }

    @Test
    fun `toMap handles empty JSON`() {
        val map = JSONObject().toMap()
        assertTrue(map.isEmpty())
    }
}
