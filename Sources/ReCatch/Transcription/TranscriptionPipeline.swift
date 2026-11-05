import Foundation

/// Per-stream pipeline: chunk -> ASR -> store. Labels come from stream, not diarization.
actor TranscriptionPipeline {
    private let meetingId: UUID
    private let hint: LanguageHint
    private var buffer: [TranscriptSegment] = []
    private var langHistory: [String] = []
    var onSegment: (@Sendable (TranscriptSegment) -> Void)?

    init(meetingId: UUID = UUID(), hint: LanguageHint = .mixed) { self.meetingId = meetingId; self.hint = hint }

    func setOnSegment(_ h: (@Sendable (TranscriptSegment) -> Void)?) { onSegment = h }

    func ingest(_ chunk: AudioChunk, text: String, lang: String, confidence: Double) {
        let smooth = LanguageRouter.smoothed(current: lang, prob: confidence, history: langHistory)
        langHistory.append(smooth); if langHistory.count > 10 { langHistory.removeFirst() }
        let seg = TranscriptSegment(
            id: UUID(), meetingId: meetingId,
            tStartMs: chunk.meetingMs, tEndMs: chunk.meetingMs,
            stream: chunk.stream, lang: lang, langProb: 0.8,
            text: text, confidence: confidence
        )
        buffer.append(seg)
        onSegment?(seg)
    }

    func segments(since ms: Int64) -> [TranscriptSegment] {
        buffer.filter { $0.tStartMs >= ms }
    }
}

/// Language router: per-chunk detect with smoothing (majority vote over 3, inherit on low prob).
enum LanguageRouter {
    static func smoothed(current: String, prob: Double, history: [String]) -> String {
        if prob < 0.6, let last = history.last { return last }
        let last3 = (history + [current]).suffix(3)
        var counts: [String: Int] = [:]
        last3.forEach { counts[$0, default: 0] += 1 }
        return counts.max(by: { $0.value < $1.value })?.key ?? current
    }
}
