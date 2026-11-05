import Foundation
import Combine

/// Owns both streams + VAD → Whisper → pipeline → SQLite.
/// Single start/stop, watchdog for silence.
///
/// Threading: MeetingStore (sqlite) is touched on MainActor only.
final class AudioCaptureManager: ObservableObject {
    @Published var state: AppState = .idle
    /// Raw chunks (debug UI). Persisted segments arrive via onSegment.
    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onSegment: (@Sendable (TranscriptSegment) -> Void)?

    private(set) var meetingId: UUID?
    private let clock = MeetingClock()
    private var mic: MicCapture?
    private var system: AnyObject?
    private var watchdog: Timer?
    private var janitor: Timer?

    // Pipeline pieces (created per meeting).
    private var store: MeetingStore?
    private var pipeline: TranscriptionPipeline?
    private var vadMic = VADChunker()
    private var vadSystem = VADChunker()
    private let whisper = WhisperKitEngine()
    var languageHint: LanguageHint = .mixed
    var retentionDays = 3
    var outputLanguage = "en"

    static func defaultDBPath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ReCatch.sqlite").path
    }

    @MainActor
    func startMeeting() async {
        state = .requestingPermissions
        clock.start()
        let mid = UUID()
        do {
            let st = try MeetingStore(path: Self.defaultDBPath())
            try? st.purgeExpired()
            let nowMs = clock.nowMs()
            let expires = RetentionJanitor.expiresAt(from: Date(), days: retentionDays)
            try st.createMeeting(id: mid, title: "Meeting", outputLanguage: outputLanguage,
                                 startedAt: nowMs, expiresAt: expires)
            janitor?.invalidate()
            janitor = RetentionJanitor.scheduleHourly(store: st)
            self.store = st
        } catch {
            state = .error("Store failed: \(error.localizedDescription)")
            clock.stop()
            return
        }
        let pipe = TranscriptionPipeline(meetingId: mid, hint: languageHint)
        await pipe.setOnSegment { [weak self] seg in
            Task { @MainActor [weak self] in
                guard let self, let st = self.store else { return }
                try? st.insertSegment(seg)
                self.onSegment?(seg)
            }
        }
        self.pipeline = pipe
        self.meetingId = mid
        vadMic = VADChunker()
        vadSystem = VADChunker()
        vadMic.onChunk = { [weak self] c in self?.handleVADChunk(c) }
        vadSystem.onChunk = { [weak self] c in self?.handleVADChunk(c) }

        let micCap = MicCapture(clock: clock)
        micCap.onChunk = { [weak self] c in
            self?.vadMic.feed(pcm: c.pcm16kMono, stream: .mic, meetingMs: c.meetingMs)
            Task { @MainActor in self?.onChunk?(c) }
        }
        do { try micCap.start() } catch { state = .error("Mic failed: \(error.localizedDescription)"); return }
        self.mic = micCap
        if #available(macOS 14.0, *) {
            let sys = SystemAudioCapture(clock: clock)
            sys.onChunk = { [weak self] c in
                self?.vadSystem.feed(pcm: c.pcm16kMono, stream: .system, meetingMs: c.meetingMs)
                Task { @MainActor in self?.onChunk?(c) }
            }
            sys.onError = { [weak self] e in Task { @MainActor in self?.state = .error("System audio: \(e.localizedDescription)") } }
            do { try await sys.start(displayID: nil) } catch { state = .error("System audio: \(error.localizedDescription)"); return }
            self.system = sys
        }
        state = .listening
        watchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in /* flag .noSignal if silent */ }
    }

    /// VAD chunk → Whisper → pipeline (drops empty transcripts, never persists hallucinations).
    private func handleVADChunk(_ chunk: AudioChunk) {
        let hint = languageHint
        Task {
            do {
                let (text, lang, _, conf) = try await whisper.transcribe(chunk.pcm16kMono, hint: hint)
                let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !t.isEmpty else { return }
                await pipeline?.ingest(chunk, text: t, lang: lang, confidence: conf)
            } catch {
                await MainActor.run { [weak self] in
                    if let e = self?.state, e == .listening { /* keep listening; ASR retry next chunk */ }
                }
            }
        }
    }

    /// Transcript window from SQLite — feeds Right now / Missed / Ask prompts.
    @MainActor
    func transcriptText(sinceMs: Int64 = 0) -> String {
        guard let mid = meetingId, let st = store else { return "" }
        return (try? st.transcriptText(meetingId: mid, sinceMs: sinceMs)) ?? ""
    }

    @MainActor
    func stopMeeting() async {
        vadMic.flush(stream: .mic, meetingMs: clock.nowMs())
        vadSystem.flush(stream: .system, meetingMs: clock.nowMs())
        watchdog?.invalidate(); watchdog = nil
        janitor?.invalidate(); janitor = nil
        mic?.stop(); mic = nil
        if #available(macOS 14.0, *), let sys = system as? SystemAudioCapture { await sys.stop() }
        system = nil
        if let mid = meetingId, let st = store { try? st.endMeeting(id: mid) }
        meetingId = nil
        store = nil
        pipeline = nil
        clock.stop()
        state = .idle
    }

    @MainActor
    func pause() { state = .paused }
    @MainActor
    func resume() { if state == .paused { state = .listening } }
}
