package com.visionclaw.android.service.gemini

import org.junit.Assert.*
import org.junit.Test

/**
 * Unit tests for GeminiConfig.
 * Note: BuildConfig values are injected at build time. In JVM tests, BuildConfig
 * fields may use defaults. These tests verify the logic around the config checks.
 */
class GeminiConfigTest {

    @Test
    fun `system instruction is non-empty`() {
        assertTrue(GeminiConfig.systemInstruction.isNotBlank())
        assertTrue(GeminiConfig.systemInstruction.contains("execute"))
    }

    @Test
    fun `audio sample rates are correct`() {
        assertEquals(16000, GeminiConfig.INPUT_AUDIO_SAMPLE_RATE)
        assertEquals(24000, GeminiConfig.OUTPUT_AUDIO_SAMPLE_RATE)
        assertEquals(1, GeminiConfig.AUDIO_CHANNELS)
        assertEquals(16, GeminiConfig.AUDIO_BITS_PER_SAMPLE)
    }

    @Test
    fun `video config values`() {
        assertEquals(1000L, GeminiConfig.VIDEO_FRAME_INTERVAL_MS)
        assertEquals(50, GeminiConfig.VIDEO_JPEG_QUALITY)
    }

    @Test
    fun `model name is set`() {
        assertTrue(GeminiConfig.model.startsWith("models/"))
        assertTrue(GeminiConfig.model.contains("gemini"))
    }
}
