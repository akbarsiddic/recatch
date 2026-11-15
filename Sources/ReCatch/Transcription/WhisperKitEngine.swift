import Foundation
import WhisperKit

/// On-device ASR via WhisperKit.
///
/// Model size is a product decision, not a detail: StreamLingo ships Whisper **base** by default
/// and offers large-v3-turbo as an upgrade. Defaulting to the 954 MB turbo is what wedged
/// ANECompilerService for 50+ minutes on this Mac — the encoder compile never returned, so
/// `runTranscribeTask` hung forever and the app looked dead.
actor WhisperKitEngine {
    enum Status: Equatable { case unloaded, loading, ready, failed(String) }

    private(set) var status: Status = .unloaded
    private(set) var modelName = TranscriptionQuality.fast.modelID
    private(set) var progress: Double = 0
    private var model: WhisperKit?
    private var loadTask: Task<Bool, Never>?
    /// One inference at a time: two concurrent CoreML runs on one WhisperKit instance deadlock.
    private let inference = AsyncSemaphore(1)
    private var queued = 0

    var promptHint = "Rina, Akbar, staging, API, deploy, deadline, meeting in English campur Bahasa Indonesia."
    var statusLine = "Model not loaded"
    var phase: TranscriptionPhase = .idle

    /// Point the engine at a quality tier. Swapping models unloads the old one.
    func configure(_ quality: TranscriptionQuality) {
        guard quality.modelID != modelName else { return }
        modelName = quality.modelID
        model = nil
        status = .unloaded
        phase = .idle
        statusLine = "Model not loaded"
        progress = 0
        loadTask = nil
    }

    /// Loads once; concurrent callers wait on the same task instead of racing.
    @discardableResult
    func load() async -> Bool {
        if case .ready = status, model != nil { return true }
        if let t = loadTask { return await t.value }
        let t = Task<Bool, Never> { await self.performLoad() }
        loadTask = t
        let ok = await t.value
        loadTask = nil
        return ok
    }

    /// After a failed/damaged download: forget the failure so the next call retries cleanly.
    func retry() {
        status = .unloaded
        phase = .idle
        progress = 0
        statusLine = "Retrying model download…"
        loadTask = nil
    }

    private func setProgress(_ value: Double) {
        progress = min(1, max(0, value))
        if case .loading = status {
            statusLine = "Downloading \(modelName) — \(Int(progress * 100))%"
        }
    }

    private func performLoad() async -> Bool {
        status = .loading
        phase = .downloading
        progress = 0
        statusLine = "Preparing \(modelName)…"
        do {
            // Explicit download so the UI can show real progress instead of a spinner.
            let folder = try await WhisperKit.download(variant: modelName) { [weak self] p in
                let value = p.fractionCompleted
                Task { await self?.setProgress(value) }
            }
            statusLine = "Loading model…"
            let m = try await WhisperKit(model: modelName, modelFolder: folder.path,
                                     computeOptions: Self.computeOptions(for: modelName.contains("turbo") ? .accurate : .fast))
            model = m
            status = .ready
            phase = .ready
            progress = 1
            statusLine = "Model ready"
            Debug.log("whisper loaded: \(modelName)")
            return true
        } catch {
            let message = error.localizedDescription
            status = .failed(message)
            phase = .failed
            // A half-downloaded model folder is the most common cause; say so, and offer retry.
            statusLine = message.lowercased().contains("corrupt") || message.lowercased().contains("damaged")
                ? "Model download was damaged — tap Retry in Settings."
                : "Model failed — \(message.prefix(60))"
            Debug.log("whisper load FAILED: \(message)")
            return false
        }
    }

    /// Compute placement is a stability decision, learned the hard way on this Mac:
    ///
    /// - The **large-v3-turbo** encoder on GPU crashes inside MetalPerformanceShadersGraph
    ///   (`GPU::StitchedOpHandler::encodeOp` → SIGSEGV). That is an unrecoverable app crash
    ///   mid-meeting, so the big model runs on the Neural Engine instead.
    /// - The **base** encoder is tiny and has run for hours on GPU without a single fault.
    ///
    /// ANE compilation of a big encoder is slow the first time (and pathological on some Macs,
    /// upstream argmaxinc/argmax-oss-swift#560), but it is cached afterwards. `RECATCH_ANE=1`
    /// forces ANE for every tier.
    static func computeOptions(for quality: TranscriptionQuality = .fast) -> ModelComputeOptions {
        let env = ProcessInfo.processInfo.environment
        if env["RECATCH_ANE"] == "1" {
            return ModelComputeOptions(melCompute: .cpuAndGPU,
                                       audioEncoderCompute: .cpuAndNeuralEngine,
                                       textDecoderCompute: .cpuAndNeuralEngine,
                                       prefillCompute: .cpuOnly)
        }
        // The 954 MB turbo encoder is broken on this class of machine both ways:
        //   GPU → SIGSEGV inside MetalPerformanceShadersGraph while encoding
        //   ANE → ANECompilerService pins a core for tens of minutes and never returns
        // CPU is the only placement that survives. Slower, but it answers.
        if quality == .accurate {
            return ModelComputeOptions(melCompute: .cpuOnly,
                                       audioEncoderCompute: .cpuOnly,
                                       textDecoderCompute: .cpuOnly,
                                       prefillCompute: .cpuOnly)
        }
        return ModelComputeOptions(melCompute: .cpuAndGPU,
                                   audioEncoderCompute: .cpuAndGPU,
                                   textDecoderCompute: .cpuAndGPU,
                                   prefillCompute: .cpuOnly)
    }

    /// Returns (text, lang, langProb, confidence). Empty text is dropped upstream.
    func transcribe(_ pcm: [Int16], hint: LanguageHint) async throws -> (String, String, Double, Double) {
        guard await load(), let model else { return ("", "en", 0, 0) }
        if queued > 2 {
            Debug.log("dropped chunk — \(queued) already queued")
            return ("", "en", 0, 0)
        }
        queued += 1
        await inference.wait()
        defer { inference.signal(); queued -= 1 }
        guard !pcm.isEmpty else { return ("", "en", 0, 0) }

        let floats = pcm.map { Float($0) / 32768.0 }
        var opts = DecodingOptions()
        switch hint {
        case .mixed, .auto:
            opts.language = nil // auto-detect per window
        default:
            opts.language = hint.rawValue
        }
        // Only bias with the prompt when the language is ambiguous; a bilingual prompt on a
        // named language drags Whisper back toward English.
        if hint == .mixed, let tokens = model.tokenizer?.encode(text: promptHint) {
            opts.promptTokens = tokens
        }
        opts.noSpeechThreshold = 0.6
        opts.logProbThreshold = -1.0
        opts.compressionRatioThreshold = 2.4
        opts.temperatureFallbackCount = 3
        opts.skipSpecialTokens = true // never leak <|startoftranscript|> into the transcript

        let results: [TranscriptionResult]
        do {
            statusLine = "Transcribing…"
            results = try await model.runTranscribeTask(audioArray: floats, decodeOptions: opts)
            statusLine = "Model ready"
        } catch {
            status = .failed(error.localizedDescription)
            phase = .failed
            statusLine = "Transcription failed — will retry."
            return ("", "en", 0, 0)
        }
        let raw = results.flatMap(\.segments).map(\.text).joined(separator: " ")
        Debug.log("whisper raw(\(results.count) res, \(String(format: "%.1f", Double(pcm.count)/16000))s): \(raw.isEmpty ? "<none>" : String(raw.prefix(90)))")
        let out = Self.filtered(results)
        if out.0.isEmpty {
            statusLine = results.flatMap(\.segments).isEmpty
                ? "Model ready — heard audio, no words detected."
                : "Model ready — last window unclear, skipped."
        }
        return out
    }

    /// Join kept segments; drop no-speech / low-confidence / repeated-phrase junk.
    static func filtered(_ results: [TranscriptionResult]) -> (String, String, Double, Double) {
        let plain = results.flatMap(\.segments).map {
            TranscriptionFilter.Segment(text: $0.text, noSpeechProb: $0.noSpeechProb, avgLogprob: $0.avgLogprob)
        }
        let lang = results.first?.language ?? "en"
        let (text, lp, conf) = TranscriptionFilter.filter(plain)
        guard !text.isEmpty else { return ("", "en", 0, 0) }
        return (text, lang, lp, conf)
    }
}
