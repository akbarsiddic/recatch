import Foundation
import WhisperKit

/// On-device ASR via WhisperKit (largev3-turbo). Falls back to empty (dropped by
/// the pipeline) until the model downloads or if loading fails offline.
actor WhisperKitEngine {
    enum Status { case unloaded, loading, ready, failed(String) }
    private(set) var status: Status = .unloaded
    var promptHint = "Rina, Akbar, staging, API, meeting in English campur Bahasa Indonesia."
    var modelName = "openai_whisper-large-v3_turbo_954MB"

    private var model: WhisperKit?

    func setModel(_ name: String) { modelName = name }

    func load() async {
        status = .loading
        phase = .downloading
        statusLine = "Downloading model (first run, ~2 GB)…"
        do {
            // Downloads on first run (~800 MB–2 GB); cached afterwards.
            let m = try await WhisperKit(model: modelName)
            self.model = m
            statusLine = "Loading model…"
            status = .ready
            phase = .ready
            statusLine = "Model ready"
        } catch {
            status = .failed(error.localizedDescription)
            phase = .failed
            statusLine = "Model failed — offline? Will retry next chunk."
        }
    }

    /// Human-readable phase for the menu/panel. Prefer `phase` over string-sniffing.
    var statusLine = "Model not loaded"
    var phase: TranscriptionPhase = .idle

    /// Returns (text, lang, langProb, confidence).
    /// Empty text (silence / filtered hallucination / unloaded model) is dropped upstream.
    func transcribe(_ pcm: [Int16], hint: LanguageHint) async throws -> (String, String, Double, Double) {
        if case .unloaded = status { await load() }
        guard case .ready = status, let model else { return ("", "en", 0, 0) }
        guard !pcm.isEmpty else { return ("", "en", 0, 0) }

        let floats = pcm.map { Float($0) / 32768.0 }
        var opts = DecodingOptions()
        switch hint {
        case .mixed, .auto:
            opts.language = nil // auto-detect per chunk (code-switch safe)
        default:
            opts.language = hint.rawValue
        }
        if hint == .mixed, let tokens = model.tokenizer?.encode(text: promptHint) {
            opts.promptTokens = tokens
        }
        opts.noSpeechThreshold = 0.6
        opts.logProbThreshold = -1.0
        opts.compressionRatioThreshold = 2.4
        opts.temperatureFallbackCount = 3
        opts.skipSpecialTokens = true // never leak <|startoftranscript|> etc. into the transcript

        let results: [TranscriptionResult]
        do {
            statusLine = "Transcribing…"
            results = try await model.runTranscribeTask(audioArray: floats, decodeOptions: opts)
            statusLine = "Model ready"
        } catch {
            status = .failed(error.localizedDescription)
            phase = .failed
            statusLine = "Transcription failed — will retry next chunk."
            return ("", "en", 0, 0)
        }
        let out = Self.filtered(results)
        if out.0.isEmpty {
            // Silent drops are the "nothing happens" complaint: say why.
            statusLine = results.flatMap(\.segments).isEmpty
                ? "Model ready — heard audio, no words detected."
                : "Model ready — last chunk unclear, skipped."
        }
        return out
    }

    /// Join kept segments; drop no-speech / low-confidence / repeated-phrase junk.
    /// Pure core lives in TranscriptionFilter (unit-tested without a model download).
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
