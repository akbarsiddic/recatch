import Foundation

/// Transcription engine phase. Lives here (not WhisperKitEngine) so UI code
/// can switch on it without importing WhisperKit.
enum TranscriptionPhase: String, Sendable {
    case idle, downloading, ready, failed
}

/// Pure transcription post-filter: no model, no dependencies — unit-testable.
///
/// Drops no-speech, low-confidence and repeated-phrase hallucinations.
/// WhisperKitEngine maps its segments onto FilterSegment and calls this.
enum TranscriptionFilter {
    struct Segment: Sendable {
        let text: String
        let noSpeechProb: Float
        let avgLogprob: Float
    }

    /// Remove [Music], [BLANK_AUDIO], (applause), ♪ etc. If nothing is left, there was no speech.
    static func stripAnnotations(_ text: String) -> String {
        var t = text
        for pattern in ["\\[[^\\]]*\\]", "\\([^\\)]*\\)", "♪", "♫"] {
            t = t.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        // Collapse leftover punctuation-only output ("...", "-", " .").
        t = t.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        let meaningful = t.unicodeScalars.contains { CharacterSet.alphanumerics.contains($0) }
        return meaningful ? t.trimmingCharacters(in: .whitespacesAndNewlines) : ""
    }

    /// Returns (text, langProb, confidence). Empty text = drop the chunk.
    static func filter(_ segs: [Segment]) -> (String, Double, Double) {
        let kept = segs.filter { seg in
            guard seg.noSpeechProb <= 0.6, seg.avgLogprob >= -1.0 else { return false }
            let t = seg.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !t.isEmpty else { return false }
            // Non-speech annotations Whisper emits on noise: [Music], [BLANK_AUDIO], (applause)…
            if stripAnnotations(t).isEmpty { return false }
            // Repeated-phrase hallucination: one unique word looping.
            let words = t.lowercased().split(separator: " ")
            if words.count >= 4, Set(words).count == 1 { return false }
            return true
        }
        guard !kept.isEmpty else { return ("", 0, 0) }
        let text = stripAnnotations(kept.map(\.text).joined(separator: " "))
        guard !text.isEmpty else { return ("", 0, 0) }
        let avgLog = kept.map(\.avgLogprob).reduce(0, +) / Float(kept.count)
        let confidence = Double(max(0, min(1, exp(min(0, avgLog)))))
        let speechiness = kept.map { 1 - $0.noSpeechProb }.reduce(0, +) / Float(kept.count)
        return (text, Double(max(0, min(1, speechiness))), confidence)
    }
}
