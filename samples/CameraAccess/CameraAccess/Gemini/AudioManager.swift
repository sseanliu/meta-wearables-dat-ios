import AVFoundation
import Foundation

class AudioManager {
  var onAudioCaptured: ((Data) -> Void)?

  private let audioEngine = AVAudioEngine()
  private let playerNode = AVAudioPlayerNode()
  private var isCapturing = false

  private let outputFormat: AVAudioFormat

  init() {
    self.outputFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: true
    )!
  }

  func setupAudioSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .voiceChat,
      options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
    )
    try session.setPreferredSampleRate(GeminiConfig.inputAudioSampleRate)
    try session.setPreferredIOBufferDuration(0.064)
    try session.setActive(true)
    #if DEBUG
    NSLog("[AudioManager] Audio session active. sampleRate=\(session.sampleRate), inputChannels=\(session.inputNumberOfChannels), outputChannels=\(session.outputNumberOfChannels), category=\(session.category.rawValue)")
    #endif
  }

  func startCapture() throws {
    guard !isCapturing else { return }

    audioEngine.attach(playerNode)
    // Connect player node for output at 24kHz for Gemini response playback
    let playerFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: false
    )!
    audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playerFormat)

    // Install tap on input node for mic capture
    let inputNode = audioEngine.inputNode
    let inputNativeFormat = inputNode.outputFormat(forBus: 0)

    // Target format: 16kHz mono Int16
    let targetFormat = AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: GeminiConfig.inputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: true
    )!

    // Check if we can install tap at target format directly
    // AVAudioEngine can do format conversion in the tap
    let tapFormat: AVAudioFormat
    var converter: AVAudioConverter?

    if inputNativeFormat.sampleRate == GeminiConfig.inputAudioSampleRate
        && inputNativeFormat.channelCount == GeminiConfig.audioChannels {
      tapFormat = targetFormat
    } else {
      // Install tap at native format, convert manually
      tapFormat = inputNativeFormat
      converter = AVAudioConverter(from: inputNativeFormat, to: targetFormat)
    }

    #if DEBUG
    NSLog("[AudioManager] Input native format: \(inputNativeFormat), tapFormat: \(tapFormat), needsConverter: \(converter != nil)")
    #endif

    var captureCount = 0
    inputNode.installTap(onBus: 0, bufferSize: 1024, format: tapFormat) { [weak self] buffer, _ in
      guard let self else { return }
      captureCount += 1

      if let converter {
        guard let convertedBuffer = self.convertBuffer(buffer, using: converter, targetFormat: targetFormat) else {
          if captureCount <= 3 {
            NSLog("[AudioManager] Conversion failed for buffer #\(captureCount)")
          }
          return
        }
        let data = self.bufferToData(convertedBuffer)
        if captureCount <= 3 || captureCount % 100 == 0 {
          NSLog("[AudioManager] Captured audio #\(captureCount): \(data.count) bytes (converted)")
        }
        self.onAudioCaptured?(data)
      } else {
        let data = self.bufferToData(buffer)
        if captureCount <= 3 || captureCount % 100 == 0 {
          NSLog("[AudioManager] Captured audio #\(captureCount): \(data.count) bytes")
        }
        self.onAudioCaptured?(data)
      }
    }

    try audioEngine.start()
    playerNode.play()
    isCapturing = true
    #if DEBUG
    NSLog("[AudioManager] Engine started, playerNode playing, capture active")
    #endif
  }

  private var playCount = 0

  func playAudio(data: Data) {
    guard isCapturing, !data.isEmpty else {
      #if DEBUG
      NSLog("[AudioManager] playAudio skipped: isCapturing=\(isCapturing), dataEmpty=\(data.isEmpty)")
      #endif
      return
    }

    playCount += 1
    let count = playCount

    // Gemini sends PCM 24kHz 16-bit mono
    // Convert to float32 for AVAudioPlayerNode
    let playerFormat = AVAudioFormat(
      commonFormat: .pcmFormatFloat32,
      sampleRate: GeminiConfig.outputAudioSampleRate,
      channels: GeminiConfig.audioChannels,
      interleaved: false
    )!

    let frameCount = UInt32(data.count) / (GeminiConfig.audioBitsPerSample / 8 * GeminiConfig.audioChannels)
    guard frameCount > 0 else {
      #if DEBUG
      NSLog("[AudioManager] playAudio: 0 frames from \(data.count) bytes")
      #endif
      return
    }

    guard let buffer = AVAudioPCMBuffer(pcmFormat: playerFormat, frameCapacity: frameCount) else {
      #if DEBUG
      NSLog("[AudioManager] playAudio: failed to create buffer")
      #endif
      return
    }
    buffer.frameLength = frameCount

    // Convert Int16 PCM data to Float32
    guard let floatData = buffer.floatChannelData else { return }
    data.withUnsafeBytes { rawBuffer in
      guard let int16Ptr = rawBuffer.bindMemory(to: Int16.self).baseAddress else { return }
      for i in 0..<Int(frameCount) {
        floatData[0][i] = Float(int16Ptr[i]) / Float(Int16.max)
      }
    }

    #if DEBUG
    if count <= 5 || count % 50 == 0 {
      NSLog("[AudioManager] Playing audio #\(count): \(frameCount) frames, playerPlaying=\(playerNode.isPlaying)")
    }
    #endif

    playerNode.scheduleBuffer(buffer)
    if !playerNode.isPlaying {
      #if DEBUG
      NSLog("[AudioManager] Restarting playerNode")
      #endif
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
  }

  // MARK: - Private helpers

  private func bufferToData(_ buffer: AVAudioPCMBuffer) -> Data {
    let frameCount = Int(buffer.frameLength)
    let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)

    if buffer.format.commonFormat == .pcmFormatInt16 {
      guard let int16Data = buffer.int16ChannelData else { return Data() }
      return Data(bytes: int16Data[0], count: frameCount * bytesPerFrame)
    } else if buffer.format.commonFormat == .pcmFormatFloat32 {
      // Convert float32 to int16
      guard let floatData = buffer.floatChannelData else { return Data() }
      var int16Array = [Int16](repeating: 0, count: frameCount)
      for i in 0..<frameCount {
        let sample = max(-1.0, min(1.0, floatData[0][i]))
        int16Array[i] = Int16(sample * Float(Int16.max))
      }
      return int16Array.withUnsafeBufferPointer { ptr in
        Data(buffer: ptr)
      }
    }
    return Data()
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

    if let error {
      #if DEBUG
      NSLog("[AudioManager] Conversion error: \(error.localizedDescription)")
      #endif
      return nil
    }

    return outputBuffer
  }
}
