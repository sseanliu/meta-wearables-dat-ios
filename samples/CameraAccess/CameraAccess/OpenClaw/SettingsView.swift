import SwiftUI

struct SettingsView: View {
  @Environment(\.dismiss) private var dismiss

  @AppStorage(AppSettings.Keys.openClawHost) private var openClawHost: String = AppSettings.Defaults.openClawHost
  @AppStorage(AppSettings.Keys.openClawPort) private var openClawPort: Int = AppSettings.Defaults.openClawPort
  @AppStorage(AppSettings.Keys.openClawAgentId) private var openClawAgentId: String = AppSettings.Defaults.openClawAgentId
  @AppStorage(AppSettings.Keys.openClawProfile) private var openClawProfile: String = AppSettings.Defaults.openClawProfile
  @AppStorage(AppSettings.Keys.geminiVoiceName) private var geminiVoiceName: String = AppSettings.Defaults.geminiVoiceName

  @State private var geminiApiKey: String = ""
  @State private var openClawGatewayToken: String = ""

  @State private var isTesting: Bool = false
  @State private var testOutput: String = ""

  private var openClawUser: String {
    AppSettings.openClawUser(profile: openClawProfile)
  }

  private var geminiConfigured: Bool {
    !geminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  private var openClawConfigured: Bool {
    let tokenOk = !openClawGatewayToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    let hostOk = !openClawHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && !openClawHost.contains("YOUR_VM_TAILNET_DNS")
    return tokenOk && hostOk
  }

  var body: some View {
    NavigationView {
      Form {
        Section("Gemini") {
          SecureField("Gemini API Key", text: $geminiApiKey)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)

          Picker("Voice", selection: $geminiVoiceName) {
            // Default voice per Gemini Live docs.
            Text("Puck (default)").tag("Puck")

            // A small curated set first; user can also type a custom voice name
            // by editing this setting in the future if desired.
            Text("Fenrir").tag("Fenrir")
            Text("Zephyr").tag("Zephyr")
            Text("Kore").tag("Kore")
            Text("Orus").tag("Orus")
            Text("Aoede").tag("Aoede")
            Text("Charon").tag("Charon")
            Text("Leda").tag("Leda")
            Text("Alnilam").tag("Alnilam")
          }
          .pickerStyle(.navigationLink)

          Text("Voice is applied when starting a new AI session.")
            .font(.caption)
            .foregroundColor(.secondary)

          Text(geminiConfigured ? "Configured" : "Not configured")
            .foregroundColor(geminiConfigured ? .green : .secondary)
        }

        Section("OpenClaw (Jarvis VM)") {
          TextField("Host (https://...)", text: $openClawHost)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)
            .keyboardType(.URL)

          HStack {
            Text("Port")
            Spacer()
            TextField("", value: $openClawPort, formatter: NumberFormatter())
              .keyboardType(.numberPad)
              .multilineTextAlignment(.trailing)
              .frame(width: 100)
          }

          SecureField("Gateway Token", text: $openClawGatewayToken)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)

          TextField("Agent Id (default: JARVIS_Main)", text: $openClawAgentId)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)

          TextField("Profile (default)", text: $openClawProfile)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled(true)

          VStack(alignment: .leading, spacing: 6) {
            Text("OpenClaw user")
              .font(.caption)
              .foregroundColor(.secondary)
            Text(openClawUser)
              .font(.system(.caption, design: .monospaced))
              .foregroundColor(.secondary)
              .lineLimit(2)
          }

          Text(openClawConfigured ? "Configured" : "Not configured")
            .foregroundColor(openClawConfigured ? .green : .secondary)
        }

        Section("Diagnostics") {
          Button(isTesting ? "Testing..." : "Test Connection") {
            Task { await runDiagnostics() }
          }
          .disabled(isTesting || !openClawConfigured)

          if !testOutput.isEmpty {
            Text(testOutput)
              .font(.system(.caption, design: .monospaced))
              .foregroundColor(.secondary)
              .textSelection(.enabled)
          }
        }

        Section("Notes") {
          Text("For tool calling, this app sends Gemini tool calls to your OpenClaw Gateway at /v1/chat/completions.")
          Text("Recommended: expose the gateway privately over Tailscale Serve and use HTTPS.")
        }
        .font(.footnote)
        .foregroundColor(.secondary)
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarLeading) {
          Button("Close") { dismiss() }
        }
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Save") {
            persistSecrets()
            dismiss()
          }
        }
      }
      .onAppear {
        // Load secrets from Keychain into local edit state.
        geminiApiKey = KeychainStore.get(.geminiApiKey) ?? ""
        openClawGatewayToken = KeychainStore.get(.openClawGatewayToken) ?? ""
      }
    }
  }

  private func persistSecrets() {
    KeychainStore.set(geminiApiKey, for: .geminiApiKey)
    KeychainStore.set(openClawGatewayToken, for: .openClawGatewayToken)
  }

  private func runDiagnostics() async {
    isTesting = true
    testOutput = ""
    defer { isTesting = false }

    // Ensure we persist before testing so the rest of the app sees the latest.
    persistSecrets()

    let health = await OpenClawDiagnostics.health(host: openClawHost, port: openClawPort)
    let chat = await OpenClawDiagnostics.chatPing(
      host: openClawHost,
      port: openClawPort,
      gatewayToken: openClawGatewayToken,
      agentId: openClawAgentId.trimmingCharacters(in: .whitespacesAndNewlines),
      user: openClawUser
    )

    testOutput = [
      "GET /health -> \(health.ok ? "OK" : "FAIL"): \(health.detail)",
      "POST /v1/chat/completions -> \(chat.ok ? "OK" : "FAIL"): \(chat.detail)",
    ].joined(separator: "\n")
  }
}
