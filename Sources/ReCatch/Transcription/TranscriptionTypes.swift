import Foundation

struct TranscriptSegment: Identifiable, Codable, Sendable {
    let id: UUID
    let meetingId: UUID
    var tStartMs: Int64
    var tEndMs: Int64
    var stream: AudioStream
    var lang: String
    var langProb: Double
    var text: String
    var confidence: Double
}

/// Global-ready: auto-detect any Whisper language (99 langs, like LiveLingo's 35+).
/// Hint is a preference, not a lock: "auto" (default), ISO code ("en","id","es","zh","ar",…), or "mixed" (= auto + bilingual prompt hint, legacy behavior).
enum LanguageHint: String { case auto, en, id, mixed
    /// Arbitrary ISO code beyond the enum cases, e.g. "es", "zh", "ja".
    static func custom(_ code: String) -> String { code.lowercased() }
}

/// VAD-gated chunker config: 250ms hangover, 400ms padding, 5-15s chunks.
struct VADConfig {
    var threshold: Float = 0.5
    var hangoverMs: Int = 250
    var maxChunkSec: Double = 15
}
