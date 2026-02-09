import Foundation

enum AppSettings {
  enum Defaults {
    // Fill these in from the in-app Settings screen.
    static let openClawHost = "https://YOUR_VM_TAILNET_DNS"
    static let openClawPort = 8444
    // Jarvis repo defaults to `JARVIS_Main` as the canonical "smart Jarvis" agent.
    static let openClawAgentId = "JARVIS_Main"
    static let openClawProfile = "default"
  }

  enum Keys {
    static let openClawHost = "visionclaw.openclaw.host"
    static let openClawPort = "visionclaw.openclaw.port"
    static let openClawAgentId = "visionclaw.openclaw.agent_id"
    static let openClawProfile = "visionclaw.openclaw.profile"
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
