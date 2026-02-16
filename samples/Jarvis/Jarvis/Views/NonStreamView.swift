/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// NonStreamView.swift
//
// Default screen to show getting started tips after app connection
// Initiates streaming
//

import MWDATCore
import SwiftUI
import UIKit

struct NonStreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @Environment(\.scenePhase) private var scenePhase
  @State private var sheetHeight: CGFloat = 300
  @State private var showSettings: Bool = false
  @State private var isStartingAI: Bool = false
  @State private var requestedAutoRegistration: Bool = false

  var body: some View {
    ZStack {
      Color.black.edgesIgnoringSafeArea(.all)

      VStack {
        HStack {
          Spacer()
          Menu {
            Button("Settings") {
              showSettings = true
            }
            if wearablesVM.registrationState != .registered {
              Button("Connect glasses") {
                wearablesVM.connectGlasses()
              }
              .disabled(wearablesVM.registrationState == .registering)
            }
            Button("Disconnect", role: .destructive) {
              wearablesVM.disconnectGlasses()
            }
            .disabled(wearablesVM.registrationState != .registered)
          } label: {
            Image(systemName: "gearshape")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .foregroundColor(.white)
              .frame(width: 24, height: 24)
          }
        }

        Spacer()

        if geminiVM.isGeminiActive {
          VStack(spacing: 12) {
            GeminiStatusBar(geminiVM: geminiVM)

            if !geminiVM.userTranscript.isEmpty || !geminiVM.aiTranscript.isEmpty {
              TranscriptView(userText: geminiVM.userTranscript, aiText: geminiVM.aiTranscript)
            }

            ToolCallStatusView(status: geminiVM.toolCallStatus)

            Text("Video: Off")
              .font(.system(size: 14, weight: .medium))
              .foregroundColor(.white.opacity(0.85))
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(Color.black.opacity(0.45))
              .cornerRadius(16)

            if geminiVM.isModelSpeaking {
              HStack(spacing: 8) {
                Image(systemName: "speaker.wave.2.fill")
                  .foregroundColor(.white)
                  .font(.system(size: 14))
                SpeakingIndicator()
              }
              .padding(.horizontal, 16)
              .padding(.vertical, 8)
              .background(Color.black.opacity(0.5))
              .cornerRadius(20)
            }
          }
          .padding(.horizontal, 12)
        } else {
          VStack(spacing: 12) {
            Image(.cameraAccessIcon)
              .resizable()
              .renderingMode(.template)
              .foregroundColor(.white)
              .aspectRatio(contentMode: .fit)
              .frame(width: 120)

            Text("Jarvis (Glasses + iPhone)")
              .font(.system(size: 20, weight: .semibold))
              .foregroundColor(.white)

            Text("Starts in audio-only mode. Say “Jarvis video on” to enable the glasses camera when you want it.")
              .font(.system(size: 15))
              .multilineTextAlignment(.center)
              .foregroundColor(.white)
          }
          .padding(.horizontal, 12)
        }

        Spacer()

        if !viewModel.hasActiveDevice {
          HStack(spacing: 8) {
            Image(systemName: "hourglass")
              .resizable()
              .aspectRatio(contentMode: .fit)
              .foregroundColor(.white.opacity(0.7))
              .frame(width: 16, height: 16)

            Text("Waiting for an active device")
              .font(.system(size: 14))
              .foregroundColor(.white.opacity(0.7))
          }
          .padding(.bottom, 12)
        }

        if geminiVM.isGeminiActive {
          CustomButton(
            title: isStartingAI ? "Starting..." : "Enable Video",
            style: .primary,
            isDisabled: isStartingAI || !viewModel.hasActiveDevice
          ) {
            Task { await enableVideo() }
          }

          CustomButton(
            title: "Stop AI",
            style: .destructive,
            isDisabled: isStartingAI
          ) {
            geminiVM.stopSession()
          }
        } else {
          CustomButton(
            title: isStartingAI ? "Starting..." : "Start AI on iPhone",
            style: .secondary,
            isDisabled: isStartingAI
          ) {
            Task { await startAIOnIPhone() }
          }

          CustomButton(
            title: isStartingAI ? "Starting..." : "Start AI with Glasses (Audio)",
            style: .primary,
            isDisabled: isStartingAI || !viewModel.hasActiveDevice
          ) {
            Task { await startAIWithGlassesAudioOnly() }
          }
        }
      }
      .padding(.all, 24)
    }
    .onAppear {
      maybeAutoStart()
    }
    .onChange(of: scenePhase) { _, _ in
      // Siri launch can briefly transition through inactive; retry when active.
      maybeAutoStart()
    }
    .onChange(of: viewModel.hasActiveDevice) { _, _ in
      maybeAutoStart()
    }
    .onChange(of: wearablesVM.registrationState) { _, _ in
      maybeAutoStart()
    }
    .sheet(isPresented: $showSettings) {
      SettingsView()
    }
    .sheet(isPresented: $wearablesVM.showGettingStartedSheet) {
      if #available(iOS 16.0, *) {
        GettingStartedSheetView(height: $sheetHeight)
          .presentationDetents([.height(sheetHeight)])
          .presentationDragIndicator(.visible)
      } else {
        GettingStartedSheetView(height: $sheetHeight)
      }
    }
  }

  private func startAIOnIPhone() async {
    guard !isStartingAI else { return }
    isStartingAI = true
    defer { isStartingAI = false }

    await viewModel.handleStartIPhone()
    geminiVM.streamingMode = .iPhone
    await geminiVM.startSession()
  }

  private func startAIWithGlassesAudioOnly() async {
    guard !isStartingAI else { return }
    isStartingAI = true
    defer { isStartingAI = false }

    viewModel.allowAutoStart = false
    viewModel.streamingMode = .glasses
    geminiVM.streamingMode = .glasses
    await geminiVM.startSession()
  }

  private func enableVideo() async {
    guard viewModel.streamingStatus == .stopped else { return }
    await viewModel.handleStartStreaming()
  }

  private func maybeAutoStart() {
    let forceAutoStart = UserDefaults.standard.bool(forKey: AppSettings.Keys.forceAutoStartOnce)
    let autoStartOnOpen = (UserDefaults.standard.object(forKey: AppSettings.Keys.autoStartOnAppOpen) as? Bool)
      ?? AppSettings.Defaults.autoStartOnAppOpen

    // Always allow explicit Siri one-shot start. Optionally auto-start whenever the app opens.
    let shouldAutoStart = forceAutoStart || autoStartOnOpen
    // Only auto-start when explicitly requested (Siri / Shortcuts "Start Jarvis").
    // We do NOT auto-start just because glasses connect or become active.
    guard shouldAutoStart else { return }
    guard !isStartingAI else { return }
    guard viewModel.allowAutoStart else { return }

    // Only start while we're in the foreground. If the Meta AI app is opened during
    // registration, our app goes inactive/background briefly.
    guard UIApplication.shared.applicationState == .active else { return }

    // If glasses aren't registered yet, kick off registration and wait for the
    // registration + active device signals to arrive (we'll retry via onChange handlers).
    if wearablesVM.registrationState != .registered {
      if !requestedAutoRegistration {
        requestedAutoRegistration = true
        wearablesVM.connectGlasses()
      }
      return
    }

    // Registered but device not active yet: wait.
    guard viewModel.hasActiveDevice else { return }

    // One-shot override.
    if forceAutoStart {
      UserDefaults.standard.set(false, forKey: AppSettings.Keys.forceAutoStartOnce)
    }
    Task { await startAIWithGlassesAudioOnly() }
  }
}

struct GettingStartedSheetView: View {
  @Environment(\.dismiss) var dismiss
  @Binding var height: CGFloat

  var body: some View {
    VStack(spacing: 24) {
      Text("Getting started")
        .font(.system(size: 18, weight: .semibold))
        .foregroundColor(.primary)

      VStack(spacing: 12) {
        TipItemView(
          resource: .videoIcon,
          text: "First, Jarvis needs permission to use your glasses camera."
        )
        TipItemView(
          resource: .tapIcon,
          text: "Capture photos by tapping the camera button."
        )
        TipItemView(
          resource: .smartGlassesIcon,
          text: "The capture LED lets others know when you're capturing content or going live."
        )
      }
      .padding(.bottom, 16)

      CustomButton(
        title: "Continue",
        style: .primary,
        isDisabled: false
      ) {
        dismiss()
      }
    }
    .padding(.all, 24)
    .background(
      GeometryReader { geo -> Color in
        DispatchQueue.main.async {
          height = geo.size.height
        }
        return Color.clear
      }
    )
  }
}

struct TipItemView: View {
  let resource: ImageResource
  let text: String

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Image(resource)
        .resizable()
        .renderingMode(.template)
        .foregroundColor(.primary)
        .aspectRatio(contentMode: .fit)
        .frame(width: 24)
        .padding(.leading, 4)
        .padding(.top, 4)

      Text(text)
        .font(.system(size: 15))
        .foregroundColor(.primary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}
