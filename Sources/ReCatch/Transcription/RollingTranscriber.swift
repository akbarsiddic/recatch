import Foundation

/// Rolling-window captions: keep the last few seconds of audio, re-transcribe it continuously,
/// and show the result as the live caption. This is StreamLingo's "live preview" — words appear
/// while people speak instead of after a 15-second VAD chunk.
///
/// The window is the source of truth. Earlier versions tried to stitch each pass onto the last
/// one, but Whisper rewords itself slightly between passes ("the information" → "information"),
/// so stitching produced sentences twice. Instead the window text *is* the line, and only the
/// already-emitted tail is stripped when the line is committed.
///
/// Two outputs:
///  - `onPartial(line)`: the current, still-changing caption (shown in the overlay).
///  - `onFinal(line)`: a settled utterance (persisted, used by catch-up answers).
final class RollingTranscriber {
    struct Config {
        /// How much audio each pass looks at. Longer = better context, slower.
        var windowSec: Double = 12.0
        /// Don't run until there's at least this much audio.
        var minAudioSec: Double = 1.0
        /// Silence after which the current utterance is committed.
        var silenceToFinalSec: Double = 1.2
        /// Meetings talk continuously — silence never comes, so commit at this length too.
        var maxLineWords: Int = 18
        /// Hard cap on one utterance's wall-clock length.
        var maxLineSeconds: Double = 22
        /// Minimum gap between passes, so we never spin the model.
        var minPassIntervalSec: Double = 0.9
        /// Absolute floor for the energy gate (mean square of Int16 samples).
        var energyGate: Double = 80_000
    }

    var config = Config()
    /// Injected ASR call: audio → text.
    var transcribe: (([Int16]) async -> String)?
    var onPartial: ((String) -> Void)?
    var onFinal: ((String, AudioStream) -> Void)?

    private var window: [Int16] = []
    /// Text of the most recent pass over `window`.
    private var windowText = ""
    /// Tail of the last committed line, so the next line doesn't repeat it.
    private var lastFinalWords: [String] = []
    private var silentMs = 0
    private var busy = false
    private var lastPassAt = Date.distantPast
    private var utteranceStartedAt = Date.distantPast
    private var label: AudioStream = .mic
    private var hasSpeech = false
    /// Slow-moving room tone. A fixed gate either misses soft speech or transcribes noise.
    private var noiseFloor: Double = 0

    /// Current caption line. Empty when nothing is being said.
    private(set) var currentLine = ""

    func feed(_ pcm: [Int16], label: AudioStream) {
        guard !pcm.isEmpty else { return }
        self.label = label
        window.append(contentsOf: pcm)
        let maxSamples = Int(config.windowSec * 16_000)
        if window.count > maxSamples {
            window.removeFirst(window.count - maxSamples)
        }
        let energy = Self.energy(pcm)
        let gate = max(config.energyGate, min(noiseFloor, 300_000) * 3)
        if energy > gate {
            hasSpeech = true
            silentMs = 0
        } else {
            silentMs += Int(Double(pcm.count) / 16.0)
        }
        // Learn room tone in both states: fast when quiet, barely while someone speaks.
        if noiseFloor == 0 {
            noiseFloor = energy
        } else if energy > gate {
            noiseFloor = noiseFloor * 0.998 + energy * 0.002
        } else {
            noiseFloor = noiseFloor * 0.9 + energy * 0.1
        }
    }

    /// Called a few times per second by the capture tick.
    func tick() async {
        guard !busy else { return }
        if silentMs >= Int(config.silenceToFinalSec * 1000), !windowText.isEmpty {
            finalize()
            return
        }
        let wordCount = windowText.split(separator: " ").count
        if wordCount >= config.maxLineWords
            || (!windowText.isEmpty && Date().timeIntervalSince(utteranceStartedAt) >= config.maxLineSeconds) {
            finalize()
            return
        }
        guard hasSpeech else { return }
        guard Double(window.count) / 16_000 >= config.minAudioSec else { return }
        guard Date().timeIntervalSince(lastPassAt) >= config.minPassIntervalSec else { return }

        busy = true
        lastPassAt = Date()
        let audio = window
        defer { busy = false }
        guard let transcribe else { return }
        let text = await transcribe(audio)
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        if windowText.isEmpty { utteranceStartedAt = Date() }
        windowText = cleaned
        currentLine = cleaned
        onPartial?(cleaned)
    }

    /// Force-commit whatever is buffered (stop listening, app quit).
    /// Waits for an in-flight pass first — otherwise the text it just produced is thrown away.
    func flush() async {
        var waited = 0
        while busy && waited < 60 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        if !windowText.isEmpty { finalize() }
        window.removeAll()
    }

    private func finalize() {
        let line = Self.stripOverlap(previous: lastFinalWords, from: windowText)
        windowText = ""
        window.removeAll()
        hasSpeech = false
        silentMs = 0
        currentLine = ""
        guard !line.isEmpty else { return }
        lastFinalWords = line.split(separator: " ").map(String.init)
        onFinal?(line, label)
    }

    // MARK: - Pure helpers

    /// Drop the words this line shares with the end of the previous one, so consecutive
    /// segments don't repeat each other. Case-insensitive; ignores punctuation-only tails.
    static func stripOverlap(previous: [String], from text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty, !previous.isEmpty else { return text }
        let maxK = min(15, previous.count, words.count)
        var overlap = 0
        if maxK > 0 {
            for k in stride(from: maxK, through: 1, by: -1) {
                let tail = previous.suffix(k).map { $0.lowercased() }
                let head = words.prefix(k).map { $0.lowercased() }
                if tail == head { overlap = k; break }
            }
        }
        guard overlap > 0, overlap < words.count else {
            // Entirely a repeat of what was already emitted.
            return overlap == words.count ? "" : text
        }
        return words.dropFirst(overlap).joined(separator: " ")
    }

    static func energy(_ pcm: [Int16]) -> Double {
        guard !pcm.isEmpty else { return 0 }
        var sum = 0.0
        for s in pcm { let v = Double(s); sum += v * v }
        return sum / Double(pcm.count)
    }
}
