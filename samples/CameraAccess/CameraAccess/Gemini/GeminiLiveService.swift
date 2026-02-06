import Foundation
import UIKit

enum GeminiConnectionState: Equatable {
  case disconnected
  case connecting
  case settingUp
  case ready
  case error(String)
}

@MainActor
class GeminiLiveService: ObservableObject {
  @Published var connectionState: GeminiConnectionState = .disconnected
  @Published var isModelSpeaking: Bool = false

  var onAudioReceived: ((Data) -> Void)?
  var onTurnComplete: (() -> Void)?
  var onInterrupted: (() -> Void)?
  var onDisconnected: ((String?) -> Void)?

  private var webSocketTask: URLSessionWebSocketTask?
  private var receiveTask: Task<Void, Never>?
  private var connectContinuation: CheckedContinuation<Bool, Never>?
  private let delegate = WebSocketDelegate()
  private var urlSession: URLSession!
  private let sendQueue = DispatchQueue(label: "gemini.send", qos: .userInitiated)

  init() {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30
    // Create session with delegate to monitor WebSocket lifecycle
    self.urlSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
  }

  func connect() async -> Bool {
    guard let url = GeminiConfig.websocketURL() else {
      connectionState = .error("No API key configured")
      return false
    }

    #if DEBUG
    NSLog("[GeminiLive] Connecting to: \(url.host ?? "unknown")...")
    #endif

    connectionState = .connecting

    // Wait for WebSocket open, then send setup, then wait for setupComplete
    let result = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
      self.connectContinuation = continuation

      // Set up delegate callbacks
      self.delegate.onOpen = { [weak self] protocol_ in
        guard let self else { return }
        #if DEBUG
        NSLog("[GeminiLive] WebSocket opened (protocol: \(protocol_ ?? "none"))")
        #endif
        Task { @MainActor in
          self.connectionState = .settingUp
          self.sendSetupMessage()
          self.startReceiving()
        }
      }

      self.delegate.onClose = { [weak self] code, reason in
        guard let self else { return }
        let reasonStr = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "no reason"
        #if DEBUG
        NSLog("[GeminiLive] WebSocket closed: code=\(code.rawValue), reason=\(reasonStr)")
        #endif
        Task { @MainActor in
          self.resolveConnect(success: false)
          self.connectionState = .disconnected
          self.isModelSpeaking = false
          self.onDisconnected?("Connection closed (code \(code.rawValue): \(reasonStr))")
        }
      }

      self.delegate.onError = { [weak self] error in
        guard let self else { return }
        let msg = error?.localizedDescription ?? "Unknown error"
        #if DEBUG
        NSLog("[GeminiLive] Session error: \(msg)")
        #endif
        Task { @MainActor in
          self.resolveConnect(success: false)
          self.connectionState = .error(msg)
          self.isModelSpeaking = false
          self.onDisconnected?(msg)
        }
      }

      self.webSocketTask = self.urlSession.webSocketTask(with: url)
      self.webSocketTask?.resume()

      // Timeout after 15 seconds
      Task {
        try? await Task.sleep(nanoseconds: 15_000_000_000)
        await MainActor.run {
          self.resolveConnect(success: false)
          if self.connectionState == .connecting || self.connectionState == .settingUp {
            self.connectionState = .error("Connection timed out")
          }
        }
      }
    }

    return result
  }

  func disconnect() {
    receiveTask?.cancel()
    receiveTask = nil
    webSocketTask?.cancel(with: .normalClosure, reason: nil)
    webSocketTask = nil
    delegate.onOpen = nil
    delegate.onClose = nil
    delegate.onError = nil
    connectionState = .disconnected
    isModelSpeaking = false
    resolveConnect(success: false)
  }

  private var audioSendCount = 0

  func sendAudio(data: Data) {
    guard connectionState == .ready else { return }
    audioSendCount += 1
    let count = audioSendCount
    sendQueue.async { [weak self] in
      let base64 = data.base64EncodedString()
      let json: [String: Any] = [
        "realtimeInput": [
          "audio": [
            "mimeType": "audio/pcm;rate=16000",
            "data": base64
          ]
        ]
      ]
      self?.sendJSON(json)
      if count <= 5 || count % 50 == 0 {
        NSLog("[GeminiLive] Sent audio chunk #\(count): \(data.count) bytes")
      }
    }
  }

  func sendVideoFrame(image: UIImage) {
    guard connectionState == .ready else { return }
    sendQueue.async { [weak self] in
      guard let jpegData = image.jpegData(compressionQuality: GeminiConfig.videoJPEGQuality) else {
        NSLog("[GeminiLive] Failed to create JPEG from image")
        return
      }
      let base64 = jpegData.base64EncodedString()
      NSLog("[GeminiLive] Sending video frame: \(jpegData.count) bytes JPEG")
      let json: [String: Any] = [
        "realtimeInput": [
          "video": [
            "mimeType": "image/jpeg",
            "data": base64
          ]
        ]
      ]
      self?.sendJSON(json)
    }
  }

  // MARK: - Private

  private func resolveConnect(success: Bool) {
    if let cont = connectContinuation {
      connectContinuation = nil
      cont.resume(returning: success)
    }
  }

  private func sendSetupMessage() {
    let setup: [String: Any] = [
      "setup": [
        "model": GeminiConfig.model,
        "generationConfig": [
          "responseModalities": ["AUDIO"]
        ],
        "systemInstruction": [
          "parts": [
            ["text": GeminiConfig.systemInstruction]
          ]
        ],
        "realtimeInputConfig": [
          "automaticActivityDetection": [
            "disabled": false
          ]
        ]
      ]
    ]
    sendJSON(setup)
  }

  private func sendJSON(_ json: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: json),
          let string = String(data: data, encoding: .utf8) else {
      return
    }
    webSocketTask?.send(.string(string)) { error in
      if let error {
        #if DEBUG
        NSLog("[GeminiLive] Send error: \(error.localizedDescription)")
        #endif
      }
    }
  }

  private func startReceiving() {
    receiveTask = Task { [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        guard let task = self.webSocketTask else { break }
        do {
          let message = try await task.receive()
          switch message {
          case .string(let text):
            await self.handleMessage(text)
          case .data(let data):
            if let text = String(data: data, encoding: .utf8) {
              await self.handleMessage(text)
            }
          @unknown default:
            break
          }
        } catch {
          if !Task.isCancelled {
            let reason = error.localizedDescription
            #if DEBUG
            NSLog("[GeminiLive] Receive error: \(reason)")
            #endif
            await MainActor.run {
              self.resolveConnect(success: false)
              self.connectionState = .disconnected
              self.isModelSpeaking = false
              self.onDisconnected?(reason)
            }
          }
          break
        }
      }
    }
  }

  private func handleMessage(_ text: String) async {
    guard let data = text.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return
    }

    #if DEBUG
    let keys = json.keys.joined(separator: ", ")
    NSLog("[GeminiLive] Message keys: \(keys)")
    #endif

    // Setup complete
    if json["setupComplete"] != nil {
      #if DEBUG
      NSLog("[GeminiLive] Setup complete - ready for audio/video")
      #endif
      connectionState = .ready
      resolveConnect(success: true)
      return
    }

    // GoAway - server will close soon
    if let goAway = json["goAway"] as? [String: Any] {
      let timeLeft = goAway["timeLeft"] as? [String: Any]
      let seconds = timeLeft?["seconds"] as? Int ?? 0
      #if DEBUG
      NSLog("[GeminiLive] GoAway, time left: \(seconds)s")
      #endif
      connectionState = .disconnected
      isModelSpeaking = false
      onDisconnected?("Server closing (time left: \(seconds)s)")
      return
    }

    // Server content
    if let serverContent = json["serverContent"] as? [String: Any] {
      #if DEBUG
      let scKeys = serverContent.keys.joined(separator: ", ")
      NSLog("[GeminiLive] serverContent keys: \(scKeys)")
      #endif

      if let interrupted = serverContent["interrupted"] as? Bool, interrupted {
        #if DEBUG
        NSLog("[GeminiLive] Model interrupted")
        #endif
        isModelSpeaking = false
        onInterrupted?()
        return
      }

      if let modelTurn = serverContent["modelTurn"] as? [String: Any],
         let parts = modelTurn["parts"] as? [[String: Any]] {
        #if DEBUG
        NSLog("[GeminiLive] modelTurn with \(parts.count) parts")
        #endif
        for part in parts {
          if let inlineData = part["inlineData"] as? [String: Any],
             let mimeType = inlineData["mimeType"] as? String {
            #if DEBUG
            NSLog("[GeminiLive] Part mimeType: \(mimeType)")
            #endif
            if mimeType.hasPrefix("audio/pcm"),
               let base64Data = inlineData["data"] as? String,
               let audioData = Data(base64Encoded: base64Data) {
              #if DEBUG
              NSLog("[GeminiLive] Audio chunk received: \(audioData.count) bytes")
              #endif
              if !isModelSpeaking {
                isModelSpeaking = true
              }
              onAudioReceived?(audioData)
            }
          } else if let text = part["text"] as? String {
            #if DEBUG
            NSLog("[GeminiLive] Text part: \(text.prefix(100))")
            #endif
          } else {
            #if DEBUG
            let partKeys = part.keys.joined(separator: ", ")
            NSLog("[GeminiLive] Unknown part keys: \(partKeys)")
            #endif
          }
        }
      }

      if let turnComplete = serverContent["turnComplete"] as? Bool, turnComplete {
        #if DEBUG
        NSLog("[GeminiLive] Turn complete")
        #endif
        isModelSpeaking = false
        onTurnComplete?()
      }

      // Log input/output transcription if present
      #if DEBUG
      if let inputTranscription = serverContent["inputTranscription"] as? [String: Any],
         let text = inputTranscription["text"] as? String {
        NSLog("[GeminiLive] Input transcription: \(text)")
      }
      if let outputTranscription = serverContent["outputTranscription"] as? [String: Any],
         let text = outputTranscription["text"] as? String {
        NSLog("[GeminiLive] Output transcription: \(text)")
      }
      #endif
    }
  }
}

// MARK: - WebSocket Delegate

private class WebSocketDelegate: NSObject, URLSessionWebSocketDelegate {
  var onOpen: ((String?) -> Void)?
  var onClose: ((URLSessionWebSocketTask.CloseCode, Data?) -> Void)?
  var onError: ((Error?) -> Void)?

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didOpenWithProtocol protocol: String?
  ) {
    onOpen?(`protocol`)
  }

  func urlSession(
    _ session: URLSession,
    webSocketTask: URLSessionWebSocketTask,
    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
    reason: Data?
  ) {
    onClose?(closeCode, reason)
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    if let error {
      onError?(error)
    }
  }
}
