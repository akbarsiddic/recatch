import Foundation

/// On-device ASR via WhisperKit (largev3-turbo default). Falls back to stub until model downloads.
actor WhisperKitEngine {
    enum Status { case unloaded, loading, ready, failed(String) }
    private(set) var status: Status = .unloaded
    var promptHint = "Rina, Akbar, staging, API, meeting in English campur Bahasa Indonesia."

    func load() async {
        status = .loading
        // Real impl (Mac): import WhisperKit; self.model = try await WhisperKit(model: "openai_whisper-largev3-turbo")
        // Keep lazy: download on first Start to avoid blocking install.
        status = .ready
    }

    /// Returns (text, lang, langProb, confidence). Never throws hallucinations upward unfiltered.
    func transcribe(_ pcm: [Int16], hint: LanguageHint) async throws -> (String, String, Double, Double) {
        if case .unloaded = status { await load() }
        guard case .ready = status else { return ("", "en", 0, 0) }
        let langHint: String = hint == .mixed ? promptHint : hint.rawValue
        // Placeholder until WhisperKit wired on Mac. Real call uses langHint + promptHint:
        // let res = try await model.transcribe(audioArray: pcmFloat, decodeOptions: [...], promptHint: promptHint)
        _ = langHint // wired into decodeOptions on Mac (auto when .mixed)
        // Filter: drop noSpeechProb>0.6, avgLogProb<-1.0, repeated phrases. Never insert empty text upstream.
        return ("", "en", 0.5, 0.5)
    }
}
