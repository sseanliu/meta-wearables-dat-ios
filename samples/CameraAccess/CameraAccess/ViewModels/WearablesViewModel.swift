/*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 * All rights reserved.
 *
 * This source code is licensed under the license found in the
 * LICENSE file in the root directory of this source tree.
 */

//
// WearablesViewModel.swift
//
// Primary view model for the CameraAccess app that manages DAT SDK integration.
// Demonstrates how to listen to device availability changes using the DAT SDK's
// device stream functionality and handle permission requests.
//

import MWDATCore
import SwiftUI

#if DEBUG
import MWDATMockDevice
#endif

@MainActor
class WearablesViewModel: ObservableObject {
  @Published var devices: [DeviceIdentifier]
  @Published var hasMockDevice: Bool
  @Published var registrationState: RegistrationState
  // Allow iPhone camera mode even if glasses are not registered yet.
  @Published var allowIPhoneMode: Bool
  @Published var showGettingStartedSheet: Bool = false
  @Published var showError: Bool = false
  @Published var errorMessage: String = ""

  private var registrationTask: Task<Void, Never>?
  private var deviceStreamTask: Task<Void, Never>?
  private var setupDeviceStreamTask: Task<Void, Never>?
  private let wearables: WearablesInterface
  private var compatibilityListenerTokens: [DeviceIdentifier: AnyListenerToken] = [:]

  init(wearables: WearablesInterface) {
    self.wearables = wearables
    self.devices = wearables.devices
    self.hasMockDevice = false
    self.registrationState = wearables.registrationState
    self.allowIPhoneMode = false

    // Set up device stream immediately to handle MockDevice events
    setupDeviceStreamTask = Task {
      await setupDeviceStream()
    }

    registrationTask = Task {
      for await registrationState in wearables.registrationStateStream() {
        let previousState = self.registrationState
        self.registrationState = registrationState
        if self.showGettingStartedSheet == false && registrationState == .registered && previousState == .registering {
          self.showGettingStartedSheet = true
        }
      }
    }
  }

  deinit {
    registrationTask?.cancel()
    deviceStreamTask?.cancel()
    setupDeviceStreamTask?.cancel()
  }

  private func setupDeviceStream() async {
    if let task = deviceStreamTask, !task.isCancelled {
      task.cancel()
    }

    deviceStreamTask = Task {
      for await devices in wearables.devicesStream() {
        self.devices = devices
        #if DEBUG
        self.hasMockDevice = !MockDeviceKit.shared.pairedDevices.isEmpty
        #endif
        // Monitor compatibility for each device
        monitorDeviceCompatibility(devices: devices)
      }
    }
  }

  private func monitorDeviceCompatibility(devices: [DeviceIdentifier]) {
    // Remove listeners for devices that are no longer present
    let deviceSet = Set(devices)
    compatibilityListenerTokens = compatibilityListenerTokens.filter { deviceSet.contains($0.key) }

    // Add listeners for new devices
    for deviceId in devices {
      guard compatibilityListenerTokens[deviceId] == nil else { continue }
      guard let device = wearables.deviceForIdentifier(deviceId) else { continue }

      // Capture device name before the closure to avoid Sendable issues
      let deviceName = device.nameOrId()
      let token = device.addCompatibilityListener { [weak self] compatibility in
        guard let self else { return }
        if compatibility == .deviceUpdateRequired {
          Task { @MainActor in
            self.showError("Device '\(deviceName)' requires an update to work with this app")
          }
        }
      }
      compatibilityListenerTokens[deviceId] = token
    }
  }

  func connectGlasses() {
    guard registrationState != .registering else { return }
    Task { @MainActor in
      do {
        try await wearables.startRegistration()
      } catch let error as RegistrationError {
        showError(messageForRegistrationError(error))
      } catch {
        showError(error.localizedDescription)
      }
    }
  }

  func disconnectGlasses() {
    Task { @MainActor in
      do {
        try await wearables.startUnregistration()
      } catch let error as UnregistrationError {
        showError(error.description)
      } catch {
        showError(error.localizedDescription)
      }
    }
  }

  private func messageForRegistrationError(_ error: RegistrationError) -> String {
    // The DAT SDK often surfaces configuration/entitlement issues as "Internal error".
    // Make the common fixes obvious so the user can self-serve without needing logs.
    switch error {
    case .configurationInvalid:
      return [
        "Meta glasses registration failed (configuration invalid).",
        "",
        "Most common fixes:",
        "1) In the Meta AI app, enable Developer Mode for your glasses.",
        "2) Ensure the Meta AI app is installed and you're signed in.",
        "3) Ensure iPhone has network access (Wi-Fi/cellular).",
        "",
        "If you are NOT using Developer Mode, this app must be registered in the Wearables Developer Center and you must set META_APP_ID + CLIENT_TOKEN in Xcode build settings.",
        "",
        "Raw: \(error.description)",
      ].joined(separator: "\n")
    case .metaAINotInstalled:
      return "Meta AI app not installed. Install it from the App Store, pair your glasses there, then try again.\n\nRaw: \(error.description)"
    case .networkUnavailable:
      return "Network unavailable. Connect your iPhone to Wi-Fi/cellular and try again.\n\nRaw: \(error.description)"
    case .alreadyRegistered:
      return "Glasses are already connected. If streaming doesn't work, try Disconnect then Connect again.\n\nRaw: \(error.description)"
    case .unknown:
      return [
        "Meta glasses registration failed (unknown).",
        "",
        "Try:",
        "1) Enable Developer Mode in Meta AI app.",
        "2) Close and reopen both apps.",
        "3) Disconnect then Connect again.",
        "",
        "Raw: \(error.description)",
      ].joined(separator: "\n")
    @unknown default:
      return "Meta glasses registration failed: \(error.description)"
    }
  }

  func showError(_ error: String) {
    errorMessage = error
    showError = true
  }

  func dismissError() {
    showError = false
  }
}
