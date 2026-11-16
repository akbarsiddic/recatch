import SwiftUI

/// First run: five short steps instead of a menu item that hides a 900 MB download.
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @StateObject private var settings = AppSettings.shared
    @StateObject private var capture = AudioCaptureManager.shared
    @StateObject private var feed = TranscriptFeed.shared

    @State private var step = 0
    @State private var micOK = PermissionsManager.micGranted()
    @State private var audioOK = PermissionsManager.audioRecordingGranted()
    @State private var key = ""
    @State private var testResult: String?
    @State private var testing = false
    @State private var testingMic = false

    private let steps = ["Welcome", "Access", "Language", "Provider", "Model", "Check"]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    switch step {
                    case 0: welcome
                    case 1: access
                    case 2: language
                    case 3: provider
                    case 4: model
                    default: check
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer
        }
        .frame(width: 620, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: Chrome

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                BrandMark(size: 22)
                Text(Brand.name).font(.headline)
                Text("· \(steps[step])").font(.headline).foregroundColor(.secondary)
                Spacer()
            }
            HStack(spacing: 4) {
                ForEach(steps.indices, id: \.self) { i in
                    Capsule()
                        .fill(i <= step ? Brand.accent : Color.secondary.opacity(0.2))
                        .frame(height: 3)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 12)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }.buttonStyle(.plain).foregroundColor(.secondary)
            }
            Spacer()
            if step < 5 {
                Button("Skip setup") { finish() }
                    .buttonStyle(.plain).foregroundColor(.secondary)
                    .padding(.trailing, 8)
            }
            Button(primaryTitle) { advance() }
                .buttonStyle(.borderedProminent)
                .tint(Brand.accent)
                .disabled(!canAdvance)
                .keyboardShortcut(.defaultAction)
        }
        .padding(18)
    }

    private var primaryTitle: String {
        switch step {
        case 0: return "Get started"
        case 4: return capture.modelPhase == .ready ? "Continue" : "Continue in background"
        case 5: return "Finish"
        default: return "Continue"
        }
    }

    private var canAdvance: Bool {
        switch step {
        case 1: return micOK
        case 3: return settings.effectiveProvider(for: .rightNow) != nil
        default: return true
        }
    }

    private func advance() {
        if step == 5 { finish(); return }
        step += 1
        if step == 4 { Task { await capture.prepareModel() } }
    }

    private func finish() {
        settings.onboarded = true
        isPresented = false
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Never ask “what did I miss?” again.")
                .font(.largeTitle).bold()
            Text("ReCatch listens on your Mac, shows live captions, and answers two questions in seconds: what's happening right now, and what you missed.")
                .font(.callout).foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                bullet("waveform", "Audio never leaves this Mac — transcription is on-device.")
                bullet("text.bubble", "Only transcript text goes to the provider you choose.")
                bullet("lock.shield", "No bots join your call. Nobody is notified.")
            }
            .padding(.top, 4)
            Text("You are responsible for complying with local rules and letting participants know you're transcribing.")
                .font(.caption).foregroundColor(.secondary)
                .padding(.top, 6)
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(Brand.accent).frame(width: 18)
            Text(text).font(.callout)
        }
    }

    private var access: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Let ReCatch hear the room").font(.title2).bold()
            Text("Microphone is required. Audio recording is what lets ReCatch hear everyone else — it does not need Screen Recording.")
                .font(.callout).foregroundColor(.secondary)

            accessRow("Microphone", granted: micOK, detail: "Your voice") {
                Task { micOK = await PermissionsManager.requestMic() }
            }
            accessRow("Audio recording", granted: audioOK, detail: "Everyone else, via system audio") {
                PermissionsManager.requestAudioRecording()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    audioOK = PermissionsManager.audioRecordingGranted()
                }
            }
            Button("Check again") {
                micOK = PermissionsManager.micGranted()
                audioOK = PermissionsManager.audioRecordingGranted()
            }
            .buttonStyle(.bordered)
        }
    }

    private func accessRow(_ title: String, granted: Bool, detail: String, grant: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundColor(granted ? Brand.ok : Brand.warn)
                .font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout).bold()
                Text(detail).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if !granted {
                Button("Allow", action: grant).buttonStyle(.borderedProminent).tint(Brand.accent)
            }
        }
        .padding(12)
        .background(Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: Brand.radius))
    }

    private var language: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What language are your meetings in?").font(.title2).bold()
            Text("ReCatch detects it once from the first seconds of speech and locks it for the meeting — guessing per window is what makes transcripts hallucinate.")
                .font(.callout).foregroundColor(.secondary)

            VStack(spacing: 2) {
                ForEach(SpokenLanguage.allCases.prefix(1)) { l in
                    languageRow(l, detail: "Recommended. Detects once, then locks. Override any time.")
                }
                ForEach(SpokenLanguage.allCases.dropFirst()) { l in
                    languageRow(l, detail: nil)
                }
            }

            Text("Answers come back in this language. ReCatch does not translate.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func languageRow(_ l: SpokenLanguage, detail: String?) -> some View {
        HStack(spacing: 10) {
            Image(systemName: settings.spokenLanguage == l ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(settings.spokenLanguage == l ? Brand.accent : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(l.title).font(.callout)
                if let detail { Text(detail).font(.caption2).foregroundColor(.secondary) }
            }
            Spacer()
        }
        .padding(.vertical, 7).padding(.horizontal, 10)
        .contentShape(Rectangle())
        .onTapGesture { settings.spokenLanguage = l }
    }

    private var provider: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Who answers your questions?").font(.title2).bold()
            Text("Transcript text is sent to this provider. Pick whichever you already have.")
                .font(.callout).foregroundColor(.secondary)

            let options = ProviderCatalog.all.filter { $0.kind != .cli }
            Picker("", selection: Binding(
                get: { settings.defaultProvider },
                set: { settings.defaultProvider = $0; testResult = nil })) {
                ForEach(options, id: \.provider) { spec in
                    Text(spec.name).tag(spec.provider)
                }
            }
            .pickerStyle(.menu).labelsHidden().frame(width: 240)

            let spec = ProviderCatalog.spec(settings.defaultProvider)
            if let account = spec.keyAccount {
                HStack(spacing: 8) {
                    SecureField("API key", text: $key).textFieldStyle(.roundedBorder).frame(width: 340)
                    Button("Save") {
                        KeychainStore.save(provider: account, key: key)
                        settings.objectWillChange.send()
                        Task { await test(spec.provider) }
                    }
                    .buttonStyle(.borderedProminent).tint(Brand.accent)
                }
            }
            if [LLMProvider.custom, .nineRouter, .ollama].contains(spec.provider) {
                TextField(spec.baseURL ?? "https://…/v1", text: Binding(
                    get: { settings.baseURL(for: spec.provider) },
                    set: { settings.setBaseURL($0, for: spec.provider) }))
                    .textFieldStyle(.roundedBorder).frame(width: 340)
            }

            HStack(spacing: 8) {
                Button(testing ? "Testing…" : "Test connection") { Task { await test(spec.provider) } }
                    .buttonStyle(.bordered)
                    .disabled(testing)
                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundColor(testResult.hasPrefix("OK") ? Brand.ok : Brand.bad)
                }
            }

            Text("Already have Claude Code, Codex, Gemini CLI or opencode installed? Those work too — add them later under Providers.")
                .font(.caption).foregroundColor(.secondary)
        }
    }

    private func test(_ p: LLMProvider) async {
        testing = true
        defer { testing = false }
        guard let g = settings.gateway(for: p) else { testResult = "Add a key first."; return }
        var opts = settings.options(for: .rightNow, verbose: false)
        opts.model = settings.model(for: .rightNow).isEmpty
            ? ProviderCatalog.defaultModel(p) : settings.model(for: .rightNow)
        let started = Date()
        do {
            _ = try await g.complete(prompt: "Reply with exactly: OK", options: opts)
            testResult = "OK · \(Int(Date().timeIntervalSince(started) * 1000)) ms"
        } catch {
            testResult = "Failed: \(error.localizedDescription)"
        }
    }

    private var model: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Download a speech model").font(.title2).bold()
            Text("Runs entirely on this Mac. Fast is small and loads in seconds — you can upgrade to Accurate later.")
                .font(.callout).foregroundColor(.secondary)

            ForEach(TranscriptionQuality.allCases) { q in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: settings.transcriptionQuality == q ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(settings.transcriptionQuality == q ? Brand.accent : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(q.title).font(.callout).bold()
                            Text(q.approxSize).font(.caption2).foregroundColor(.secondary)
                        }
                        Text(q.subtitle).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(settings.transcriptionQuality == q ? Brand.accentSoft : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: Brand.radius))
                .contentShape(Rectangle())
                .onTapGesture { settings.transcriptionQuality = q }
            }

            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: capture.modelProgress)
                Text(capture.modelLine).font(.caption).foregroundColor(.secondary)
            }
            .padding(.top, 4)
        }
    }

    private var check: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Say something").font(.title2).bold()
            Text("A quick check that the mic and the model agree. This does not save a meeting.")
                .font(.callout).foregroundColor(.secondary)

            HStack(spacing: 12) {
                LevelMeter(level: capture.level)
                Button(testingMic ? "Listening…" : "Listen for 8 seconds") {
                    Task {
                        testingMic = true
                        await capture.startMeeting()
                        try? await Task.sleep(nanoseconds: 8_000_000_000)
                        await capture.stopMeeting()
                        testingMic = false
                    }
                }
                .buttonStyle(.bordered)
                .disabled(testingMic)
            }

            Text(feed.caption.isEmpty ? "Nothing heard yet." : feed.caption)
                .font(.callout)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.surface)
                .clipShape(RoundedRectangle(cornerRadius: Brand.radius))

            Text("Press ⌥⌘R in any meeting for catch-up. The overlay shows live captions while you listen.")
                .font(.caption).foregroundColor(.secondary)
        }
    }
}
