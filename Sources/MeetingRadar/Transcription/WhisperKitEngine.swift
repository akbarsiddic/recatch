import Foundation

/// On-device ASR via WhisperKit (largev3-turbo default). Falls back to stub until model downloads.
final class WhisperKitEngine {
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
        guard case .ready = status else { await load() ; return ("", "en", 0, 0) }
        // Placeholder until WhisperKit wired on Mac. Real call:
        // let res = try await model.transcribe(audioArray: pcmFloat, decodeOptions: [...], promptHint: promptHint)
        // Filter: drop noSpeechProb>0.6, avgLogProb<-1.0, repeated phrases.
        return ("", "en", 0.5, 0.5)
    }
}
