import Foundation
import Security

enum KeychainStore {
  enum Key: String {
    case geminiApiKey = "gemini_api_key"
    case openClawGatewayToken = "openclaw_gateway_token"
    case deviceId = "device_id"
  }

  // Keep service stable across installs; account is the per-key name.
  private static let service = "VisionClaw"

  static func get(_ key: Key) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  static func set(_ value: String, for key: Key) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      delete(key)
      return
    }

    let data = Data(trimmed.utf8)
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
    ]

    let update: [String: Any] = [
      kSecValueData as String: data
    ]

    let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
    if status == errSecItemNotFound {
      let add: [String: Any] = query.merging(update) { _, new in new }
      _ = SecItemAdd(add as CFDictionary, nil)
    }
  }

  static func delete(_ key: Key) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key.rawValue,
    ]
    _ = SecItemDelete(query as CFDictionary)
  }
}

