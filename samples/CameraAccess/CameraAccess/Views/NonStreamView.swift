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

struct NonStreamView: View {
  @ObservedObject var viewModel: StreamSessionViewModel
  @ObservedObject var wearablesVM: WearablesViewModel
  @ObservedObject var geminiVM: GeminiSessionViewModel
  @State private var sheetHeight: CGFloat = 300
  @State private var showSettings: Bool = false
  @State private var isStartingAI: Bool = false

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

        VStack(spacing: 12) {
          Image(.cameraAccessIcon)
            .resizable()
            .renderingMode(.template)
            .foregroundColor(.white)
            .aspectRatio(contentMode: .fit)
            .frame(width: 120)

          Text("Stream Your Glasses Camera")
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(.white)

          Text("Tap the Start streaming button to stream video from your glasses or use the camera button to take a photo from your glasses.")
            .font(.system(size: 15))
            .multilineTextAlignment(.center)
            .foregroundColor(.white)
        }
        .padding(.horizontal, 12)

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

        CustomButton(
          title: isStartingAI ? "Starting..." : "Start AI on iPhone",
          style: .secondary,
          isDisabled: isStartingAI
        ) {
          Task { await startAIOnIPhone() }
        }

        CustomButton(
          title: isStartingAI ? "Starting..." : "Start AI with Glasses",
          style: .primary,
          isDisabled: isStartingAI || !viewModel.hasActiveDevice
        ) {
          Task { await startAIWithGlasses() }
        }
      }
      .padding(.all, 24)
    }
    .onAppear {
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

  private func startAIWithGlasses() async {
    guard !isStartingAI else { return }
    isStartingAI = true
    defer { isStartingAI = false }

    await viewModel.handleStartStreaming()
    geminiVM.streamingMode = .glasses
    await geminiVM.startSession()
  }

  private func maybeAutoStart() {
    let forceAutoStart = UserDefaults.standard.bool(forKey: AppSettings.Keys.forceAutoStartOnce)
    // Only auto-start when explicitly requested (Siri / Shortcuts "Start Jarvis").
    // We do NOT auto-start just because glasses connect or become active.
    guard forceAutoStart else { return }
    guard !isStartingAI else { return }
    guard wearablesVM.registrationState == .registered else { return }
    guard viewModel.hasActiveDevice else { return }

    // One-shot override.
    UserDefaults.standard.set(false, forKey: AppSettings.Keys.forceAutoStartOnce)
    Task { await startAIWithGlasses() }
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
