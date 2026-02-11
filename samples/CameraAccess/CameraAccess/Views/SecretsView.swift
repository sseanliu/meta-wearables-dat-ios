/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// SecretsView.swift
//
// Password-protected view for configuring API keys and tokens.
// Unlock via PIN or Face ID (when enabled).
//

import SwiftUI

struct SecretsView: View {
  @ObservedObject var authManager = AuthManager.shared
  @ObservedObject private var secretsManager = SecretsManager.shared
  @Environment(\.dismiss) var dismiss
  @State private var showSaveConfirmation = false
  @State private var showChangePIN = false

  var body: some View {
    Group {
      if !authManager.hasPIN {
        PINSetupView()
      } else if !authManager.isUnlocked {
        PINUnlockView()
      } else {
        secretsContent
      }
    }
    .onDisappear {
      authManager.lock()
    }
  }

  private var secretsContent: some View {
    NavigationStack {
      List {
        // Security section
        Section {
          if authManager.isFaceIDAvailable {
            Toggle("Use Face ID", isOn: $authManager.useFaceID)
          }
          Button("Change PIN") {
            showChangePIN = true
          }
        } header: {
          Text("Security")
        } footer: {
          if authManager.isFaceIDAvailable {
            Text("When enabled, you can unlock secrets with Face ID instead of entering your PIN.")
          }
        }
        .sheet(isPresented: $showChangePIN) {
          ChangePINView()
        }

        // Configure secrets section
        Section {
          LabeledContent("Gemini API Key") {
            TextField("API key", text: $secretsManager.geminiAPIKey)
              .textContentType(.password)
              .autocapitalization(.none)
              .autocorrectionDisabled()
          }

          LabeledContent("OpenClaw Host") {
            TextField("Host URL", text: $secretsManager.openClawHost)
              .textContentType(.URL)
              .autocapitalization(.none)
              .autocorrectionDisabled()
              .keyboardType(.URL)
          }

          LabeledContent("OpenClaw Port") {
            TextField("Port", value: $secretsManager.openClawPort, format: IntegerFormatStyle().grouping(.never))
              .keyboardType(.numberPad)
          }

          LabeledContent("OpenClaw Hook Token") {
            TextField("Hook token", text: $secretsManager.openClawHookToken)
              .textContentType(.password)
              .autocapitalization(.none)
              .autocorrectionDisabled()
          }

          LabeledContent("OpenClaw Gateway Token") {
            TextField("Gateway token", text: $secretsManager.openClawGatewayToken)
              .textContentType(.password)
              .autocapitalization(.none)
              .autocorrectionDisabled()
          }

          Button("Reset to defaults") {
            secretsManager.resetToDefaults()
            showSaveConfirmation = true
          }
          .foregroundColor(.orange)
        } header: {
          Text("Configure Secrets")
        } footer: {
          Text("Gemini API key from aistudio.google.com/apikey. OpenClaw values from your Mac gateway. Stored on device.")
        }

        // Save button
        Section {
          Button("Save") {
            secretsManager.save()
            showSaveConfirmation = true
          }
          .frame(maxWidth: .infinity)
          .fontWeight(.semibold)
        }
      }
      .navigationTitle("Secrets")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
      .alert("Saved", isPresented: $showSaveConfirmation) {
        Button("OK") { }
      } message: {
        Text("Your settings have been saved.")
      }
    }
  }
}

// MARK: - PIN Setup (first-time)

private struct PINSetupView: View {
  @ObservedObject var authManager = AuthManager.shared
  @State private var pin = ""
  @State private var confirmPin = ""
  @State private var step: Step = .create
  @State private var errorMessage: String?
  @FocusState private var focusedField: Field?

  private enum Step {
    case create
    case confirm
  }

  private enum Field {
    case pin
    case confirm
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Image(systemName: "lock.shield")
          .font(.system(size: 48))
          .foregroundStyle(.secondary)

        Text(step == .create ? "Create PIN" : "Confirm PIN")
          .font(.title2)
          .fontWeight(.semibold)

        Text("Enter a 4–6 digit PIN to protect your secrets.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)

        if let message = errorMessage {
          Text(message)
            .font(.caption)
            .foregroundColor(.red)
        }

        SecureField(step == .create ? "PIN" : "Confirm PIN", text: step == .create ? $pin : $confirmPin)
          .textContentType(.oneTimeCode)
          .keyboardType(.numberPad)
          .focused($focusedField, equals: step == .create ? .pin : .confirm)
          .padding()
          .background(Color(.systemGray6))
          .cornerRadius(10)
          .padding(.horizontal, 32)

        if step == .create {
          Button("Continue") {
            guard pin.count >= 4, pin.count <= 6 else {
              errorMessage = "PIN must be 4–6 digits"
              return
            }
            errorMessage = nil
            step = .confirm
            focusedField = .confirm
          }
          .buttonStyle(.borderedProminent)
          .disabled(pin.count < 4 || pin.count > 6)
        } else {
          Button("Set PIN") {
            guard pin == confirmPin else {
              errorMessage = "PINs do not match"
              return
            }
            if authManager.setPIN(pin) {
              authManager.isUnlocked = true
            } else {
              errorMessage = "Could not save PIN"
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(pin != confirmPin || confirmPin.isEmpty)
        }
      }
      .navigationTitle("Secrets")
      .navigationBarTitleDisplayMode(.inline)
    }
  }
}

// MARK: - PIN Unlock

private struct PINUnlockView: View {
  @ObservedObject var authManager = AuthManager.shared
  @State private var pin = ""
  @State private var errorMessage: String?
  @FocusState private var isPinFocused: Bool

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Image(systemName: "lock.fill")
          .font(.system(size: 48))
          .foregroundStyle(.secondary)

        Text("Enter PIN")
          .font(.title2)
          .fontWeight(.semibold)

        Text("Enter your PIN to unlock secrets.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .padding(.horizontal)

        if let message = errorMessage {
          Text(message)
            .font(.caption)
            .foregroundColor(.red)
        }

        SecureField("PIN", text: $pin)
          .textContentType(.oneTimeCode)
          .keyboardType(.numberPad)
          .focused($isPinFocused)
          .padding()
          .background(Color(.systemGray6))
          .cornerRadius(10)
          .padding(.horizontal, 32)

        if authManager.useFaceID && authManager.isFaceIDAvailable {
          Button {
            Task {
              let success = await authManager.authenticateWithFaceID(reason: "Unlock secrets")
              if !success {
                errorMessage = "Face ID failed"
              }
            }
          } label: {
            Label("Face ID", systemImage: "faceid")
              .frame(maxWidth: .infinity)
          }
          .buttonStyle(.borderedProminent)
          .padding(.horizontal, 32)
        }

        Button("Unlock") {
          if authManager.unlock(withPIN: pin) {
            errorMessage = nil
          } else {
            errorMessage = "Incorrect PIN"
          }
        }
        .buttonStyle(.borderedProminent)
        .disabled(pin.count < 4)
        .padding(.horizontal, 32)
      }
      .navigationTitle("Secrets")
      .navigationBarTitleDisplayMode(.inline)
      .onChange(of: pin) { _, newValue in
        if newValue.count >= 4, authManager.verifyPIN(newValue) {
          authManager.unlock(withPIN: newValue)
        }
      }
    }
  }
}

// MARK: - Change PIN

private struct ChangePINView: View {
  @ObservedObject var authManager = AuthManager.shared
  @Environment(\.dismiss) var dismiss
  @State private var currentPin = ""
  @State private var newPin = ""
  @State private var confirmPin = ""
  @State private var step: Step = .current
  @State private var errorMessage: String?

  private enum Step {
    case current
    case new
    case confirm
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 24) {
        Text(stepTitle)
          .font(.title2)
          .fontWeight(.semibold)

        if step == .current {
          SecureField("Current PIN", text: $currentPin)
            .textContentType(.oneTimeCode)
            .keyboardType(.numberPad)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 32)
        } else if step == .new {
          SecureField("New PIN", text: $newPin)
            .textContentType(.oneTimeCode)
            .keyboardType(.numberPad)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 32)
        } else {
          SecureField("Confirm new PIN", text: $confirmPin)
            .textContentType(.oneTimeCode)
            .keyboardType(.numberPad)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(10)
            .padding(.horizontal, 32)
        }

        if let message = errorMessage {
          Text(message)
            .font(.caption)
            .foregroundColor(.red)
        }

        if step == .current {
          Button("Continue") {
            guard authManager.verifyPIN(currentPin) else {
              errorMessage = "Incorrect PIN"
              return
            }
            errorMessage = nil
            step = .new
          }
          .buttonStyle(.borderedProminent)
          .disabled(currentPin.count < 4)
        } else if step == .new {
          Button("Continue") {
            guard newPin.count >= 4, newPin.count <= 6 else {
              errorMessage = "PIN must be 4–6 digits"
              return
            }
            errorMessage = nil
            step = .confirm
          }
          .buttonStyle(.borderedProminent)
          .disabled(newPin.count < 4 || newPin.count > 6)
        } else {
          Button("Update PIN") {
            guard newPin == confirmPin else {
              errorMessage = "PINs do not match"
              return
            }
            if authManager.setPIN(newPin) {
              dismiss()
            } else {
              errorMessage = "Could not save PIN"
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(newPin != confirmPin || confirmPin.isEmpty)
        }
      }
      .navigationTitle("Change PIN")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            dismiss()
          }
        }
      }
    }
  }

  private var stepTitle: String {
    switch step {
    case .current: "Enter current PIN"
    case .new: "Enter new PIN"
    case .confirm: "Confirm new PIN"
    }
  }
}

#Preview {
  SecretsView()
}
