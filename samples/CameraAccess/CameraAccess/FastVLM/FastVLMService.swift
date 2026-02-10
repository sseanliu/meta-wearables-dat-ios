import CoreImage
import Foundation
import MLX
import MLXLMCommon
import MLXVLM
import UIKit

/// On-device vision-language model service using FastVLM (0.5B).
/// Accepts UIImage frames and produces text descriptions.
@Observable
@MainActor
class FastVLMService {

    // MARK: - Public state

    var isActive = false
    var isRunning = false
    var output = ""
    var ttft = ""
    var modelInfo = ""

    enum EvaluationState: String {
        case idle = "Idle"
        case loading = "Loading Model"
        case processingPrompt = "Processing"
        case generatingResponse = "Generating"
    }

    var evaluationState = EvaluationState.idle

    // MARK: - Configuration

    var prompt = "What is the main object? Reply with only its name, max 2 words."

    // MARK: - Private

    private enum LoadState {
        case idle
        case loaded(ModelContainer)
    }

    private let generateParameters = GenerateParameters(temperature: 0.0)
    private let maxTokens = 80

    private var loadState = LoadState.idle
    private var currentTask: Task<Void, Never>?

    private var lastAnalyzeStart = Date.distantPast
    private var frameCount = 0

    // Temporal smoothing: only update displayed label when a new label appears N times in a row
    private let confirmationThreshold = 2
    private var candidateLabel = ""
    private var candidateCount = 0
    private var confirmedLabel = ""

    // MARK: - Init

    init() {
        FastVLM.register(modelFactory: VLMModelFactory.shared)
    }

    // MARK: - Model loading

    private func _load() async throws -> ModelContainer {
        switch loadState {
        case .idle:
            evaluationState = .loading

            MLX.GPU.set(cacheLimit: 256 * 1024 * 1024)

            // Look for the model files in the app bundle's "models" folder
            let modelConfig = FastVLM.modelConfiguration

            let modelContainer = try await VLMModelFactory.shared.loadContainer(
                configuration: modelConfig
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.modelInfo = "Loading model: \(Int(progress.fractionCompleted * 100))%"
                }
            }

            modelInfo = "Model loaded"
            evaluationState = .idle
            loadState = .loaded(modelContainer)
            return modelContainer

        case .loaded(let container):
            return container
        }
    }

    func load() async {
        do {
            _ = try await _load()
        } catch {
            modelInfo = "Error loading model: \(error)"
            evaluationState = .idle
            print("[FastVLM] Load error: \(error)")
        }
    }

    // MARK: - Inference

    /// Analyze a single frame. Returns immediately if already running or model not ready.
    func analyze(_ image: UIImage) async {
        guard let ciImage = CIImage(image: image) else {
            print("[FastVLM] Failed to create CIImage from UIImage")
            return
        }

        if isRunning {
            return
        }

        let gap = Date().timeIntervalSince(lastAnalyzeStart)
        lastAnalyzeStart = Date()
        frameCount += 1
        let thisFrame = frameCount
        print("[FastVLM] Frame #\(thisFrame) - gap since last: \(Int(gap * 1000))ms")

        isRunning = true
        currentTask?.cancel()

        let frameStart = Date()

        let task = Task {
            do {
                let modelContainer = try await _load()

                if Task.isCancelled { return }

                let prepareStart = Date()
                let userInput = UserInput(
                    prompt: .text(prompt),
                    images: [.ciImage(ciImage)]
                )

                let result = try await modelContainer.perform { context in
                    Task { @MainActor in
                        self.evaluationState = .processingPrompt
                    }

                    let input = try await context.processor.prepare(input: userInput)
                    let prepareTime = Date().timeIntervalSince(prepareStart)
                    print("[FastVLM] Frame #\(thisFrame) - image prep: \(Int(prepareTime * 1000))ms")

                    let generateStart = Date()
                    var seenFirstToken = false

                    let result = try MLXLMCommon.generate(
                        input: input, parameters: self.generateParameters, context: context
                    ) { tokens in
                        if Task.isCancelled { return .stop }

                        if !seenFirstToken {
                            seenFirstToken = true
                            let ttftDuration = Date().timeIntervalSince(generateStart)
                            Task { @MainActor in
                                self.evaluationState = .generatingResponse
                                self.ttft = "\(Int(ttftDuration * 1000))ms"
                            }
                            print("[FastVLM] Frame #\(thisFrame) - TTFT: \(Int(ttftDuration * 1000))ms")
                        }

                        if tokens.count >= self.maxTokens {
                            return .stop
                        }
                        return .more
                    }

                    let generateTime = Date().timeIntervalSince(generateStart)
                    print("[FastVLM] Frame #\(thisFrame) - generate: \(Int(generateTime * 1000))ms (\(result.output.count) chars)")

                    return result
                }

                if !Task.isCancelled {
                    let rawLabel = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let totalTime = Date().timeIntervalSince(frameStart)
                    print("[FastVLM] Frame #\(thisFrame) - raw: \"\(rawLabel)\" - TOTAL: \(Int(totalTime * 1000))ms")

                    self.updateLabel(rawLabel)
                }
            } catch {
                if !Task.isCancelled {
                    output = "Failed: \(error)"
                    print("[FastVLM] Frame #\(thisFrame) inference error: \(error)")
                }
            }

            if evaluationState == .generatingResponse {
                evaluationState = .idle
            }
            isRunning = false
        }

        currentTask = task
    }

    /// Temporal smoothing: only update the displayed label when a new label is confirmed N times in a row.
    private func updateLabel(_ rawLabel: String) {
        if rawLabel == confirmedLabel {
            // Same as current — reset candidate
            candidateLabel = ""
            candidateCount = 0
            return
        }

        if rawLabel == candidateLabel {
            candidateCount += 1
        } else {
            candidateLabel = rawLabel
            candidateCount = 1
        }

        if candidateCount >= confirmationThreshold {
            confirmedLabel = rawLabel
            output = rawLabel
            candidateLabel = ""
            candidateCount = 0
            print("[FastVLM] Label confirmed: \"\(rawLabel)\"")
        }
    }

    /// Called from the video frame pipeline. Runs continuously — back-pressure via isRunning guard.
    func analyzeIfReady(image: UIImage) {
        guard isActive, !isRunning else { return }

        Task {
            await analyze(image)
        }
    }

    // MARK: - Lifecycle

    func start() async {
        isActive = true
        output = ""
        ttft = ""
        await load()
    }

    func stop() {
        isActive = false
        cancel()
    }

    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isRunning = false
        output = ""
        ttft = ""
        evaluationState = .idle
        candidateLabel = ""
        candidateCount = 0
        confirmedLabel = ""
    }
}
