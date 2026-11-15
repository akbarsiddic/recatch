import Foundation

/// VAD-gated chunker: accumulates voiced PCM, emits 5–15s chunks. One instance per stream.
final class VADChunker: @unchecked Sendable {
    private let lock = NSLock()
    private let config: VADConfig
    private var voiced: [Int16] = []
    private var silenceMs = 0
    private var chunkStartMs: Int64 = 0
    /// Slow-moving room tone. A fixed threshold either misses soft speech or fires on noise;
    /// this adapts per machine, per room, per mic.
    private var noiseFloor: Double = 0
    var onChunk: (@Sendable (AudioChunk) -> Void)?

    init(config: VADConfig = VADConfig()) { self.config = config }

    /// Feed 16k mono frames of any length. Energy gate stands in for Silero until CoreML model ships.
    /// Duration is derived from the sample count (16 samples = 1 ms), not assumed.
    func feed(pcm: [Int16], stream: AudioStream, meetingMs: Int64) {
        lock.lock(); defer { lock.unlock() }
        let frameMs = pcm.isEmpty ? 0 : pcm.count / 16
        let energy: Double = pcm.isEmpty ? 0 : pcm.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(pcm.count)
        // Gate = 3x room tone, clamped: never below ~0.009 RMS (dead quiet room),
        // never above ~0.037 RMS (loud room would otherwise go deaf). Silero replaces this later.
        let floor = min(max(noiseFloor, 26_666), 400_000)
        let isVoiced = energy > max(80_000.0, floor * 3)
        // Track room tone in both states, faster when quiet — otherwise a noisy room
        // that starts above the initial gate stays "voiced" forever and the floor never learns.
        if noiseFloor == 0 {
            noiseFloor = energy
        } else if isVoiced {
            noiseFloor = noiseFloor * 0.995 + energy * 0.005
        } else {
            noiseFloor = noiseFloor * 0.9 + energy * 0.1
        }
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
