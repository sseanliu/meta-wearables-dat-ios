/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamView.swift
//
// Main UI for video streaming from Meta wearable devices using the DAT SDK.
// This view demonstrates the complete streaming API: video streaming with real-time display, photo capture,
// and error handling. Extended with Gemini Live AI assistant integration.
//

import MWDATCore
import SwiftUI

struct StreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @State private var showSettings: Bool = false
  @State private var voiceNameWhenOpeningSettings: String = ""
  @AppStorage(AppSettings.Keys.showVideoPreviewOnPhone) private var showVideoPreviewOnPhone: Bool = AppSettings.Defaults.showVideoPreviewOnPhone

  var body: some View {
    ZStack {
      // Black background for letterboxing/pillarboxing
      Color.black
        .edgesIgnoringSafeArea(.all)

      // Video backdrop
      if showVideoPreviewOnPhone {
        if let videoFrame = viewModel.currentVideoFrame, viewModel.hasReceivedFirstFrame {
          GeometryReader { geometry in
            Image(uiImage: videoFrame)
              .resizable()
              .aspectRatio(contentMode: .fill)
              .frame(width: geometry.size.width, height: geometry.size.height)
              .clipped()
          }
          .edgesIgnoringSafeArea(.all)
        } else {
          ProgressView()
            .scaleEffect(1.5)
            .foregroundColor(.white)
        }
      }

      // Gemini status overlay (top) + speaking indicator
      if geminiVM.isGeminiActive {
        VStack {
          GeminiStatusBar(geminiVM: geminiVM)
          Spacer()

          VStack(spacing: 8) {
            if !geminiVM.userTranscript.isEmpty || !geminiVM.aiTranscript.isEmpty {
              TranscriptView(
                userText: geminiVM.userTranscript,
                aiText: geminiVM.aiTranscript
              )
            }

            ToolCallStatusView(status: geminiVM.toolCallStatus)

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
          .padding(.bottom, 80)
        }
        .padding(.all, 24)
      }

      // Bottom controls layer
      VStack {
        Spacer()
        ControlsView(viewModel: viewModel, geminiVM: geminiVM)
      }
      .padding(.all, 24)

      // Top-right menu
      VStack {
        HStack {
          Spacer()
          Menu {
            Button("Settings") {
              // Used to detect changes and refresh Gemini with new runtime settings.
              voiceNameWhenOpeningSettings = GeminiConfig.voiceName
              showSettings = true
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
      }
      .padding(.all, 24)
    }
    // Show captured photos from DAT SDK in a preview sheet
    .sheet(isPresented: $viewModel.showPhotoPreview) {
      if let photo = viewModel.capturedPhoto {
        PhotoPreviewView(
          photo: photo,
          onDismiss: {
            viewModel.dismissPhotoPreview()
          }
        )
      }
    }
    // Gemini error alert
    .alert("AI Assistant", isPresented: Binding(
      get: { geminiVM.errorMessage != nil },
      set: { if !$0 { geminiVM.errorMessage = nil } }
    )) {
      Button("OK") { geminiVM.errorMessage = nil }
    } message: {
      Text(geminiVM.errorMessage ?? "")
    }
    .sheet(isPresented: $showSettings, onDismiss: {
      // Gemini applies voice selection only during the initial setup message,
      // so we restart the session when voice changes.
      let oldVoice = voiceNameWhenOpeningSettings.trimmingCharacters(in: .whitespacesAndNewlines)
      let newVoice = GeminiConfig.voiceName.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !oldVoice.isEmpty, oldVoice != newVoice else { return }
      guard geminiVM.isGeminiActive else { return }

      Task { @MainActor in
        geminiVM.stopSession()
        await geminiVM.startSession()
      }
    }) {
      SettingsView()
    }
  }
}

// Extracted controls for clarity
struct ControlsView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel

  var body: some View {
    // Controls row
    HStack(spacing: 8) {
      CustomButton(
        title: "Video off",
        style: .secondary,
        isDisabled: false
      ) {
        Task {
          await viewModel.stopSession(userInitiated: true)
        }
      }

      // Photo button (glasses mode only — DAT SDK capture)
      if viewModel.streamingMode == .glasses {
        CircleButton(icon: "camera.fill", text: nil) {
          viewModel.capturePhoto()
        }
      }

      // Gemini AI button
      CircleButton(
        icon: geminiVM.isGeminiActive ? "waveform.circle.fill" : "waveform.circle",
        text: "AI"
      ) {
        Task {
          if geminiVM.isGeminiActive {
            geminiVM.stopSession()
          } else {
            await geminiVM.startSession()
          }
        }
      }
    }
  }
}
