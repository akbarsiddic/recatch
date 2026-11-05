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

enum LanguageHint: String { case auto, en, id, mixed }

/// VAD-gated chunker config: 250ms hangover, 400ms padding, 5-15s chunks.
struct VADConfig {
    var threshold: Float = 0.5
    var hangoverMs: Int = 250
    var maxChunkSec: Double = 15
}
