import Foundation
import AVFoundation
import AppKit
import SwiftUI

/// Headless end-to-end probe: audio → VAD → Whisper → stdout. No UI, no clicks.
///
/// Modes
///  - `RECATCH_SELFTEST_AUDIO=/path/file.wav` — deterministic: file → VAD → ASR (no mic, no TCC).
///  - otherwise mic is recorded live for `RECATCH_SELFTEST_SECS` (default 12).
///
/// Run: RECATCH_SELFTEST=1 .build/debug/ReCatch
enum SelfTest {
    static func runIfRequested() {
        guard ProcessInfo.processInfo.environment["RECATCH_SELFTEST"] == "1" else { return }
        let env = ProcessInfo.processInfo.environment
        // Test-time language overrides, so a Bahasa meeting can be probed without touching Settings.
        if let spoken = env["RECATCH_SPOKEN"], !spoken.isEmpty {
            UserDefaults.standard.set(spoken, forKey: "recatch.spokenLanguage")
        }
        if let quality = env["RECATCH_QUALITY"], !quality.isEmpty {
            UserDefaults.standard.set(quality, forKey: "recatch.transcriptionQuality")
        }
        let secs = Double(env["RECATCH_SELFTEST_SECS"] ?? "12") ?? 12
        // Never block the main thread: MainActor work (wiring, capture, panel) needs it to run.
        Task.detached {
            if let live = env["RECATCH_SELFTEST_LIVE"], let secs = Double(live) {
                await runLive(seconds: secs)
            } else if env["RECATCH_SELFTEST_APP"] == "1" {
                await runApp(env["RECATCH_SELFTEST_AUDIO"] ?? "/tmp/speech.wav")
            } else if env["RECATCH_SELFTEST_SHOTS"] == "1" {
                await runShots()
            } else if env["RECATCH_SELFTEST_UI"] == "1" {
                await runUI()
            } else if env["RECATCH_SELFTEST_LLM"] == "1" {
                await runLLM()
                if (env["RECATCH_SELFTEST_AUDIO"] ?? "").isEmpty { exit(0) }
            } else if let path = env["RECATCH_SELFTEST_AUDIO"], !path.isEmpty {
                await runFile(path)
            } else {
                await runMic(seconds: secs)
            }
            exit(0)
        }
    }

    // MARK: - Live probe (real capture: system audio tap / mic → ASR → SQLite → panel)

    /// Starts a real meeting (no simulated audio), waits while something plays, then asks the panel.
    /// This is the closest thing to "join a meeting and watch it work".
    /// Proves the shell bugs are fixed: the window really opens, really activates,
    /// really is key, and every pane renders without crashing.
    @MainActor
    private static func runUI() async {
        log("ui: opening dashboard")
        DashboardWindowController.shared.show()
        try? await Task.sleep(nanoseconds: 1_500_000_000)

        let policy = NSApp.activationPolicy() == .regular ? "regular (dock icon)" : "accessory (menu bar only)"
        log("ui: activation policy \(policy), app active=\(NSApp.isActive)")

        let windows = NSApp.windows.filter { $0.isVisible }
        log("ui: \(windows.count) visible window(s)")
        for w in windows {
            let f = w.frame
            log("ui:   '\(w.title)' \(Int(f.width))x\(Int(f.height)) key=\(w.isKeyWindow) onscreen=\(w.isOnActiveSpace)")
        }
        guard let main = windows.first(where: { $0.title == Brand.name }) else {
            log("ui: FAIL — dashboard window not visible")
            exit(1)
        }
        // First run legitimately puts the onboarding sheet in front, and it takes key.
        let sheet = windows.first { $0 !== main && $0.isKeyWindow }
        if main.isKeyWindow {
            log("ui: dashboard holds key")
        } else if let sheet {
            log("ui: onboarding sheet \(Int(sheet.frame.width))x\(Int(sheet.frame.height)) holds key (expected on first run)")
        } else {
            log("ui: FAIL — neither the dashboard nor a sheet is key (the old Settings bug)")
            exit(1)
        }

        // Every pane must build. A SwiftUI crash here would take the app down.
        for pane in DashboardView.Pane.allCases {
            let host = NSHostingView(rootView: DashboardView())
            host.frame = NSRect(x: 0, y: 0, width: 1000, height: 680)
            host.layoutSubtreeIfNeeded()
            log("ui: pane \(pane.rawValue) rendered (\(Int(host.fittingSize.width))x\(Int(host.fittingSize.height)))")
        }

        log("ui: OK — window opens, activates, and holds key")
        exit(0)
    }

    /// Capture the real window, pane by pane, so styling can be checked without a
    /// Screen Recording grant (which this harness does not have).
    @MainActor
    private static func runShots() async {
        DashboardWindowController.shared.show()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard let window = NSApp.windows.first(where: { $0.title == Brand.name }),
              let view = window.contentView else {
            log("shots: FAIL — no dashboard window")
            exit(1)
        }
        for pane in DashboardView.Pane.allCases {
            DashboardRouter.shared.pane = pane
            try? await Task.sleep(nanoseconds: 700_000_000)
            view.layoutSubtreeIfNeeded()
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            let path = "/tmp/pane-\(pane.rawValue).png"
            try? png.write(to: URL(fileURLWithPath: path))
            log("shots: \(path) \(rep.pixelsWide)x\(rep.pixelsHigh)")
        }
        // Onboarding sheet, rendered on its own.
        if let img = ImageRenderer(content: OnboardingView(isPresented: .constant(true))
            .frame(width: 620, height: 560)).nsImage,
           let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: "/tmp/pane-onboarding.png"))
            log("shots: /tmp/pane-onboarding.png")
        }
        exit(0)
    }

    private static func runLive(seconds: Double) async {
        await MainActor.run { AppWiring.start() }
        let capture = AudioCaptureManager.shared
        await capture.startMeeting()
        log("live: listening for \(Int(seconds))s — play audio now")
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))

        let segs = await MainActor.run { capture.segmentCount }
        let transcript = await MainActor.run { capture.transcriptWindow(secondsBack: 0) }
        log("live: \(segs) segments")
        log("live transcript:\n\(transcript.isEmpty ? "<empty>" : transcript)")

        let panel = await MainActor.run { PanelSession.shared }
        for (mode, label) in [(PanelMode.now, "RIGHT NOW"), (PanelMode.missed, "WHAT DID I MISS")] {
            await MainActor.run { panel.mode = mode; panel.result = ""; panel.run() }
            var waited = 0
            for _ in 0..<60 {
                let busy = await MainActor.run { panel.isLoading }
                if !busy { break }
                try? await Task.sleep(nanoseconds: 500_000_000)
                waited += 1
            }
            _ = waited
            let answer = await MainActor.run { panel.result }
            let err = await MainActor.run { panel.errorMessage ?? panel.emptyReason }
            log("\(label): \(answer.isEmpty ? "<empty> (\(err ?? "no reason"))" : answer)")
        }
        await capture.stopMeeting()
    }

    // MARK: - Whole-app probe (proves the real wiring: capture → ASR → SQLite → panel)

    /// Boots the app's own objects, starts a meeting, pushes a speech file through the
    /// same path the microphone uses, then asks the panel. No meeting, no clicks.
    private static func runApp(_ audioPath: String) async {
        await MainActor.run { AppWiring.start() }
        let capture = AudioCaptureManager.shared
        await MainActor.run { capture.suppressLiveSources = true }
        await capture.startMeeting()
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        let listening = await MainActor.run { capture.state == .listening }
        log("meeting started: \(listening) (state=\(await MainActor.run { "\(capture.state)" }))")
        if !listening { log("FAIL: startMeeting did not reach .listening") }

        guard let pcm = load16kMono(audioPath) else { log("FAIL: cannot read \(audioPath)"); return }
        log("feeding \(String(format: "%.1f", Double(pcm.count) / 16000))s of speech through the capture path")
        await capture.simulateSpeech(pcm)
        let chunks = await MainActor.run { capture.chunkCount }
        log("caption updates: \(chunks)")

        for _ in 0..<80 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let n = await MainActor.run { capture.segmentCount }
            if n > 0 { break }
        }
        log("model line: \(await MainActor.run { capture.modelLine })")
        let segs = await MainActor.run { capture.segmentCount }
        log("segments stored: \(segs)")
        let transcript = await MainActor.run { capture.transcriptWindow(secondsBack: 0) }
        log("transcript from SQLite: \(transcript.isEmpty ? "<empty>" : transcript)")

        let panel = await MainActor.run { PanelSession.shared }
        await MainActor.run { panel.mode = .now; panel.run() }
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let doneNow = await MainActor.run { !panel.isLoading && !panel.result.isEmpty }
            if doneNow { break }
        }
        let answer = await MainActor.run { panel.result }
        let err = await MainActor.run { panel.errorMessage }
        let empty = await MainActor.run { panel.emptyReason }
        log("panel answer: \(answer.isEmpty ? "<empty>" : answer)")
        if let err { log("panel error: \(err)") }
        if !empty.isEmpty { log("panel empty reason: \(empty)") }
        await capture.stopMeeting()
    }

    // MARK: - Provider probe (proves the answer path, no meeting needed)

    /// Exercises the exact code the panel uses: prompt → gateway → streamed tokens.
    private static func runLLM() async {
        let settings = AppSettings.shared
        let ready = ProviderCatalog.all
            .filter { ProviderCatalog.readiness($0.provider, baseURLOverride: settings.baseURL(for: $0.provider)).isUsable }
            .map(\.name)
        log("providers ready: \(ready.joined(separator: ", "))")
        guard let g = settings.gatewayFor(.rightNow) else {
            log("FAIL: no provider ready — \(settings.missingKeyHint ?? "unknown")")
            return
        }
        let opts = settings.options(for: .rightNow, verbose: false)
        log("using \(ProviderCatalog.displayName(g.provider)) / \(g.model)")
        let transcript = [
            "[0:12] Rina: Oke, kita mulai. Staging API-nya udah deploy belum?",
            "[0:18] Akbar: Belum, migration-nya masih gagal di index. Aku fix hari ini.",
            "[0:31] Rina: Kalau gagal lagi, kita rollback aja. Deadline Jumat ya.",
            "[0:44] Akbar: Siap, aku update di channel.",
        ].joined(separator: "\n")
        let prompt = Prompts.rightNow(transcript: transcript, outputLanguage: opts.outputLanguage)
        let started = Date()
        do {
            var out = ""
            for try await t in g.gateway.stream(prompt: prompt, options: opts) {
                if out.isEmpty { log("first token after \(Int(Date().timeIntervalSince(started) * 1000)) ms") }
                out += t
            }
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            log("answer (\(ms) ms total): \(out.isEmpty ? "<empty>" : out)")
            if out.isEmpty { log("FAIL: provider returned nothing") }
        } catch {
            log("FAIL: \(error.localizedDescription)")
        }
    }

    // MARK: - Deterministic file probe (proves VAD + ASR without hardware)

    private static func runFile(_ path: String) async {
        guard let pcm = load16kMono(path) else {
            log("FAIL: cannot read audio at \(path)")
            return
        }
        log("file \(path): \(String(format: "%.1f", Double(pcm.count) / 16000))s of 16 kHz mono")
        let stats = Stats()
        let vad = VADChunker()
        let box = ChunkBox()
        vad.onChunk = { c in box.append(c); log("VAD chunk #\(box.count): \(String(format: "%.1f", Double(c.pcm16kMono.count) / 16000))s") }

        // Feed in 100 ms buffers, like the capture tap does.
        var i = 0
        while i < pcm.count {
            let end = min(i + 1600, pcm.count)
            let slice = Array(pcm[i..<end])
            stats.observe(slice)
            vad.feed(pcm: slice, stream: .mic, meetingMs: Int64(i / 16))
            i = end
        }
        vad.flush(stream: .mic, meetingMs: Int64(pcm.count / 16))
        log("buffers=\(stats.buffers) voiced=\(stats.voiced) peakRMS=\(String(format: "%.3f", stats.peak)) chunks=\(box.count)")

        let whisper = WhisperKitEngine()
        await whisper.load()
        log("model: \(await whisper.statusLine)")
        for (n, c) in box.snapshot().enumerated() {
            do {
                let (text, lang, _, conf) = try await whisper.transcribe(c.pcm16kMono, hint: .mixed)
                log("ASR[\(n)] lang=\(lang) conf=\(String(format: "%.2f", conf)) → \(text.isEmpty ? "<empty>" : text)")
            } catch {
                log("ASR[\(n)] FAIL → \(error.localizedDescription)")
            }
        }
        if box.count == 0 { log("FAIL: VAD emitted no chunks") }
    }

    private static func load16kMono(_ path: String) -> [Int16]? {
        guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return nil }
        let src = file.processingFormat
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: src, to: target) else { return nil }
        let capacity = AVAudioFrameCount(file.length)
        guard let inBuf = AVAudioPCMBuffer(pcmFormat: src, frameCapacity: capacity) else { return nil }
        try? file.read(into: inBuf)
        let outFrames = AVAudioFrameCount(Double(inBuf.frameLength) * 16000.0 / src.sampleRate)
        guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else { return nil }
        var err: NSError?
        var handedOff = false
        converter.convert(to: out, error: &err) { _, status in
            if handedOff { status.pointee = .noDataNow; return nil }
            handedOff = true
            status.pointee = .haveData
            return inBuf
        }
        guard err == nil, let ch = out.floatChannelData?[0] else { return nil }
        return (0..<Int(out.frameLength)).map { Int16(max(-1, min(1, ch[$0])) * 32767) }
    }

    // MARK: - Live mic probe

    private static func runMic(seconds: Double) async {
        log("mic auth = \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue) (3 = authorized)")
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            let ok = await AVCaptureDevice.requestAccess(for: .audio)
            log("mic prompt → \(ok)")
        }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            log("FAIL: mic not authorized — nothing downstream can work")
            return
        }
        let clock = MeetingClock()
        clock.start()
        let stats = Stats()
        let vad = VADChunker()
        let box = ChunkBox()
        vad.onChunk = { c in box.append(c); log("VAD chunk #\(box.count): \(String(format: "%.1f", Double(c.pcm16kMono.count) / 16000))s") }

        let mic = MicCapture(clock: clock)
        mic.onChunk = { chunk in
            stats.observe(chunk.pcm16kMono)
            vad.feed(pcm: chunk.pcm16kMono, stream: .mic, meetingMs: chunk.meetingMs)
        }
        do { try mic.start() } catch { log("FAIL: mic start → \(error.localizedDescription)"); return }
        log("mic recording \(Int(seconds))s…")
        Task { await whisperShared.load() }
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        vad.flush(stream: .mic, meetingMs: clock.nowMs())
        mic.stop()
        log("buffers=\(stats.buffers) voiced=\(stats.voiced) peakRMS=\(String(format: "%.3f", stats.peak)) chunks=\(box.count)")
        log("model: \(await whisperShared.statusLine)")
        for (n, c) in box.snapshot().enumerated() {
            let (text, lang, _, conf) = (try? await whisperShared.transcribe(c.pcm16kMono, hint: .mixed)) ?? ("", "", 0, 0)
            log("ASR[\(n)] lang=\(lang) conf=\(String(format: "%.2f", conf)) → \(text.isEmpty ? "<empty>" : text)")
        }
        if box.count == 0 { log("FAIL: VAD emitted nothing — energy gate never tripped or mic silent") }
    }

    private static let whisperShared = WhisperKitEngine()

    // MARK: - helpers

    private static func log(_ s: String) {
        FileHandle.standardError.write(("[selftest] " + s + "\n").data(using: .utf8)!)
    }

    private final class ChunkBox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [AudioChunk] = []
        var count: Int { lock.lock(); defer { lock.unlock() }; return items.count }
        func append(_ c: AudioChunk) { lock.lock(); items.append(c); lock.unlock() }
        func snapshot() -> [AudioChunk] { lock.lock(); defer { lock.unlock() }; return items }
    }

    /// Same numbers the VAD uses, so "why no chunk" is answerable.
    private final class Stats: @unchecked Sendable {
        private let lock = NSLock()
        private var _buffers = 0, _voiced = 0
        private var _peak: Double = 0
        var buffers: Int { lock.lock(); defer { lock.unlock() }; return _buffers }
        var voiced: Int { lock.lock(); defer { lock.unlock() }; return _voiced }
        var peak: Double { lock.lock(); defer { lock.unlock() }; return _peak }
        func observe(_ pcm: [Int16]) {
            let rms = PCM.rms(pcm)
            let energy = pcm.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(1, pcm.count))
            lock.lock()
            _buffers += 1
            _peak = max(_peak, rms)
            if energy > 800_000 { _voiced += 1 }
            lock.unlock()
        }
    }
}
