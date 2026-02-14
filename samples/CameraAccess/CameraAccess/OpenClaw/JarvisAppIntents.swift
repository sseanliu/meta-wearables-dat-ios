import AppIntents
import Foundation

// Siri/Shortcuts entrypoints.
// Goal: allow "Start Jarvis" to work while the phone is locked.

struct StartJarvisIntent: AppIntent {
  static var title: LocalizedStringResource = "Start Jarvis"
  static var description = IntentDescription("Opens Jarvis and starts a hands-free glasses session.")

  static var openAppWhenRun: Bool = true
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  @MainActor
  func perform() async throws -> some IntentResult {
    // One-shot override so NonStreamView will auto-start even if a prior stop disabled auto-start.
    UserDefaults.standard.set(true, forKey: AppSettings.Keys.forceAutoStartOnce)
    return .result()
  }
}

struct StopJarvisIntent: AppIntent {
  static var title: LocalizedStringResource = "Stop Jarvis"
  static var description = IntentDescription("Stops the current Jarvis session.")

  static var openAppWhenRun: Bool = true
  static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

  @MainActor
  func perform() async throws -> some IntentResult {
    NotificationCenter.default.post(name: .jarvisStopRequested, object: nil)
    return .result()
  }
}

extension Notification.Name {
  static let jarvisStopRequested = Notification.Name("jarvis.stop_requested")
}

struct JarvisShortcuts: AppShortcutsProvider {
  static var shortcutTileColor: ShortcutTileColor = .blue

  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: StartJarvisIntent(),
      phrases: [
        "Start \(.applicationName)",
        "Activate \(.applicationName)",
        "Open \(.applicationName)",
      ],
      shortTitle: "Start Jarvis",
      systemImageName: "sparkles"
    )

    AppShortcut(
      intent: StopJarvisIntent(),
      phrases: [
        "Stop \(.applicationName)",
        "Deactivate \(.applicationName)",
      ],
      shortTitle: "Stop Jarvis",
      systemImageName: "xmark.circle"
    )
  }
}
