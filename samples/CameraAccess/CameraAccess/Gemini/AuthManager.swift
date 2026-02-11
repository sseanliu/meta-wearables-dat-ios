//
//  AuthManager.swift
//  CameraAccess
//
//  Manages PIN and Face ID authentication for the Secrets view.
//  PIN is stored hashed in Keychain. Face ID preference in UserDefaults.
//

import Foundation
import LocalAuthentication
import Security

final class AuthManager: ObservableObject {
  static let shared = AuthManager()

  private enum Keys {
    static let pinHash = "com.cameraaccess.secrets.pinHash"
    static let useFaceID = "secrets.useFaceID"
  }

  private let defaults = UserDefaults.standard

  @Published var isUnlocked = false
  @Published var useFaceID: Bool {
    didSet { defaults.set(useFaceID, forKey: Keys.useFaceID) }
  }

  var hasPIN: Bool {
    KeychainHelper.load(key: Keys.pinHash) != nil
  }

  var isFaceIDAvailable: Bool {
    let context = LAContext()
    var error: NSError?
    return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
  }

  private init() {
    self.useFaceID = defaults.object(forKey: Keys.useFaceID) as? Bool ?? true
  }

  func setPIN(_ pin: String) -> Bool {
    guard pin.count >= 4 else { return false }
    let hash = pin.sha256Hash
    return KeychainHelper.save(key: Keys.pinHash, value: hash)
  }

  func verifyPIN(_ pin: String) -> Bool {
    guard let stored = KeychainHelper.load(key: Keys.pinHash) else { return false }
    return pin.sha256Hash == stored
  }

  func authenticateWithFaceID(reason: String = "Unlock secrets") async -> Bool {
    let context = LAContext()
    var error: NSError?

    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
      return false
    }

    do {
      let success = try await context.evaluatePolicy(
        .deviceOwnerAuthenticationWithBiometrics,
        localizedReason: reason
      )
      await MainActor.run { isUnlocked = success }
      return success
    } catch {
      return false
    }
  }

  func unlock(withPIN pin: String) -> Bool {
    let ok = verifyPIN(pin)
    if ok { isUnlocked = true }
    return ok
  }

  func lock() {
    isUnlocked = false
  }

  func removePIN() {
    KeychainHelper.delete(key: Keys.pinHash)
    useFaceID = false
    isUnlocked = false
  }
}

// MARK: - Keychain Helper

private enum KeychainHelper {
  static func save(key: String, value: String) -> Bool {
    guard let data = value.data(using: .utf8) else { return false }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecValueData as String: data,
      kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
    ]
    SecItemDelete(query as CFDictionary) // Remove existing
    let status = SecItemAdd(query as CFDictionary, nil)
    return status == errSecSuccess
  }

  static func load(key: String) -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    guard status == errSecSuccess,
          let data = result as? Data,
          let string = String(data: data, encoding: .utf8) else { return nil }
    return string
  }

  static func delete(key: String) {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrAccount as String: key,
    ]
    SecItemDelete(query as CFDictionary)
  }
}

// MARK: - SHA256 Hash

private extension String {
  var sha256Hash: String {
    guard let data = data(using: .utf8) else { return "" }
    let hash = SHA256.hash(data: data)
    return hash.map { String(format: "%02x", $0) }.joined()
  }
}

import CryptoKit
