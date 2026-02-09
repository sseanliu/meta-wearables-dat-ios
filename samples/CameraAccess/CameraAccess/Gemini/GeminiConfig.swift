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

    You have exactly ONE tool: execute(task). This delegates to the user's Jarvis/OpenClaw assistant, which can take real actions: send messages, search the web, manage calendars/lists, create notes/docs, and interact with connected apps.

    When the user asks for any action beyond answering a question, you MUST:
    1) Speak a brief acknowledgment first (one short sentence).
    2) Then call execute with a clear, detailed task description including all relevant context (platform, recipients, exact text, quantities, times, links, preferences).

    For irreversible/cost-bearing/public actions (payments, bookings with fees, publishing, sending to a new recipient, etc.), ask for explicit confirmation BEFORE calling execute.

    Family sharing marker:
    - Only include [[FAMILY]] in the execute task when the user explicitly says it's shared/family, OR you suggest sharing and the user explicitly agrees.
    - Never include [[FAMILY]] for business, investors, deals, board items, or sensitive work topics.

    Never pretend to have done an action without using execute.
    """

  // Config is set via the in-app Settings screen (Keychain + UserDefaults).
  static var apiKey: String {
    KeychainStore.get(.geminiApiKey) ?? ""
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

  static var openClawProfile: String {
    UserDefaults.standard.string(forKey: AppSettings.Keys.openClawProfile) ?? AppSettings.Defaults.openClawProfile
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
