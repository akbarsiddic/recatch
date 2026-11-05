import Foundation

/// VAD-gated chunker: accumulates voiced PCM, emits 5–15s chunks. One instance per stream.
final class VADChunker {
    private let config: VADConfig
    private var voiced: [Int16] = []
    private var silenceMs = 0
    private var chunkStartMs: Int64 = 0
    var onChunk: ((AudioChunk, [Int16]) -> Void)?

    init(config: VADConfig = VADConfig()) { self.config = config }

    /// Feed 0.5s frames of 16k mono. Energy gate stands in for Silero until CoreML model ships.
    func feed(pcm: [Int16], stream: AudioStream, meetingMs: Int64) {
        let energy = pcm.reduce(0) { $0 + Int64($1) * Int64($1) } / Int64(max(1, pcm.count))
        let isVoiced = energy > 2_000_000 // ~tuned placeholder; Silero replaces this
        if voiced.isEmpty { chunkStartMs = meetingMs }
        if isVoiced {
            voiced.append(contentsOf: pcm)
            silenceMs = 0
        } else {
            silenceMs += 500
            if !voiced.isEmpty { voiced.append(contentsOf: pcm) } // 400ms padding
        }
        let secs = Double(voiced.count) / 16000.0
        if !voiced.isEmpty && (secs >= config.maxChunkSec || (silenceMs >= 1500 && secs >= 2)) {
            let out = voiced; voiced = []; silenceMs = 0
            onChunk?(AudioChunk(stream: stream, pcm16kMono: [], meetingMs: chunkStartMs, sampleRate: 16000), out)
        }
    }

    func flush(stream: AudioStream, meetingMs: Int64) {
        guard !voiced.isEmpty else { return }
        let out = voiced; voiced = []
        onChunk?(AudioChunk(stream: stream, pcm16kMono: [], meetingMs: chunkStartMs, sampleRate: 16000), out)
    }
}
