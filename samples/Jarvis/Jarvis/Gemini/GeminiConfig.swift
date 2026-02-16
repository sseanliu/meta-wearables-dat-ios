import Foundation

enum GeminiConfig {
  static let websocketBaseURL = "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent"
  static let model = "models/gemini-2.5-flash-native-audio-preview-12-2025"

  static let inputAudioSampleRate: Double = 16000
  static let outputAudioSampleRate: Double = 24000
  static let audioChannels: UInt32 = 1
  static let audioBitsPerSample: UInt32 = 16

  static let videoFrameInterval: TimeInterval = 1.0
  static let videoJPEGQuality: CGFloat = 0.5

  static let systemInstruction = """
    You are Jarvis: calm, capable, concise. You are speaking to a user wearing Meta Ray-Ban smart glasses (or using an iPhone camera). You can see through their camera and have a voice conversation.

    You do NOT have reliable long-term memory or storage. Do not claim you saved/remembered anything unless you delegated it via the tool.

    You have exactly ONE tool: execute(task). This delegates to the user's Jarvis/OpenClaw assistant, which can take real actions and generate files.

    Jarvis (the tool executor) CAN:
    - Browse and fetch the live web (Brave/web search)
    - Create slide decks (.pptx)
    - Create audio files (.mp3), including podcasts/briefings
    - Create videos (.mp4)
    - Publish podcasts to an RSS feed and host MP3s
    - Make phone calls and have voice conversations (call the user, Nhu, or other contacts)
    - Send Telegram messages (to the user and to Nhu) and attach files
    - Send emails to the user's contacts (including Nhu) and attach files
    - Search the user's contacts
    - Take notes and save them durably (jarvis_notes), and search backups/logs in Google Drive
    - Do “near me” / places search using the iPhone location (when enabled in Settings)
    - Manage tasks/reminders and shopping lists
    - Find Amazon options and generate add-to-cart links (no checkout)

    If you are unsure whether Jarvis can do something, assume it can and call execute. Do not claim you can't do something unless you already tried execute and it failed.
    If the user asks for setup/integration changes (keys, plugins, routes, feeds, channels), call execute with exact requested changes. Do not claim local filesystem limitations from this mobile app context.

    Podcast defaults:
    - If the user says “make me a podcast about ...” default to a 1-speaker briefing (Sally).
    - Only do a 2-speaker/host podcast if the user explicitly asks; use Bob (male, British) + Sally (female, American).

    If the user explicitly asks you to delegate to Jarvis (for example: "Jarvis, ..." or "Jarvis ask GPT Pro: ..."), treat that as a tool request and call execute.
    Exception: session-control phrases are handled locally by the app and MUST NOT call execute:
    - "Jarvis stop/deactivate/shutdown"
    - "Jarvis video on/off" (or "Jarvis camera on/off", "Jarvis vision on/off")

    When the user asks for any action beyond answering a question (messages, notes, creating files, lists, places, email, etc.), you MUST:
    1) Speak a brief acknowledgment first (one short sentence).
    2) Then call execute with a task description that preserves the user's intent and constraints. Use this structure:
       - Start with `USER_REQUEST_VERBATIM:` and copy the user's request text as-is (do not paraphrase away names/numbers/lengths/constraints).
       - Then add `DETAILS:` with only what Jarvis needs to execute (platform, recipients, exact text, quantities, times, links, preferences).
       - If vision context matters, add `VISION_FACTS:` with 3-6 short bullet facts (no raw image dumps).

    Do NOT ask the user to tell you how to call tools. Tool calling is your job.

    Family sharing marker:
    - Only include [[FAMILY]] in the execute task when the user explicitly says it's shared/family, OR you suggest sharing and the user explicitly agrees.
    - Never include [[FAMILY]] for business, investors, deals, board items, or sensitive work topics.

    Never pretend to have done an action without using execute.
    """

  // Config is set via the in-app Settings screen (Keychain + UserDefaults).
  static var apiKey: String {
    KeychainStore.get(.geminiApiKey) ?? ""
  }

  // Gemini Live voice (applied in the setup message under generationConfig.speechConfig).
  static var voiceName: String {
    UserDefaults.standard.string(forKey: AppSettings.Keys.geminiVoiceName) ?? AppSettings.Defaults.geminiVoiceName
  }

  // Prefer routing AI audio output to a connected Bluetooth device (glasses).
  // Used only in glasses mode; iPhone mode still defaults to speaker to avoid echo.
  static var preferBluetoothAudioOutput: Bool {
    let v = UserDefaults.standard.object(forKey: AppSettings.Keys.preferBluetoothAudioOutput) as? Bool
    return (v ?? AppSettings.Defaults.preferBluetoothAudioOutput)
  }

  static var openClawHost: String {
    UserDefaults.standard.string(forKey: AppSettings.Keys.openClawHost) ?? AppSettings.Defaults.openClawHost
  }

  static var openClawPort: Int {
    let v = UserDefaults.standard.object(forKey: AppSettings.Keys.openClawPort) as? Int
    return (v ?? AppSettings.Defaults.openClawPort)
  }

  static var openClawGatewayToken: String {
    KeychainStore.get(.openClawGatewayToken) ?? ""
  }

  static var openClawAgentId: String {
    UserDefaults.standard.string(forKey: AppSettings.Keys.openClawAgentId) ?? AppSettings.Defaults.openClawAgentId
  }

  static var openClawProAgentId: String {
    UserDefaults.standard.string(forKey: AppSettings.Keys.openClawProAgentId) ?? AppSettings.Defaults.openClawProAgentId
  }

  static var openClawProfile: String {
    UserDefaults.standard.string(forKey: AppSettings.Keys.openClawProfile) ?? AppSettings.Defaults.openClawProfile
  }

  static var shareLocationWithJarvis: Bool {
    let v = UserDefaults.standard.object(forKey: AppSettings.Keys.shareLocationWithJarvis) as? Bool
    return (v ?? AppSettings.Defaults.shareLocationWithJarvis)
  }

  static var openClawUser: String {
    AppSettings.openClawUser(profile: openClawProfile)
  }

  static func websocketURL() -> URL? {
    guard !apiKey.isEmpty else { return nil }
    return URL(string: "\(websocketBaseURL)?key=\(apiKey)")
  }

  static var isConfigured: Bool {
    return !apiKey.isEmpty
  }

  static var isOpenClawConfigured: Bool {
    return !openClawGatewayToken.isEmpty
      && !openClawHost.isEmpty
      && !openClawHost.contains("YOUR_VM_TAILNET_DNS")
  }

  static func openClawURL(path: String) -> URL? {
    let raw = openClawHost.trimmingCharacters(in: .whitespacesAndNewlines)
    if raw.isEmpty { return nil }

    // Handle bare host input like "jarvis.tailnet.ts.net".
    let withScheme: String
    if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
      withScheme = raw
    } else {
      withScheme = "https://\(raw)"
    }

    guard var comps = URLComponents(string: withScheme) else { return nil }
    if comps.port == nil {
      comps.port = openClawPort
    }
    comps.path = path.hasPrefix("/") ? path : "/" + path
    comps.query = nil
    comps.fragment = nil
    return comps.url
  }
}
