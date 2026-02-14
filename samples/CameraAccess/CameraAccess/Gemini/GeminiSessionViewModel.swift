import AVFoundation
import Foundation
import SwiftUI

@MainActor
class GeminiSessionViewModel: ObservableObject {
  @Published var isGeminiActive: Bool = false
  @Published var connectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false
  @Published var errorMessage: String?
  @Published var userTranscript: String = ""
  @Published var aiTranscript: String = ""
  @Published var toolCallStatus: ToolCallStatus = .idle
  @Published var audioRouteLabel: String = ""
  @Published var deactivateRequested: Bool = false
  private let geminiService = GeminiLiveService()
  private let openClawBridge = OpenClawBridge()
  private var toolCallRouter: ToolCallRouter?
  private let audioManager = AudioManager()
  private var lastVideoFrameTime: Date = .distantPast
  private var stateObservation: Task<Void, Never>?
  private var audioInterruptionObserver: NSObjectProtocol?
  private var audioRouteObserver: NSObjectProtocol?

  var streamingMode: StreamingMode = .glasses

  func startSession() async {
    guard !isGeminiActive else { return }

    guard GeminiConfig.isConfigured else {
      errorMessage = "Gemini API key not configured. Open Settings (gear icon) and paste your Gemini API key from https://aistudio.google.com/apikey"
      return
    }

    isGeminiActive = true
    deactivateRequested = false

    // Wire audio callbacks
    audioManager.onAudioCaptured = { [weak self] data in
      guard let self else { return }
      Task { @MainActor in
        // Mute mic while the model speaks to prevent echo/feedback.
        // iPhone mode: loudspeaker + co-located mic overwhelms iOS echo cancellation.
        // Glasses mode: only gate when we route output to the same headset as the mic.
        let shouldGateEcho = (self.streamingMode == .iPhone)
          || (self.streamingMode == .glasses && GeminiConfig.preferBluetoothAudioOutput)
        if shouldGateEcho && self.geminiService.isModelSpeaking { return }
        self.geminiService.sendAudio(data: data)
      }
    }

    geminiService.onAudioReceived = { [weak self] data in
      self?.audioManager.playAudio(data: data)
    }

    geminiService.onInterrupted = { [weak self] in
      self?.audioManager.stopPlayback()
    }

    geminiService.onTurnComplete = { [weak self] in
      guard let self else { return }
      Task { @MainActor in
        // Clear user transcript when AI finishes responding
        self.userTranscript = ""
      }
    }

    geminiService.onInputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        self.userTranscript += text
        self.aiTranscript = ""
        self.maybeHandleLocalVoiceCommands(transcript: self.userTranscript)
      }
    }

    geminiService.onOutputTranscription = { [weak self] text in
      guard let self else { return }
      Task { @MainActor in
        self.aiTranscript += text
      }
    }

    // Handle unexpected disconnection
    geminiService.onDisconnected = { [weak self] reason in
      guard let self else { return }
      Task { @MainActor in
        guard self.isGeminiActive else { return }
        self.stopSession()
        self.errorMessage = "Connection lost: \(reason ?? "Unknown error")"
      }
    }

    // New OpenClaw session per Gemini session (fresh context, no stale memory)
    openClawBridge.resetSession()

    // Wire tool call handling
    toolCallRouter = ToolCallRouter(
      bridge: openClawBridge,
      onToolFinished: { [weak self] _ in
        self?.audioManager.playChime()
      }
    )

    geminiService.onToolCall = { [weak self] toolCall in
      guard let self else { return }
      Task { @MainActor in
        for call in toolCall.functionCalls {
          self.toolCallRouter?.handleToolCall(call) { [weak self] response in
            self?.geminiService.sendToolResponse(response)
          }
        }
      }
    }

    geminiService.onToolCallCancellation = { [weak self] cancellation in
      guard let self else { return }
      Task { @MainActor in
        self.toolCallRouter?.cancelToolCalls(ids: cancellation.ids)
      }
    }

    // Observe service state
    stateObservation = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
        guard !Task.isCancelled else { break }
        self.connectionState = self.geminiService.connectionState
        self.isModelSpeaking = self.geminiService.isModelSpeaking
        self.toolCallStatus = self.openClawBridge.lastToolCallStatus
      }
    }

    // Setup audio
    do {
      let preferBluetooth = (streamingMode == .glasses) ? GeminiConfig.preferBluetoothAudioOutput : false
      try audioManager.setupAudioSession(useIPhoneMode: streamingMode == .iPhone, preferBluetoothOutput: preferBluetooth)
      registerAudioObservers()
      updateAudioRouteLabel()
    } catch {
      errorMessage = "Audio setup failed: \(error.localizedDescription)"
      isGeminiActive = false
      return
    }

    // Connect to Gemini and wait for setupComplete
    let setupOk = await geminiService.connect()

    if !setupOk {
      let msg: String
      if case .error(let err) = geminiService.connectionState {
        msg = err
      } else {
        msg = "Failed to connect to Gemini"
      }
      errorMessage = msg
      geminiService.disconnect()
      unregisterAudioObservers()
      audioManager.deactivateAudioSession()
      stateObservation?.cancel()
      stateObservation = nil
      isGeminiActive = false
      connectionState = .disconnected
      return
    }

    // Start mic capture
    do {
      try audioManager.startCapture()
    } catch {
      errorMessage = "Mic capture failed: \(error.localizedDescription)"
      geminiService.disconnect()
      unregisterAudioObservers()
      audioManager.deactivateAudioSession()
      stateObservation?.cancel()
      stateObservation = nil
      isGeminiActive = false
      connectionState = .disconnected
      return
    }
  }

  func stopSession() {
    toolCallRouter?.cancelAll()
    toolCallRouter = nil
    audioManager.stopCapture()
    geminiService.disconnect()
    stateObservation?.cancel()
    stateObservation = nil
    unregisterAudioObservers()
    isGeminiActive = false
    connectionState = .disconnected
    isModelSpeaking = false
    userTranscript = ""
    aiTranscript = ""
    toolCallStatus = .idle
    audioRouteLabel = ""
    deactivateRequested = false
  }

  func sendVideoFrameIfThrottled(image: UIImage) {
    guard isGeminiActive, connectionState == .ready else { return }
    let now = Date()
    guard now.timeIntervalSince(lastVideoFrameTime) >= GeminiConfig.videoFrameInterval else { return }
    lastVideoFrameTime = now
    geminiService.sendVideoFrame(image: image)
  }

  private func registerAudioObservers() {
    unregisterAudioObservers()

    let nc = NotificationCenter.default
    audioInterruptionObserver = nc.addObserver(
      forName: AVAudioSession.interruptionNotification,
      object: AVAudioSession.sharedInstance(),
      queue: nil
    ) { [weak self] notification in
      guard let self else { return }
      guard let userInfo = notification.userInfo,
            let raw = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }

      Task { @MainActor in
        guard self.isGeminiActive else { return }
        switch type {
        case .began:
          self.stopSession()
          self.errorMessage = "Audio interrupted (call/Siri). Tap AI to resume."
        case .ended:
          // No-op. User can resume explicitly.
          break
        @unknown default:
          break
        }
      }
    }

    audioRouteObserver = nc.addObserver(
      forName: AVAudioSession.routeChangeNotification,
      object: AVAudioSession.sharedInstance(),
      queue: nil
    ) { [weak self] notification in
      guard let self else { return }
      let reason: AVAudioSession.RouteChangeReason? = {
        guard let userInfo = notification.userInfo,
              let raw = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt else { return nil }
        return AVAudioSession.RouteChangeReason(rawValue: raw)
      }()

      Task { @MainActor in
        self.updateAudioRouteLabel()
        // Do NOT auto-stop the session on route changes. When the user puts on/takes off
        // the glasses, iOS can briefly reshuffle routes; stopping feels like a crash.
        //
        // If audio gets weird, the user can explicitly stop/restart AI. We keep running.
        if reason == .oldDeviceUnavailable {
          NSLog("[Audio] Route change: oldDeviceUnavailable (continuing session)")
        }
      }
    }
  }

  private func unregisterAudioObservers() {
    let nc = NotificationCenter.default
    if let t = audioInterruptionObserver {
      nc.removeObserver(t)
      audioInterruptionObserver = nil
    }
    if let t = audioRouteObserver {
      nc.removeObserver(t)
      audioRouteObserver = nil
    }
  }

  private func updateAudioRouteLabel() {
    let route = AVAudioSession.sharedInstance().currentRoute
    let inName = route.inputs.first?.portName ?? "?"
    let outName = route.outputs.first?.portName ?? "?"
    audioRouteLabel = "\(inName) -> \(outName)"
  }

  private func maybeHandleLocalVoiceCommands(transcript: String) {
    guard isGeminiActive else { return }
    guard !deactivateRequested else { return }

    let norm = normalizeCommandText(transcript)
    // Keep the trigger tight to avoid false positives.
    // We only match explicit "Jarvis stop/deactivate/shutdown" style commands.
    let tokens = norm.split(separator: " ").map(String.init)
    let shouldDeactivate = isExplicitDeactivateCommand(tokens: tokens)
    guard shouldDeactivate else { return }

    deactivateRequested = true
    audioManager.playChime()

    Task { @MainActor in
      // Let the chime be heard before tearing down audio.
      try? await Task.sleep(nanoseconds: 350_000_000)
      self.stopSession()
    }
  }

  private func isExplicitDeactivateCommand(tokens: [String]) -> Bool {
    if tokens.isEmpty { return false }

    // Drop a few common fillers.
    var t = tokens
    while let first = t.first, ["hey", "ok", "okay", "please", "um", "uh"].contains(first) {
      t.removeFirst()
    }
    if t.isEmpty { return false }

    func isAction(_ s: String) -> Bool {
      return ["stop", "deactivate", "shutdown", "shut", "quit", "close"].contains(s)
    }

    // "Jarvis stop", "Jarvis deactivate", "Jarvis shutdown"
    if t.count >= 2, t[0] == "jarvis" {
      if isAction(t[1]) { return true }
      if t.count >= 3, t[1] == "shut", t[2] == "down" { return true }
    }

    // "Stop Jarvis", "Deactivate Jarvis", "Shut down Jarvis"
    if t.count >= 2, isAction(t[0]), t[1] == "jarvis" { return true }
    if t.count >= 3, t[0] == "shut", t[1] == "down", t[2] == "jarvis" { return true }

    return false
  }

  private func normalizeCommandText(_ input: String) -> String {
    // Lowercase, replace punctuation with spaces, and collapse whitespace.
    let lower = input.lowercased()
    var out = ""
    out.reserveCapacity(lower.count)
    for scalar in lower.unicodeScalars {
      if CharacterSet.alphanumerics.contains(scalar) {
        out.unicodeScalars.append(scalar)
      } else {
        out.append(" ")
      }
    }
    return out.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
  }

}
