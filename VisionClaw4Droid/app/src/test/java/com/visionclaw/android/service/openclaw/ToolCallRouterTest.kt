package com.visionclaw.android.service.openclaw

import com.visionclaw.android.service.gemini.GeminiFunctionCall
import com.visionclaw.android.service.gemini.ToolCallStatus
import com.visionclaw.android.service.gemini.ToolResult
import kotlinx.coroutines.*
import kotlinx.coroutines.test.runTest
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for ToolCallRouter: routing, response building, cancellation.
 */
class ToolCallRouterTest {

    /** Fake bridge that records calls and returns a canned result. */
    private class FakeBridge : OpenClawBridge() {
        var lastTask: String? = null
        var resultToReturn: ToolResult = ToolResult.Success("done")

        override suspend fun delegateTask(task: String, toolName: String): ToolResult {
            lastTask = task
            return resultToReturn
        }
    }

    @Test
    fun `handleToolCall routes task to bridge and returns response`() = runTest {
        val bridge = FakeBridge()
        bridge.resultToReturn = ToolResult.Success("search completed")
        val router = ToolCallRouter(bridge, this)

        var response: JSONObject? = null
        val call = GeminiFunctionCall("id_1", "execute", mapOf("task" to "find cats"))

        router.handleToolCall(call) { response = it }

        // Wait for the coroutine to complete
        advanceUntilIdle()

        assertNotNull(response)
        assertEquals("find cats", bridge.lastTask)

        // Verify response structure
        val toolResponse = response!!.getJSONObject("toolResponse")
        val funcResponses = toolResponse.getJSONArray("functionResponses")
        assertEquals(1, funcResponses.length())
        val fr = funcResponses.getJSONObject(0)
        assertEquals("id_1", fr.getString("id"))
        assertEquals("execute", fr.getString("name"))
        assertEquals("search completed", fr.getJSONObject("response").getString("result"))
    }

    @Test
    fun `handleToolCall uses args toString when no task key`() = runTest {
        val bridge = FakeBridge()
        val router = ToolCallRouter(bridge, this)

        val call = GeminiFunctionCall("id_2", "execute", mapOf("foo" to "bar"))
        router.handleToolCall(call) {}
        advanceUntilIdle()

        // Should pass the full args map as string since no "task" key
        assertNotNull(bridge.lastTask)
        assertTrue(bridge.lastTask!!.contains("foo"))
    }

    @Test
    fun `cancelToolCalls cancels in-flight jobs`() = runTest {
        val bridge = FakeBridge()
        bridge.resultToReturn = ToolResult.Success("ok")

        val router = ToolCallRouter(bridge, this)

        // Start a call that will be slow
        val slowBridge = object : OpenClawBridge() {
            override suspend fun delegateTask(task: String, toolName: String): ToolResult {
                delay(10_000) // Very slow
                return ToolResult.Success("should not reach")
            }
        }
        val slowRouter = ToolCallRouter(slowBridge, this)

        var responseReceived = false
        val call = GeminiFunctionCall("id_slow", "execute", mapOf("task" to "slow task"))
        slowRouter.handleToolCall(call) { responseReceived = true }

        // Cancel before it completes
        slowRouter.cancelToolCalls(listOf("id_slow"))
        advanceUntilIdle()

        assertFalse(responseReceived)
    }

    @Test
    fun `cancelAll cancels all in-flight jobs`() = runTest {
        val bridge = object : OpenClawBridge() {
            override suspend fun delegateTask(task: String, toolName: String): ToolResult {
                delay(10_000)
                return ToolResult.Success("should not reach")
            }
        }
        val router = ToolCallRouter(bridge, this)

        var count = 0
        router.handleToolCall(GeminiFunctionCall("a", "execute", mapOf("task" to "1"))) { count++ }
        router.handleToolCall(GeminiFunctionCall("b", "execute", mapOf("task" to "2"))) { count++ }

        router.cancelAll()
        advanceUntilIdle()

        assertEquals(0, count)
    }

    @Test
    fun `failure result builds correct response`() = runTest {
        val bridge = FakeBridge()
        bridge.resultToReturn = ToolResult.Failure("network error")
        val router = ToolCallRouter(bridge, this)

        var response: JSONObject? = null
        router.handleToolCall(
            GeminiFunctionCall("id_fail", "execute", mapOf("task" to "fail"))
        ) { response = it }
        advanceUntilIdle()

        val fr = response!!
            .getJSONObject("toolResponse")
            .getJSONArray("functionResponses")
            .getJSONObject(0)
        assertEquals("network error", fr.getJSONObject("response").getString("error"))
    }
}
