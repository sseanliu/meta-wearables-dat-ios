import AVFoundation
import Foundation

class AudioManager {
  var onAudioCaptured: ((Data) -> Void)?

  private let audioEngine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var isCapturing = false
  private var suppressCaptureUntil: Date?

  private let outputFormat: AVAudioFormat

  private let chimeFormat: AVAudioFormat

  // Accumulate resampled PCM into ~100ms chunks before sending
  private let sendQueue = DispatchQueue(label: "audio.accumulator")
  private var accumulatedData = Data()
  private let minSendBytes = 3200  // 100ms at 16kHz mono Int16 = 1600 frames * 2 bytes

  init() {
    self.outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: true
    )!
    self.chimeFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: false
    )!
  }

  func setupAudioSession(useIPhoneMode: Bool = false, preferBluetoothOutput: Bool = false) throws {
    let session = AVAudioSession.sharedInstance()
    // iPhone mode: voiceChat for aggressive echo cancellation (mic + speaker co-located)
    // Glasses mode: videoChat for mild AEC (mic is on glasses, speaker is on phone)
    let mode: AVAudioSession.Mode
    if useIPhoneMode {
      mode = .voiceChat
    } else {
      // If we route output to the same device as the mic (glasses), we want stronger AEC.
      mode = preferBluetoothOutput ? .voiceChat : .videoChat
    }

    // Always avoid the iPhone receiver route (quiet). If a Bluetooth route is available,
    // iOS can still select it; this only affects the fallback route.
    let options: AVAudioSession.CategoryOptions = [.allowBluetoothHFP, .defaultToSpeaker]

    try session.setCategory(.playAndRecord, mode: mode, options: options)

    // Force speaker only when explicitly not preferring Bluetooth output.
    if preferBluetoothOutput {
      try? session.overrideOutputAudioPort(.none)
    } else {
      try? session.overrideOutputAudioPort(.speaker)
    }

    try session.setPreferredSampleRate(GeminiConfig.inputAudioSampleRate)
    try session.setPreferredIOBufferDuration(0.064)
    try session.setActive(true)
    let inName = session.currentRoute.inputs.first?.portName ?? "?"
    let outName = session.currentRoute.outputs.first?.portName ?? "?"
    NSLog("[Audio] Session mode: %@ preferBluetooth=%@ route_in=%@ route_out=%@",
          useIPhoneMode ? "voiceChat (iPhone)" : (preferBluetoothOutput ? "voiceChat (glasses)" : "videoChat (glasses)"),
          preferBluetoothOutput ? "YES" : "NO",
          inName,
          outName)
  }

  func startCapture() throws {
    guard !isCapturing else { return }

    audioEngine.attach(playerNode)
    let playerFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: false
    )!
    audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playerFormat)

    let inputNode = audioEngine.inputNode
    let inputNativeFormat = inputNode.outputFormat(forBus: 0)

    NSLog("[Audio] Native input format: %@ sampleRate=%.0f channels=%d",
          inputNativeFormat.commonFormat == .pcmFormatFloat32 ? "Float32" :
          inputNativeFormat.commonFormat == .pcmFormatInt16 ? "Int16" : "Other",
          inputNativeFormat.sampleRate, inputNativeFormat.channelCount)

    // Always tap in native format (Float32) and convert to Int16 PCM manually.
    // AVAudioEngine taps don't reliably convert between sample formats inline.
    let needsResample = inputNativeFormat.sampleRate != GeminiConfig.inputAudioSampleRate
        || inputNativeFormat.channelCount != GeminiConfig.audioChannels

    NSLog("[Audio] Needs resample: %@", needsResample ? "YES" : "NO")

    sendQueue.async { self.accumulatedData = Data() }

    var converter: AVAudioConverter?
    if needsResample {
      let resampleFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: GeminiConfig.inputAudioSampleRate,
        channels: GeminiConfig.audioChannels,
        interleaved: false
      )!
      converter = AVAudioConverter(from: inputNativeFormat, to: resampleFormat)
    }

    var tapCount = 0
    inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputNativeFormat) { [weak self] buffer, _ in
      guard let self else { return }

      tapCount += 1
      let pcmData: Data

      if let converter {
        let resampleFormat = AVAudioFormat(
          commonFormat: .pcmFormatFloat32,
          sampleRate: GeminiConfig.inputAudioSampleRate,
          channels: GeminiConfig.audioChannels,
          interleaved: false
        )!
        guard let resampled = self.convertBuffer(buffer, using: converter, targetFormat: resampleFormat) else {
          if tapCount <= 3 { NSLog("[Audio] Resample failed for tap #%d", tapCount) }
          return
        }
        pcmData = self.float32BufferToInt16Data(resampled)
      } else {
        pcmData = self.float32BufferToInt16Data(buffer)
      }

      // Log first 3 taps, then every ~2 seconds (every 8th tap at 4096 frames/16kHz = ~256ms each)
      // if tapCount <= 3 || tapCount % 8 == 0 {
      //   NSLog("[Audio] Tap #%d: %d frames, %d bytes, rms=%.4f",
      //         tapCount, buffer.frameLength, pcmData.count, rms)
      // }

      // Accumulate into ~100ms chunks before sending to Gemini
      self.sendQueue.async {
        if let until = self.suppressCaptureUntil, Date() < until {
          // Drop mic audio briefly while we play a UI chime so it doesn't get
          // sent to Gemini as user input.
          self.accumulatedData = Data()
          return
        }

        self.accumulatedData.append(pcmData)
        if self.accumulatedData.count >= self.minSendBytes {
          let chunk = self.accumulatedData
          self.accumulatedData = Data()
          if tapCount <= 3 {
            NSLog("[Audio] Sending chunk: %d bytes (~%dms)",
                  chunk.count, chunk.count / 32)  // 16kHz * 2 bytes = 32 bytes/ms
          }
          self.onAudioCaptured?(chunk)
        }
      }
    }

    do {
      try audioEngine.start()
    } catch {
      // If capture setup fails, clean up and release audio session so the user can
      // keep using the glasses for calls/music.
      audioEngine.inputNode.removeTap(onBus: 0)
      playerNode.stop()
      audioEngine.stop()
      audioEngine.detach(playerNode)
      deactivateAudioSession()
      throw error
    }
    playerNode.play()
    isCapturing = true
  }

  func playAudio(data: Data) {
    guard isCapturing, !data.isEmpty else { return }

    let playerFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: false
    )!

    let frameCount = UInt32(data.count) / (GeminiConfig.audioBitsPerSample / 8 * GeminiConfig.audioChannels)
    guard frameCount > 0 else { return }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: frameCount) else { return }
    buffer.frameLength = frameCount

    guard let floatData = buffer.floatChannelData else { return }
    data.withUnsafeBytes { rawBuffer in
      guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
      for i in 0..<Int(frameCount) {
        floatData[0][i] = Float(int16Ptr[i]) / Float(Int16.max)
      }
    }

    playerNode.scheduleBuffer(buffer)
    if !playerNode.isPlaying {
      playerNode.play()
    }
  }

  func stopPlayback() {
    playerNode.stop()
    playerNode.play()
  }

  func stopCapture() {
    guard isCapturing else { return }
    audioEngine.inputNode.removeTap(onBus: 0)
    playerNode.stop()
    audioEngine.stop()
    audioEngine.detach(playerNode)
    isCapturing = false
    deactivateAudioSession()
    // Flush any remaining accumulated audio
    sendQueue.async {
      if !self.accumulatedData.isEmpty {
        let chunk = self.accumulatedData
        self.accumulatedData = Data()
        self.onAudioCaptured?(chunk)
      }
    }
  }

  func playChime() {
    // Play a short, subtle "meditation bell" style chime to indicate task completion.
    guard isCapturing else { return }

    let sampleRate = chimeFormat.sampleRate
    let channels = Int(chimeFormat.channelCount)
    guard channels == 1 else { return }

    let durationSec: Double = 0.65
    let frames = AVAudioFrameCount(max(1, Int(sampleRate * durationSec)))
    guard let buffer = AVAudioPCMBuffer(pcmFormat: chimeFormat, frameCapacity: frames) else { return }
    buffer.frameLength = frames
    guard let data = buffer.floatChannelData else { return }

    sendQueue.async {
      self.suppressCaptureUntil = Date().addingTimeInterval(durationSec + 0.15)
      self.accumulatedData = Data()
    }

    let baseHz: Double = 528.0
    // A few (mostly inharmonic) partials with different decay constants.
    let partials: [(freqHz: Double, decaySec: Double, amp: Double)] = [
      (baseHz * 1.00, 0.90, 0.10),
      (baseHz * 1.20, 0.75, 0.07),
      (baseHz * 1.50, 0.65, 0.06),
      (baseHz * 2.00, 0.50, 0.04),
      (baseHz * 2.70, 0.40, 0.03),
    ]

    let n = Int(frames)
    let attackSec: Double = 0.010
    let attackFrames = max(1, Int(sampleRate * attackSec))
    let endFadeSec: Double = 0.020
    let endFadeFrames = max(1, Int(sampleRate * endFadeSec))

    for i in 0..<n {
      let t = Double(i) / sampleRate

      // Attack and end fade (avoid clicks).
      let attack = min(1.0, Double(i) / Double(attackFrames))
      let tail = max(0.0, min(1.0, Double(n - i - 1) / Double(endFadeFrames)))
      let envEdge = min(attack, tail)

      var v: Double = 0.0
      for p in partials {
        let env = exp(-t / max(0.05, p.decaySec))
        v += p.amp * sin(2.0 * Double.pi * p.freqHz * t) * env
      }

      // Keep it subtle.
      let sample = max(-1.0, min(1.0, v * 0.85 * envEdge))
      data[0][i] = Float(sample)
    }

    playerNode.scheduleBuffer(buffer)
    if !playerNode.isPlaying {
      playerNode.play()
    }
  }

  // MARK: - Private helpers

  func deactivateAudioSession() {
    // Release audio route so calls/music can resume on the glasses.
    do {
      try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    } catch {
      NSLog("[Audio] Failed to deactivate audio session: %@", error.localizedDescription)
    }
  }

  private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0, let floatData = buffer.floatChannelData else { return 0 }
    var sumSquares: Float = 0
    for i in 0..<frameCount {
      let s = floatData[0][i]
      sumSquares += s * s
    }
    return sqrt(sumSquares / Float(frameCount))
  }

  private func float32BufferToInt16Data(_ buffer: AVAudioPCMBuffer) -> Data {
    let frameCount = Int(buffer.frameLength)
    guard frameCount > 0, let floatData = buffer.floatChannelData else { return Data() }
    var int16Array = [Int16](repeating: 0, count: frameCount)
    for i in 0..<frameCount {
      let sample = max(-1.0, min(1.0, floatData[0][i]))
      int16Array[i] = Int16(sample * Float(Int16.max))
    }
    return int16Array.withUnsafeBufferPointer { ptr in
      Data(buffer: ptr)
    }
  }

  private func convertBuffer(
    _ inputBuffer: AVAudioPCMBuffer,
    using converter: AVAudioConverter,
    targetFormat: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let ratio = targetFormat.sampleRate / inputBuffer.format.sampleRate
    let outputFrameCount = UInt32(Double(inputBuffer.frameLength) * ratio)
    guard outputFrameCount > 0 else { return nil }

    guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: outputFrameCount) else {
      return nil
    }

    var error: NSError?
    var consumed = false
    converter.convert(to: outputBuffer, error: &error) { _, outStatus in
      if consumed {
        outStatus.pointee = .noDataNow
        return nil
      }
      consumed = true
      outStatus.pointee = .haveData
      return inputBuffer
    }

    if error != nil {
      return nil
    }

    return outputBuffer
  }
}
