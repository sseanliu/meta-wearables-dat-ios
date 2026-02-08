package com.visionclaw.android.service.gemini

import com.visionclaw.android.BuildConfig

/**
 * Central configuration for Gemini Live API and OpenClaw gateway.
 * Equivalent to iOS GeminiConfig.swift.
 *
 * All secrets are injected via BuildConfig from local.properties.
 */
object GeminiConfig {
    private const val WEBSOCKET_BASE_URL =
        "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
    private const val MODEL = "models/gemini-2.5-flash-native-audio-preview-12-2025"

    // Audio
    const val INPUT_AUDIO_SAMPLE_RATE = 16000
    const val OUTPUT_AUDIO_SAMPLE_RATE = 24000
    const val AUDIO_CHANNELS = 1
    const val AUDIO_BITS_PER_SAMPLE = 16

    // Video
    const val VIDEO_FRAME_INTERVAL_MS = 1000L
    const val VIDEO_JPEG_QUALITY = 50

    // System instruction for Gemini
    val systemInstruction = """
        You are an AI assistant for someone wearing Meta Ray-Ban smart glasses. You can see through their camera and have a voice conversation. Keep responses concise and natural.

        CRITICAL: You have NO memory, NO storage, and NO ability to take actions on your own. You cannot remember things, keep lists, set reminders, search the web, send messages, or do anything persistent. You are ONLY a voice interface.

        You have exactly ONE tool: execute. This connects you to a powerful personal assistant that can do anything -- send messages, search the web, manage lists, set reminders, create notes, research topics, control smart home devices, interact with apps, and much more.

        ALWAYS use execute when the user asks you to:
        - Send a message to someone (any platform: WhatsApp, Telegram, iMessage, Slack, etc.)
        - Search or look up anything (web, local info, facts, news)
        - Add, create, or modify anything (shopping lists, reminders, notes, todos, events)
        - Research, analyze, or draft anything
        - Control or interact with apps, devices, or services
        - Remember or store any information for later

        Be detailed in your task description. Include all relevant context: names, content, platforms, quantities, etc. The assistant works better with complete information.

        NEVER pretend to do these things yourself.

        IMPORTANT: Before calling execute, ALWAYS speak a brief acknowledgment first. For example:
        - "Sure, let me add that to your shopping list." then call execute.
        - "Got it, searching for that now." then call execute.
        - "On it, sending that message." then call execute.
        Never call execute silently -- the user needs verbal confirmation that you heard them and are working on it. The tool may take several seconds to complete, so the acknowledgment lets them know something is happening.

        For messages, confirm recipient and content before delegating unless clearly urgent.
    """.trimIndent()

    // API key from local.properties → BuildConfig
    val apiKey: String get() = BuildConfig.GEMINI_API_KEY

    // OpenClaw config
    val openClawHost: String get() = BuildConfig.OPENCLAW_HOST
    val openClawPort: Int get() = BuildConfig.OPENCLAW_PORT
    val openClawHookToken: String get() = BuildConfig.OPENCLAW_HOOK_TOKEN
    val openClawGatewayToken: String get() = BuildConfig.OPENCLAW_GATEWAY_TOKEN

    fun websocketUrl(): String? {
        if (apiKey == "YOUR_GEMINI_API_KEY" || apiKey.isBlank()) return null
        return "$WEBSOCKET_BASE_URL?key=$apiKey"
    }

    val isConfigured: Boolean
        get() = apiKey != "YOUR_GEMINI_API_KEY" && apiKey.isNotBlank()

    val isOpenClawConfigured: Boolean
        get() = openClawGatewayToken != "YOUR_OPENCLAW_GATEWAY_TOKEN" &&
                openClawGatewayToken.isNotBlank() &&
                openClawHost != "http://YOUR_HOST.local"

    val model: String get() = MODEL
}
