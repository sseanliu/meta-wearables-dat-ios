/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// StreamSessionView.swift
//
//

import MWDATCore
import SwiftUI
import UIKit

struct StreamSessionView: View {
  let wearables: WearablesInterface
  @ObservedObject private var wearablesViewModel: WearablesViewModel
  @StateObject private var viewModel: StreamSessionViewModel
  @StateObject private var geminiVM = GeminiSessionViewModel()
  @Environment(\.scenePhase) private var scenePhase

  init(wearables: WearablesInterface, wearablesVM: WearablesViewModel) {
    self.wearables = wearables
    self.wearablesViewModel = wearablesVM
    self._viewModel = StateObject(wrappedValue: StreamSessionViewModel(wearables: wearables))
  }

  var body: some View {
    ZStack {
      if viewModel.isStreaming {
        // Full-screen video view with streaming controls
        StreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, geminiVM: geminiVM)
      } else {
        // Pre-streaming setup view with permissions and start button
        NonStreamView(viewModel: viewModel, wearablesVM: wearablesViewModel, geminiVM: geminiVM)
      }
    }
    .task {
      viewModel.geminiSessionVM = geminiVM
      geminiVM.streamingMode = viewModel.streamingMode
    }
    .onChange(of: viewModel.streamingMode) { _, newMode in
      geminiVM.streamingMode = newMode
    }
    .onChange(of: geminiVM.deactivateRequested) { _, requested in
      guard requested else { return }
      Task { @MainActor in
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession(userInitiated: true)
        }
        geminiVM.deactivateRequested = false
        closeAppAfterDeactivation()
      }
    }
    .onChange(of: scenePhase) { _, phase in
      // If the user leaves the app (or Meta AI briefly takes foreground during registration),
      // release audio/camera resources so normal glasses behavior (calls/music/Meta AI) stays snappy.
      guard phase != .active else { return }
      Task { @MainActor in
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession(userInitiated: true)
        }
        if geminiVM.isGeminiActive {
          geminiVM.stopSession()
        }
      }
    }
    .onReceive(NotificationCenter.default.publisher(for: .jarvisStopRequested)) { _ in
      Task { @MainActor in
        if viewModel.streamingStatus != .stopped {
          await viewModel.stopSession(userInitiated: true)
        }
        geminiVM.stopSession()
        closeAppAfterDeactivation()
      }
    }
    .alert("Error", isPresented: $viewModel.showError) {
      Button("OK") {
        viewModel.dismissError()
      }
    } message: {
      Text(viewModel.errorMessage)
    }
  }

  private func closeAppAfterDeactivation() {
    // iOS doesn't provide a public "quit app" API. For this dev-signed, on-device build,
    // we suspend (home screen) and then terminate so Siri can relaunch cleanly.
    //
    // Important: if we delay too long after suspending, iOS may suspend the process
    // before our `exit(0)` runs, leaving the app "minimized but still running".
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
      UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
      exit(0)
    }
  }
}
