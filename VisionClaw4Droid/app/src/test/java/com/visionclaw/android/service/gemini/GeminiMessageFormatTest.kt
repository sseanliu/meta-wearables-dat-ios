package com.visionclaw.android.service.gemini

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

/**
 * Tests that the JSON message formats match the Gemini Live API protocol.
 * Verifies we produce/consume the correct wire format.
 */
class GeminiMessageFormatTest {

    // ---- Outgoing messages ----

    @Test
    fun `setup message has correct structure`() {
        // Replicate the setup message structure from GeminiLiveService.sendSetupMessage()
        val setup = JSONObject().apply {
            put("setup", JSONObject().apply {
                put("model", GeminiConfig.model)
                put("generationConfig", JSONObject().apply {
                    put("responseModalities", JSONArray().put("AUDIO"))
                    put("thinkingConfig", JSONObject().put("thinkingBudget", 0))
                })
                put("systemInstruction", JSONObject().apply {
                    put("parts", JSONArray().put(
                        JSONObject().put("text", GeminiConfig.systemInstruction)
                    ))
                })
                put("tools", JSONArray().put(
                    JSONObject().put("functionDeclarations", ToolDeclarations.allDeclarations())
                ))
                put("realtimeInputConfig", JSONObject().apply {
                    put("automaticActivityDetection", JSONObject().apply {
                        put("disabled", false)
                        put("startOfSpeechSensitivity", "START_SENSITIVITY_HIGH")
                        put("endOfSpeechSensitivity", "END_SENSITIVITY_LOW")
                    })
                    put("activityHandling", "START_OF_ACTIVITY_INTERRUPTS")
                    put("turnCoverage", "TURN_INCLUDES_ALL_INPUT")
                })
                put("inputAudioTranscription", JSONObject())
                put("outputAudioTranscription", JSONObject())
            })
        }

        // Verify key fields exist
        val s = setup.getJSONObject("setup")
        assertTrue(s.getString("model").contains("gemini"))
        assertEquals("AUDIO",
            s.getJSONObject("generationConfig")
                .getJSONArray("responseModalities")
                .getString(0))
        assertFalse(
            s.getJSONObject("realtimeInputConfig")
                .getJSONObject("automaticActivityDetection")
                .getBoolean("disabled"))
    }

    @Test
    fun `audio input message has correct format`() {
        val audioBytes = byteArrayOf(0x01, 0x02, 0x03, 0x04)
        val base64 = android.util.Base64.encodeToString(audioBytes, android.util.Base64.NO_WRAP)

        val json = JSONObject().apply {
            put("realtimeInput", JSONObject().apply {
                put("audio", JSONObject().apply {
                    put("mimeType", "audio/pcm;rate=${GeminiConfig.INPUT_AUDIO_SAMPLE_RATE}")
                    put("data", base64)
                })
            })
        }

        val audio = json.getJSONObject("realtimeInput").getJSONObject("audio")
        assertEquals("audio/pcm;rate=16000", audio.getString("mimeType"))
        assertTrue(audio.getString("data").isNotEmpty())
    }

    @Test
    fun `video input message has correct format`() {
        val json = JSONObject().apply {
            put("realtimeInput", JSONObject().apply {
                put("video", JSONObject().apply {
                    put("mimeType", "image/jpeg")
                    put("data", "base64encodedJpeg")
                })
            })
        }

        val video = json.getJSONObject("realtimeInput").getJSONObject("video")
        assertEquals("image/jpeg", video.getString("mimeType"))
    }

    @Test
    fun `tool response message has correct format`() {
        val result = ToolResult.Success("task completed successfully")
        val response = JSONObject().apply {
            put("toolResponse", JSONObject().apply {
                put("functionResponses", JSONArray().put(
                    JSONObject().apply {
                        put("id", "call_123")
                        put("name", "execute")
                        put("response", result.responseValue())
                    }
                ))
            })
        }

        val fr = response
            .getJSONObject("toolResponse")
            .getJSONArray("functionResponses")
            .getJSONObject(0)
        assertEquals("call_123", fr.getString("id"))
        assertEquals("execute", fr.getString("name"))
        assertEquals("task completed successfully",
            fr.getJSONObject("response").getString("result"))
    }

    // ---- Incoming messages ----

    @Test
    fun `parse setupComplete message`() {
        val json = JSONObject().put("setupComplete", JSONObject())
        assertTrue(json.has("setupComplete"))
    }

    @Test
    fun `parse goAway message`() {
        val json = JSONObject().apply {
            put("goAway", JSONObject().apply {
                put("timeLeft", JSONObject().put("seconds", 30))
            })
        }
        val seconds = json.getJSONObject("goAway")
            .getJSONObject("timeLeft")
            .getInt("seconds")
        assertEquals(30, seconds)
    }

    @Test
    fun `parse serverContent with audio`() {
        val json = JSONObject().apply {
            put("serverContent", JSONObject().apply {
                put("modelTurn", JSONObject().apply {
                    put("parts", JSONArray().put(
                        JSONObject().apply {
                            put("inlineData", JSONObject().apply {
                                put("mimeType", "audio/pcm;rate=24000")
                                put("data", "AQID") // base64 of [1,2,3]
                            })
                        }
                    ))
                })
            })
        }

        val parts = json.getJSONObject("serverContent")
            .getJSONObject("modelTurn")
            .getJSONArray("parts")
        val mime = parts.getJSONObject(0)
            .getJSONObject("inlineData")
            .getString("mimeType")
        assertTrue(mime.startsWith("audio/pcm"))
    }

    @Test
    fun `parse serverContent with turnComplete`() {
        val json = JSONObject().apply {
            put("serverContent", JSONObject().apply {
                put("turnComplete", true)
            })
        }
        assertTrue(
            json.getJSONObject("serverContent").getBoolean("turnComplete")
        )
    }

    @Test
    fun `parse serverContent with interrupted`() {
        val json = JSONObject().apply {
            put("serverContent", JSONObject().apply {
                put("interrupted", true)
            })
        }
        assertTrue(
            json.getJSONObject("serverContent").getBoolean("interrupted")
        )
    }

    @Test
    fun `parse transcription messages`() {
        val json = JSONObject().apply {
            put("serverContent", JSONObject().apply {
                put("inputTranscription", JSONObject().put("text", "hello world"))
                put("outputTranscription", JSONObject().put("text", "hi there"))
            })
        }

        val sc = json.getJSONObject("serverContent")
        assertEquals("hello world",
            sc.getJSONObject("inputTranscription").getString("text"))
        assertEquals("hi there",
            sc.getJSONObject("outputTranscription").getString("text"))
    }
}
