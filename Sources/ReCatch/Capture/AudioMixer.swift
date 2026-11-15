import Foundation

/// Mixes microphone and system audio into one 16 kHz mono stream before ASR.
///
/// Two streams meant two VADs, two inference queues and doubled load — and Whisper is not
/// reentrant, so the second call used to deadlock the first. StreamLingo mixes first
/// (`SynchronizedAudioMixer`) and transcribes once.
///
/// The label survives the mix: whichever side carried the energy is credited, so the transcript
/// can still say "Me" vs "Others".
final class AudioMixer: @unchecked Sendable {
    private let lock = NSLock()
    private var mic: [Int16] = []
    private var system: [Int16] = []
    private var micPeak: Double = 0
    private var systemPeak: Double = 0

    /// Cap per source so one stalled side can't grow without bound.
    private let maxBuffered = 16_000 * 30

    func feed(_ pcm: [Int16], stream: AudioStream) {
        lock.lock(); defer { lock.unlock() }
        let energy = RollingTranscriber.energy(pcm)
        switch stream {
        case .mic:
            mic.append(contentsOf: pcm)
            micPeak = max(micPeak, energy)
            if mic.count > maxBuffered { mic.removeFirst(mic.count - maxBuffered) }
        case .system:
            system.append(contentsOf: pcm)
            systemPeak = max(systemPeak, energy)
            if system.count > maxBuffered { system.removeFirst(system.count - maxBuffered) }
        }
    }

    struct Mixed {
        var pcm: [Int16]
        var label: AudioStream
    }

    /// Drain up to `maxSamples` of mixed audio. Silence on one side is fine — we take the longer
    /// buffer as the frame and pad the other, so a dropped source never desyncs the timeline.
    func drain(maxSamples: Int) -> Mixed? {
        lock.lock(); defer { lock.unlock() }
        let available = max(mic.count, system.count)
        guard available > 0 else { return nil }
        let count = min(available, maxSamples)

        var out = [Int16](repeating: 0, count: count)
        for i in 0..<count {
            let a = i < mic.count ? Int32(mic[i]) : 0
            let b = i < system.count ? Int32(system[i]) : 0
            // Sum, then soft-clamp. Both sides rarely speak at once; when they do, this keeps
            // both audible instead of dropping one.
            let sum = a + b
            out[i] = Int16(max(-32768, min(32767, sum)))
        }
        if mic.count >= count { mic.removeFirst(count) } else { mic.removeAll() }
        if system.count >= count { system.removeFirst(count) } else { system.removeAll() }

        // Credit whoever was louder in this window.
        let label: AudioStream
        let micE = micPeak, sysE = systemPeak
        micPeak = 0; systemPeak = 0
        if micE == 0 && sysE == 0 { label = .mic }
        else if sysE > micE * 2 { label = .system }
        else { label = .mic }

        return Mixed(pcm: out, label: label)
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        mic.removeAll(); system.removeAll()
        micPeak = 0; systemPeak = 0
    }
}
