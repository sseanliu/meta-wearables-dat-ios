//
//  SecretsManager.swift
//  CameraAccess
//
//  Manages app secrets with device storage. Falls back to Secrets.swift defaults
//  when no stored values exist. Values are persisted in UserDefaults.
//

import Combine
import Foundation

class SecretsManager: ObservableObject {
  static let shared = SecretsManager()

  private enum Keys {
    static let geminiAPIKey = "secrets.geminiAPIKey"
    static let openClawHost = "secrets.openClawHost"
    static let openClawPort = "secrets.openClawPort"
    static let openClawHookToken = "secrets.openClawHookToken"
    static let openClawGatewayToken = "secrets.openClawGatewayToken"
    static let hasStoredValues = "secrets.hasStoredValues"
  }

  private let defaults = UserDefaults.standard

  @Published var geminiAPIKey: String
  @Published var openClawHost: String
  @Published var openClawPort: Int
  @Published var openClawHookToken: String
  @Published var openClawGatewayToken: String

  private init() {
    if defaults.bool(forKey: Keys.hasStoredValues) {
      self.geminiAPIKey = defaults.string(forKey: Keys.geminiAPIKey) ?? Secrets.geminiAPIKey
      self.openClawHost = defaults.string(forKey: Keys.openClawHost) ?? Secrets.openClawHost
      self.openClawPort = defaults.object(forKey: Keys.openClawPort) as? Int ?? Secrets.openClawPort
      self.openClawHookToken = defaults.string(forKey: Keys.openClawHookToken) ?? Secrets.openClawHookToken
      self.openClawGatewayToken = defaults.string(forKey: Keys.openClawGatewayToken) ?? Secrets.openClawGatewayToken
    } else {
      self.geminiAPIKey = Secrets.geminiAPIKey
      self.openClawHost = Secrets.openClawHost
      self.openClawPort = Secrets.openClawPort
      self.openClawHookToken = Secrets.openClawHookToken
      self.openClawGatewayToken = Secrets.openClawGatewayToken
      save()
    }
  }

  func save() {
    defaults.set(true, forKey: Keys.hasStoredValues)
    defaults.set(geminiAPIKey, forKey: Keys.geminiAPIKey)
    defaults.set(openClawHost, forKey: Keys.openClawHost)
    defaults.set(openClawPort, forKey: Keys.openClawPort)
    defaults.set(openClawHookToken, forKey: Keys.openClawHookToken)
    defaults.set(openClawGatewayToken, forKey: Keys.openClawGatewayToken)
  }

  func resetToDefaults() {
    geminiAPIKey = Secrets.geminiAPIKey
    openClawHost = Secrets.openClawHost
    openClawPort = Secrets.openClawPort
    openClawHookToken = Secrets.openClawHookToken
    openClawGatewayToken = Secrets.openClawGatewayToken
    save()
  }
}
