import Foundation
import Combine

/// Owns both streams + VAD → Whisper → pipeline → SQLite.
/// Single start/stop, watchdog for silence.
///
/// Threading: MeetingStore (sqlite) is touched on MainActor only.
final class AudioCaptureManager: ObservableObject {
    @Published var state: AppState = .idle
    /// Live mic level 0...1 (decays on the watchdog tick). If this never moves, the mic is the problem.
    @Published var level: Double = 0
    /// Chunks the VAD emitted this meeting (capture is flowing).
    @Published var chunkCount = 0
    /// Transcribed segments persisted this meeting.
    @Published var segmentCount = 0
    /// When the last segment landed.
    @Published var lastHeardAt: Date?
    /// Whisper phase for the menu/panel ("Model ready", "Downloading model…", …).
    @Published var modelLine = "Model not loaded"
    /// “12 segments · last heard 4s ago” — refreshed on the watchdog tick.
    @Published var heardLine = "Nothing heard yet"
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

    /// Shared initial prompt line (reset + watchdog agree).
    private static let idlePrompt = "Listening — talk to test the mic…"

    static func defaultDBPath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ReCatch.sqlite").path
    }

    @MainActor
    func startMeeting() async {
        state = .requestingPermissions
        // Preflight: mic prompt inline; Screen Recording needs grant + relaunch.
        if !PermissionsManager.micGranted() {
            guard await PermissionsManager.requestMic() else {
                state = .error("Mic denied — allow in System Settings → Privacy → Microphone.")
                return
            }
        }
        if !PermissionsManager.screenGranted() {
            _ = PermissionsManager.requestScreen()
            state = .error("Grant Screen Recording, then relaunch ReCatch. Mic-only until then is not started.")
            return
        }
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
                self.segmentCount += 1
                self.lastHeardAt = Date()
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
            Task { @MainActor in
                self?.level = PCM.rms(c.pcm16kMono)
                self?.onChunk?(c)
            }
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
        level = 0; chunkCount = 0; segmentCount = 0; lastHeardAt = nil
        heardLine = Self.idlePrompt
        // Preload the model now: waiting for the first VAD chunk would leave
        // "Model not loaded" on screen for a quiet mic indefinitely.
        modelLine = "Loading model…"
        Task { await whisper.load() }
        watchdog = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    /// 1s tick: decay the meter, refresh model phase + heard line (drives menu/panel).
    @MainActor
    private func tick() {
        level = max(0, level * 0.6)
        Task { [weak self] in
            guard let self else { return }
            let line = await self.whisper.statusLine
            await MainActor.run { [weak self] in self?.modelLine = line }
        }
        if segmentCount == 0 {
            heardLine = chunkCount == 0 ? Self.idlePrompt : "Hearing sound, waiting on first transcript…"
        } else if let last = lastHeardAt {
            let ago = max(0, Int(Date().timeIntervalSince(last)))
            heardLine = ago < 3 ? "\(segmentCount) segments · hearing you now" : "\(segmentCount) segments · last heard \(ago)s ago"
        }
    }

    /// Engine phase for the panel (no string-sniffing). Actor hop.
    func enginePhase() async -> TranscriptionPhase { await whisper.phase }

    /// VAD chunk → Whisper → pipeline (drops empty transcripts, never persists hallucinations).
    private func handleVADChunk(_ chunk: AudioChunk) {
        Task { @MainActor in self.chunkCount += 1 }
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

    /// Windowed variant: secondsBack == 0 means the whole meeting.
    @MainActor
    func transcriptWindow(secondsBack: Int) -> String {
        guard meetingId != nil else { return "" }
        if secondsBack <= 0 { return transcriptText() }
        let since = max(0, clock.nowMs() - Int64(secondsBack) * 1000)
        return transcriptText(sinceMs: since)
    }

    /// Persist timestamp + size to llm_log (never content).
    @MainActor
    func logLLM(provider: String, model: String, tokensIn: Int, tokensOut: Int, windowSec: Int) {
        try? store?.logLLM(provider: provider, model: model, tokensIn: tokensIn, tokensOut: tokensOut, windowSec: windowSec)
    }

    @MainActor
    func llmLog(limit: Int = 50) -> [MeetingStore.LLMLogEntry] {
        (try? store?.fetchLLMLog(limit: limit)) ?? []
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
