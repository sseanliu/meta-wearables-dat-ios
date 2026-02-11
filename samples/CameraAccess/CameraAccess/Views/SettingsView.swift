/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// SettingsView.swift
//
// Settings screen with disconnect option and configure secrets form.
// Secrets are stored on device and can be edited without recompiling.
//

import MWDATCore
import SwiftUI

struct SettingsView: View {
  @ObservedObject var wearablesVM: WearablesViewModel
  @Environment(\.dismiss) var dismiss
  @State private var showSecrets = false

  var body: some View {
    NavigationStack {
      List {
        // Disconnect section
        Section {
          Button("Disconnect", role: .destructive) {
            wearablesVM.disconnectGlasses()
            dismiss()
          }
          .disabled(wearablesVM.registrationState != .registered)
        } header: {
          Text("Connection")
        } footer: {
          Text("Disconnect your glasses from this app.")
        }

        // Secrets section
        Section {
          Button {
            showSecrets = true
          } label: {
            Label("Configure Secrets", systemImage: "key.fill")
          }
        } header: {
          Text("API Keys & Tokens")
        } footer: {
          Text("Gemini API key, OpenClaw host, and tokens. Protected by PIN.")
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Done") {
            dismiss()
          }
        }
      }
      .sheet(isPresented: $showSecrets) {
        SecretsView()
      }
    }
  }
}
