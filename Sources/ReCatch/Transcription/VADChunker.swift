import Foundation

/// VAD-gated chunker: accumulates voiced PCM, emits 5–15s chunks. One instance per stream.
final class VADChunker: @unchecked Sendable {
    private let lock = NSLock()
    private let config: VADConfig
    private var voiced: [Int16] = []
    private var silenceMs = 0
    private var chunkStartMs: Int64 = 0
    var onChunk: (@Sendable (AudioChunk) -> Void)?

    init(config: VADConfig = VADConfig()) { self.config = config }

    /// Feed 16k mono frames of any length. Energy gate stands in for Silero until CoreML model ships.
    /// Duration is derived from the sample count (16 samples = 1 ms), not assumed.
    func feed(pcm: [Int16], stream: AudioStream, meetingMs: Int64) {
        lock.lock(); defer { lock.unlock() }
        let frameMs = pcm.isEmpty ? 0 : pcm.count / 16
        let energy = pcm.isEmpty ? 0 : pcm.reduce(0) { $0 + Int64($1) * Int64($1) } / Int64(pcm.count)
        let isVoiced = energy > 800_000 // ~sensitive enough for laptop mics; Silero replaces this
        if voiced.isEmpty { chunkStartMs = meetingMs }
        if isVoiced {
            voiced.append(contentsOf: pcm)
            silenceMs = 0
        } else {
            silenceMs += frameMs
            // Cap trailing padding at ~400ms: without this a sub-2s utterance
            // followed by long silence grows `voiced` unboundedly and never emits.
            let paddingBudget = max(0, 400 - (silenceMs - frameMs))
            if !voiced.isEmpty, paddingBudget > 0 {
                let keep = min(pcm.count, paddingBudget * 16)
                voiced.append(contentsOf: pcm.prefix(keep))
            }
        }
        let secs = Double(voiced.count) / 16000.0
        if !voiced.isEmpty && (secs >= config.maxChunkSec || (silenceMs >= 1500 && secs >= 2)) {
            let out = voiced; voiced = []; silenceMs = 0
            onChunk?(AudioChunk(stream: stream, pcm16kMono: out, meetingMs: chunkStartMs, sampleRate: 16000))
        }
    }

    func flush(stream: AudioStream, meetingMs: Int64) {
        lock.lock(); defer { lock.unlock() }
        guard !voiced.isEmpty else { return }
        let out = voiced; voiced = []
        onChunk?(AudioChunk(stream: stream, pcm16kMono: out, meetingMs: chunkStartMs, sampleRate: 16000))
    }
}
