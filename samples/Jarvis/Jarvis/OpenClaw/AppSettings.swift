import Foundation

enum AppSettings {
  enum Defaults {
    // Fill these in from the in-app Settings screen.
    static let openClawHost = "https://YOUR_VM_TAILNET_DNS"
    static let openClawPort = 8444
    // Jarvis repo defaults to `JARVIS_Main` as the canonical "smart Jarvis" agent.
    static let openClawAgentId = "JARVIS_Main"
    // Used when the user explicitly asks for an expensive "GPT Pro" query (e.g., "Jarvis ask GPT Pro: ...").
    static let openClawProAgentId = "JARVIS_Guard"
    static let openClawProfile = "default"

    // When enabled, the app includes one-shot device location metadata in OpenClaw tool calls
    // (sent only to the Jarvis gateway, not to Gemini Live).
    static let shareLocationWithJarvis = false

    // Gemini Live voice configuration (applied in the setup message).
    // If empty, the API defaults to "Puck".
    static let geminiVoiceName = "Puck"

    // When enabled (recommended for Meta Ray-Bans), prefer routing AI audio output
    // to a connected Bluetooth headset (glasses). This can cause echo if the mic
    // also comes from the same headset; we mitigate with echo-gating + voiceChat mode.
    static let preferBluetoothAudioOutput = true

    // QoL defaults for using Jarvis hands-free with glasses.
    // - Auto-start is intentionally OFF: Jarvis should only launch when explicitly requested (Siri or a tap).
    // - Hiding the preview keeps the phone usable in-pocket without showing POV video.
    static let autoStartWithGlasses = false
    // When enabled, opening the app will auto-connect glasses (if needed) and start
    // the glasses AI experience as soon as a device is active.
    static let autoStartOnAppOpen = true
    static let showVideoPreviewOnPhone = false

    // When enabled, saying "Jarvis stop/deactivate" will end the glasses experience and
    // also close the app so Siri can "Start Jarvis" again cleanly.
    static let closeAppOnDeactivate = true
  }

  enum Keys {
    static let openClawHost = "visionclaw.openclaw.host"
    static let openClawPort = "visionclaw.openclaw.port"
    static let openClawAgentId = "visionclaw.openclaw.agent_id"
    static let openClawProAgentId = "visionclaw.openclaw.pro_agent_id"
    static let openClawProfile = "visionclaw.openclaw.profile"
    static let shareLocationWithJarvis = "visionclaw.openclaw.share_location"
    static let geminiVoiceName = "visionclaw.gemini.voice_name"
    static let preferBluetoothAudioOutput = "visionclaw.audio.prefer_bluetooth_output"
    static let autoStartWithGlasses = "visionclaw.glasses.auto_start_ai"
    static let autoStartOnAppOpen = "visionclaw.glasses.auto_start_on_app_open"
    static let showVideoPreviewOnPhone = "visionclaw.ui.show_video_preview"
    static let closeAppOnDeactivate = "visionclaw.ui.close_on_deactivate"

    // Internal one-shot signals (Siri / Shortcuts, deep links, etc.)
    static let forceAutoStartOnce = "visionclaw.runtime.force_autostart_once"
  }

  static func deviceId() -> String {
    if let existing = KeychainStore.get(.deviceId), !existing.isEmpty {
      return existing
    }
    let new = UUID().uuidString.lowercased()
    KeychainStore.set(new, for: .deviceId)
    return new
  }

  static func openClawUser(profile: String) -> String {
    let p = profile.trimmingCharacters(in: .whitespacesAndNewlines)
    let profilePart = p.isEmpty ? "default" : p
    return "visionclaw:\(deviceId()):\(profilePart)"
  }
}
