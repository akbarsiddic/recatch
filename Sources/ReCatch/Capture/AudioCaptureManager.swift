import Foundation
import Combine

/// Owns capture → mix → rolling ASR → SQLite.
///
/// Shape borrowed from StreamLingo: one mixed stream, one recognizer, rolling captions.
/// The old design ran two VADs and two Whisper calls (mic + system) concurrently — which
/// deadlocked CoreML and meant nothing was ever transcribed.
final class AudioCaptureManager: ObservableObject {
    /// Menu-bar apps have exactly one capture owner; the app delegate wires it at launch.
    static let shared = AudioCaptureManager()

    @Published var state: AppState = .idle
    /// Live mic level 0...1 (decays on the watchdog tick).
    @Published var level: Double = 0
    /// Non-fatal note (e.g. "system audio off") — listening continues without it.
    @Published var systemNote: String?
    /// Rolling windows transcribed this meeting.
    @Published var chunkCount = 0
    /// Settled utterances persisted this meeting.
    @Published var segmentCount = 0
    @Published var lastHeardAt: Date?
    /// Model phase for menu/panel ("Model ready", "Downloading base — 42%", …).
    @Published var modelLine = "Model not loaded"
    @Published var heardLine = "Nothing heard yet"
    /// Speech-model readiness, surfaced by the dashboard (phase + real progress).
    @Published var modelPhase: TranscriptionPhase = .idle
    @Published var modelProgress: Double = 0
    /// Language detected once for this meeting ("Bahasa Indonesia"), nil while unknown.
    @Published var detectedLanguageTitle: String?

    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onSegment: (@Sendable (TranscriptSegment) -> Void)?
    /// Live partial caption (the overlay's headline).
    var onPartial: (@MainActor (String) -> Void)?

    private(set) var meetingId: UUID?
    private let clock = MeetingClock()
    private var mic: MicCapture?
    private var systemTap: AnyObject?
    private var systemSCK: AnyObject?
    private var watchdog: Timer?
    private var drainTimer: Timer?
    private var janitor: Timer?

    /// Language is decided once per meeting, then locked (see LanguageBox).
    private let languageBox = LanguageBox(.auto)
    /// Votes from the first paragraphs; see collectLanguageVote.
    private var languageVotes: [String: Int] = [:]
    private var didDetectLanguage = false

    private var store: MeetingStore?
    private let mixer = AudioMixer()
    private let rolling = RollingTranscriber()
    private let whisper = WhisperKitEngine()
    var languageHint: LanguageHint = .auto
    var retentionDays = 3
    var outputLanguage = "en"
    /// Quality tier for the speech model; set from settings before start.
    var quality: TranscriptionQuality = .fast
    /// Self-test only: skip live mic/tap so a fed file is the sole audio source.
    var suppressLiveSources = false

    private static let idlePrompt = "Listening — talk to test the mic…"

    static func defaultDBPath() -> String {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("ReCatch.sqlite").path
    }

    @MainActor
    func startMeeting() async {
        guard state != .listening else { return }
        state = .requestingPermissions

        // Mic is the only hard requirement. System audio is a best-effort upgrade —
        // blocking on it is what made this app look dead.
        if !PermissionsManager.micGranted() {
            guard await PermissionsManager.requestMic() else {
                state = .error("Mic denied — allow ReCatch in System Settings → Privacy → Microphone.")
                return
            }
        }
        clock.start()
        let mid = UUID()
        do {
            let st = try MeetingStore(path: Self.defaultDBPath())
            try? st.purgeExpired()
            // Epoch ms: the Meetings pane shows a real date. Segment offsets stay relative
            // to the meeting start, which is what the "last N seconds" window maths needs.
            let startedAt = Int64(Date().timeIntervalSince1970 * 1000)
            let expires = RetentionJanitor.expiresAt(from: Date(), days: retentionDays)
            try st.createMeeting(id: mid, title: "Meeting", outputLanguage: outputLanguage,
                                 startedAt: startedAt, expiresAt: expires)
            janitor?.invalidate()
            janitor = RetentionJanitor.scheduleHourly(store: st)
            self.store = st
        } catch {
            state = .error("Store failed: \(error.localizedDescription)")
            clock.stop()
            return
        }
        meetingId = mid

        // Rolling transcriber → partial captions + settled segments.
        rolling.config = .init()
        let box = languageBox
        // Start in whatever we learned last time; only a first-ever meeting begins unknown.
        let starting = AppSettings.shared.startingLanguage
        await box.set(starting.hint)
        languageVotes.removeAll()
        didDetectLanguage = starting != .auto
        detectedLanguageTitle = starting == .auto ? nil : starting.title
        rolling.transcribe = { [whisper, box] pcm in
            let hint = await box.get()
            let (text, lang, _, _) = (try? await whisper.transcribe(pcm, hint: hint)) ?? ("", "", 0, 0)
            return (text, lang)
        }
        rolling.onPartial = { [weak self] line in
            Task { @MainActor in
                self?.onPartial?(line)
                self?.heardLine = line.isEmpty ? "Listening…" : "Hearing you now"
            }
        }
        rolling.onFinal = { [weak self] line, stream in
            Task { @MainActor in self?.persist(line: line, stream: stream) }
        }
        rolling.onLanguage = { [weak self] lang in
            Task { @MainActor in self?.collectLanguageVote(lang) }
        }

        await whisper.configure(quality)

        if suppressLiveSources {
            state = .listening
            modelLine = "Preparing \(quality.title.lowercased()) model…"
            Task { await whisper.load() }
            startTimers()
            return
        }

        let micCap = MicCapture(clock: clock)
        micCap.onChunk = { [weak self] c in
            guard let self else { return }
            self.mixer.feed(c.pcm16kMono, stream: .mic)
            Task { @MainActor in self.level = PCM.rms(c.pcm16kMono) }
        }
        do { try micCap.start() } catch { state = .error("Mic failed: \(error.localizedDescription)"); return }
        self.mic = micCap

        systemNote = nil
        startSystemAudio()

        state = .listening
        level = 0; chunkCount = 0; segmentCount = 0; lastHeardAt = nil
        heardLine = Self.idlePrompt
        modelLine = "Preparing \(quality.title.lowercased()) model…"
        Task { await whisper.load() }

        startTimers()
    }

    /// Drain (200 ms) keeps captions flowing; the transcriber decides when to run ASR.
    @MainActor
    private func startTimers() {
        drainTimer?.invalidate()
        let dt = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.drainTick() }
        }
        RunLoop.main.add(dt, forMode: .common)
        drainTimer = dt

        watchdog?.invalidate()
        let wd = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(wd, forMode: .common)
        watchdog = wd
    }

    /// Core Audio tap first (Audio Recording only), ScreenCaptureKit as fallback (Screen Recording).
    @MainActor
    private func startSystemAudio() {
        guard #available(macOS 14.2, *) else {
            systemNote = "System audio needs macOS 14.2+ — mic only."
            return
        }
        let tap = SystemAudioTap(clock: clock)
        tap.onChunk = { [weak self] c in
            guard let self else { return }
            self.mixer.feed(c.pcm16kMono, stream: .system)
            Task { @MainActor in self.onChunk?(c) }
        }
        tap.onError = { [weak self] e in
            Task { @MainActor in self?.systemNote = "System audio stopped: \(e.localizedDescription)" }
        }
        do {
            try tap.start()
            systemTap = tap
            PermissionsManager.confirmAudioRecording()
            return
        } catch {
            Debug.log("tap failed: \(error.localizedDescription) — falling back to ScreenCaptureKit")
            systemNote = "System audio off. \(error.localizedDescription)"
        }

        if #available(macOS 14.0, *), PermissionsManager.screenGranted() {
            let sck = SystemAudioCapture(clock: clock)
            sck.onChunk = { [weak self] c in
                guard let self else { return }
                self.mixer.feed(c.pcm16kMono, stream: .system)
                Task { @MainActor in self.onChunk?(c) }
            }
            sck.onError = { [weak self] e in
                Task { @MainActor in self?.systemNote = "System audio stopped: \(e.localizedDescription)" }
            }
            Task { @MainActor in
                do {
                    try await sck.start(displayID: nil)
                    self.systemSCK = sck
                    self.systemNote = nil
                } catch {
                    self.systemNote = "System audio unavailable — mic only."
                }
            }
        } else if #available(macOS 14.0, *) {
            _ = PermissionsManager.requestScreen()
        }
    }

    @MainActor
    private func drainTick() async {
        guard state == .listening else { return }
        guard let mixed = mixer.drain(maxSamples: 16_000 / 5) else { return }
        rolling.feed(mixed.pcm, label: mixed.label)
        await rolling.tick()
        if rolling.currentLine.isEmpty == false { chunkCount += 1 }
    }

    /// Decide the meeting language from the first few paragraphs, then remember it.
    ///
    /// No extra inference: every rolling pass already reports the language it decoded, so the
    /// vote is free. (A dedicated detection pass doubled GPU work and, with the turbo encoder,
    /// was enough to crash MetalPerformanceShadersGraph.)
    @MainActor
    private func collectLanguageVote(_ lang: String) {
        guard AppSettings.shared.spokenLanguage == .auto, !didDetectLanguage else { return }
        guard !lang.isEmpty else { return }
        languageVotes[lang, default: 0] += 1
        guard segmentCount >= 3 else { return }
        let winner = languageVotes.max { $0.value < $1.value }
        guard let code = winner?.key, winner!.value >= 2 else { return }
        didDetectLanguage = true
        let language = SpokenLanguage.allCases.first { $0.code == code } ?? .auto
        guard language != .auto else { return }
        detectedLanguageTitle = language.title
        AppSettings.shared.learnedLanguage = language
        Task { await languageBox.set(language.hint) }
        Debug.log("language learned from \(languageVotes): \(code) (\(language.title))")
    }

    /// One-click override from the dashboard or the overlay: applies now and is remembered.
    @MainActor
    func applyLanguage(_ language: SpokenLanguage) {
        AppSettings.shared.spokenLanguage = language
        if language != .auto { AppSettings.shared.learnedLanguage = language }
        detectedLanguageTitle = language == .auto ? nil : language.title
        didDetectLanguage = language != .auto
        languageVotes.removeAll()
        Task { await languageBox.set(language.hint) }
        Debug.log("language set by hand: \(language.rawValue)")
    }

    /// Load the speech model without starting a meeting (onboarding, pre-warm).
    @MainActor
    func prepareModel() async {
        await whisper.configure(quality)
        await whisper.load()
        await refreshModelState()
    }

    @MainActor
    private func refreshModelState() async {
        modelPhase = await whisper.phase
        modelProgress = await whisper.progress
        modelLine = await whisper.statusLine
    }

    /// Settled utterance → SQLite + feed.
    @MainActor
    private func persist(line: String, stream: AudioStream) {
        guard let mid = meetingId, let st = store else { return }
        let seg = TranscriptSegment(
            id: UUID(), meetingId: mid,
            tStartMs: clock.nowMs(), tEndMs: clock.nowMs(),
            stream: stream, lang: "auto", langProb: 1.0,
            text: line, confidence: 1.0)
        do { try st.insertSegment(seg) }
        catch { Debug.log("store insert failed: \(error.localizedDescription)") }
        segmentCount += 1
        lastHeardAt = Date()
        onSegment?(seg)
    }

    /// 1s tick: decay the meter, refresh model phase (drives menu/panel).
    @MainActor
    private func tick() {
        level = max(0, level * 0.6)
        Task { [weak self] in
            guard let self else { return }
            let phase = await self.whisper.phase
            let progress = await self.whisper.progress
            let line = await self.whisper.statusLine
            await MainActor.run { [weak self] in
                self?.modelPhase = phase
                self?.modelProgress = progress
                self?.modelLine = line
            }
        }
        if segmentCount == 0 {
            heardLine = rolling.currentLine.isEmpty ? Self.idlePrompt : rolling.currentLine
        } else if let last = lastHeardAt {
            let ago = max(0, Int(Date().timeIntervalSince(last)))
            heardLine = ago < 3 ? "\(segmentCount) segments · hearing you now" : "\(segmentCount) segments · last heard \(ago)s ago"
        }
    }

    /// Engine phase for the panel (no string-sniffing). Actor hop.
    func enginePhase() async -> TranscriptionPhase { await whisper.phase }

    /// Retry a failed/damaged model download.
    @MainActor
    func retryModel() {
        Task {
            await whisper.retry()
            await whisper.load()
            await refreshModelState()
        }
    }

    @MainActor
    func transcriptText(sinceMs: Int64 = 0) -> String {
        guard let mid = meetingId, let st = store else { return "" }
        return (try? st.transcriptText(meetingId: mid, sinceMs: sinceMs)) ?? ""
    }

    @MainActor
    func transcriptWindow(secondsBack: Int) -> String {
        guard meetingId != nil else { return "" }
        if secondsBack <= 0 { return transcriptText() }
        let since = max(0, clock.nowMs() - Int64(secondsBack) * 1000)
        return transcriptText(sinceMs: since)
    }

    @MainActor
    func logLLM(provider: String, model: String, tokensIn: Int, tokensOut: Int, windowSec: Int) {
        try? store?.logLLM(provider: provider, model: model, tokensIn: tokensIn, tokensOut: tokensOut, windowSec: windowSec)
    }

    @MainActor
    func llmLog(limit: Int = 50) -> [MeetingStore.LLMLogEntry] {
        (try? store?.fetchLLMLog(limit: limit)) ?? []
    }

    /// Test hook: push PCM through the same mix → rolling → store path the microphone uses.
    @MainActor
    func simulateSpeech(_ pcm: [Int16]) async {
        // Let the model finish loading first, like a real meeting would.
        var waited = 0
        while await whisper.phase != .ready && waited < 200 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            waited += 1
        }
        mixer.feed(pcm, stream: .mic)
        // Drain at real time (100 ms of audio per 100 ms) so passes behave like live capture.
        var iterations = 0
        while iterations < 2000 {
            guard let mixed = mixer.drain(maxSamples: 1600) else { break }
            rolling.feed(mixed.pcm, label: mixed.label)
            await rolling.tick()
            iterations += 1
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        await rolling.flush()
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    @MainActor
    func stopMeeting() async {
        drainTimer?.invalidate(); drainTimer = nil
        watchdog?.invalidate(); watchdog = nil
        janitor?.invalidate(); janitor = nil
        await rolling.flush()
        mic?.stop(); mic = nil
        if #available(macOS 14.2, *), let tap = systemTap as? SystemAudioTap { tap.stop() }
        if #available(macOS 14.0, *), let sck = systemSCK as? SystemAudioCapture {
            Task { await sck.stop() }
        }
        systemTap = nil; systemSCK = nil
        mixer.reset()
        if let mid = meetingId, let st = store { try? st.endMeeting(id: mid) }
        meetingId = nil
        store = nil
        clock.stop()
        state = .idle
    }

    @MainActor
    func pause() { state = .paused }
    @MainActor
    func resume() { if state == .paused { state = .listening } }
}
