import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var capture: AudioCaptureManager
    @State private var keys: [LLMProvider: String] = [:]
    @State private var savedFlash: String?
    @State private var testing: LLMProvider?
    @State private var testResult: [LLMProvider: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            BrandHeader(status: "Settings", tone: Brand.accent)
                .padding(.horizontal, 20).padding(.top, 14)
            TabView {
                generalForm.tabItem { Text("General") }
                providersForm.tabItem { Text("Providers") }
                privacyView.tabItem { Text("Privacy") }
            }
            .padding(.top, 6)
        }
        .frame(width: 720, height: 560)
        .onAppear(perform: loadKeys)
    }

    private func loadKeys() {
        for spec in ProviderCatalog.all {
            guard let acct = spec.keyAccount else { continue }
            keys[spec.provider] = KeychainStore.load(provider: acct) ?? ""
        }
    }

    // MARK: - General

    var generalForm: some View {
        Form {
            KeyboardShortcuts.Recorder("Summon panel:", name: .summonPanel)
            Picker("Spoken language:", selection: $settings.spokenLanguage) {
                ForEach(SpokenLanguage.allCases) { l in
                    Text(l.title).tag(l)
                }
            }
            Text(settings.spokenLanguage == .auto
                 ? "Auto-detect guesses per window and can hear English in Indonesian audio. Naming the language is more accurate."
                 : "Answers still come back in the answer language below.")
                .font(.caption).foregroundColor(.secondary)
            // Speech model tier: Base loads in seconds; Large V3 Turbo is the accuracy upgrade.
            Picker("Speech model:", selection: $settings.transcriptionQuality) {
                ForEach(TranscriptionQuality.allCases) { q in
                    Text("\(q.title) — \(q.approxSize)").tag(q)
                }
            }
            Text(settings.transcriptionQuality.subtitle + " · " + settings.transcriptionQuality.note)
                .font(.caption).foregroundColor(.secondary)
            HStack(spacing: 6) {
                Text(capture.modelLine).font(.caption2).foregroundColor(.secondary)
                if capture.modelLine.lowercased().contains("failed") || capture.modelLine.lowercased().contains("damaged") {
                    Button("Retry download") { capture.retryModel() }
                        .buttonStyle(.plain).font(.caption2).foregroundColor(Brand.accent)
                }
            }
            Toggle("Start listening automatically when a meeting takes the mic", isOn: $settings.autoListen)
            Toggle("Floating overlay", isOn: $settings.overlayEnabled)
            // No translation: answers come back in the meeting's language, always.
            HStack(spacing: 6) {
                Image(systemName: "text.bubble").foregroundStyle(Brand.accent)
                Text(settings.spokenLanguage == .auto
                     ? "Answers come back in whatever language the meeting is in."
                     : "Answers come back in \(settings.spokenLanguage.title). No translation.")
                    .font(.caption).foregroundColor(.secondary)
            }
            Stepper("Keep transcripts: \(settings.retentionDays) days",
                    value: Binding(get: { settings.retentionDays },
                                   set: { settings.retentionDays = $0 }), in: 1...7)
            if let hint = settings.missingKeyHint {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").foregroundStyle(Brand.warn)
                    Text(hint).font(.caption)
                }
            }
            Section {
                Text("Mic audio stays on this Mac and is transcribed on-device. Only the transcript window you ask about is sent to your provider.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.padding(20)
    }

    // MARK: - Providers

    var providersForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Which brain answers which question
                VStack(alignment: .leading, spacing: 8) {
                    Text("Which brain answers").font(.headline)
                    ForEach(FeatureScope.allCases) { f in
                        HStack(spacing: 10) {
                            Text(f.title).frame(width: 120, alignment: .leading)
                            Picker("", selection: Binding(
                                get: { settings.provider(for: f) },
                                set: { settings.setProvider($0, for: f) })) {
                                ForEach(ProviderCatalog.all, id: \.provider) { spec in
                                    Text(spec.name).tag(spec.provider)
                                }
                            }
                            .labelsHidden().frame(width: 160)
                            TextField(ProviderCatalog.defaultModel(settings.provider(for: f)), text: Binding(
                                get: { settings.model(for: f) },
                                set: { settings.setModel($0, for: f) }))
                            .textFieldStyle(.roundedBorder)
                            if let ready = settings.effectiveProvider(for: f) {
                                Text("→ \(ProviderCatalog.displayName(ready))")
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                    Text("Tip: Groq for Right now (instant), a stronger model for Ask.")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(14)
                .background(Brand.surface)
                .clipShape(RoundedRectangle(cornerRadius: Brand.radius))

                Text("Add a provider").font(.headline)

                ForEach(ProviderCatalog.all, id: \.provider) { spec in
                    providerRow(spec)
                }

                if let flash = savedFlash {
                    Text(flash).font(.caption).foregroundColor(Brand.accent)
                }
                Text("Keys are stored in the macOS Keychain, never in preferences or logs.")
                    .font(.caption2).foregroundColor(.secondary)
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func providerRow(_ spec: ProviderSpec) -> some View {
        let ready = settings.readiness(for: spec.provider)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle()
                    .fill(ready.isUsable ? Brand.ok : Brand.warn)
                    .frame(width: 7, height: 7)
                Text(spec.name).fontWeight(.semibold)
                Text(ready.label)
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background((ready.isUsable ? Brand.ok : Brand.warn).opacity(0.14))
                    .clipShape(Capsule())
                Spacer()
                if let note = spec.note {
                    Text(note).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Button(testing == spec.provider ? "Testing…" : "Test") {
                    Task { await test(spec.provider) }
                }
                .disabled(testing != nil)
            }

            if spec.kind == .cli {
                HStack(spacing: 8) {
                    Text("Command").font(.caption).foregroundColor(.secondary).frame(width: 60, alignment: .leading)
                    TextField(spec.cliCommand ?? "", text: Binding(
                        get: { settings.cliCommand(for: spec.provider) },
                        set: { settings.setCLICommand($0, for: spec.provider) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    Text("reads the prompt from stdin").font(.caption2).foregroundColor(.secondary)
                }
            } else {
                if let acct = spec.keyAccount {
                    HStack(spacing: 8) {
                        Text("Key").font(.caption).foregroundColor(.secondary).frame(width: 60, alignment: .leading)
                        SecureField(spec.keyOptional ? "optional" : "API key", text: Binding(
                            get: { keys[spec.provider] ?? "" },
                            set: { keys[spec.provider] = $0 }))
                        .textFieldStyle(.roundedBorder)
                        Button("Save") {
                            KeychainStore.save(provider: acct, key: keys[spec.provider] ?? "")
                            savedFlash = "\(spec.name) key saved in Keychain."
                            settings.objectWillChange.send()
                        }
                    }
                }
                if spec.provider == .custom || spec.provider == .nineRouter || spec.provider == .ollama {
                    HStack(spacing: 8) {
                        Text("URL").font(.caption).foregroundColor(.secondary).frame(width: 60, alignment: .leading)
                        TextField(spec.baseURL ?? "https://…/v1", text: Binding(
                            get: { settings.baseURL(for: spec.provider) },
                            set: { settings.setBaseURL($0, for: spec.provider) }))
                        .textFieldStyle(.roundedBorder)
                        Text(spec.baseURL.map { "default: \($0)" } ?? "")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }

            if let result = testResult[spec.provider] {
                Text(result).font(.caption2).foregroundColor(result.hasPrefix("OK") ? Brand.ok : Brand.bad)
            }
        }
        .padding(12)
        .background(Brand.surface)
        .clipShape(RoundedRectangle(cornerRadius: Brand.radius))
    }

    /// Round-trip a real request so "Ready" means "answered", not "looks configured".
    private func test(_ p: LLMProvider) async {
        testing = p
        defer { testing = nil }
        guard let g = settings.gateway(for: p) else {
            testResult[p] = "FAIL: not configured"
            return
        }
        let model = settings.model(for: .rightNow).isEmpty ? ProviderCatalog.defaultModel(p) : settings.model(for: .rightNow)
        var opts = settings.options(for: .rightNow, verbose: false)
        opts.model = model
        let started = Date()
        do {
            let out = try await g.complete(prompt: "Reply with exactly: OK", options: opts)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            testResult[p] = "OK · \(ms) ms · \(out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))"
        } catch {
            testResult[p] = "FAIL: \(error.localizedDescription)"
        }
    }

    // MARK: - Privacy

    var privacyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Brand.accent)
                Text("Audio never leaves this Mac. Only transcript text is sent to your provider for the window you request.")
                    .font(.callout)
            }
            Text("What left this machine (timestamp + size only):")
                .font(.headline).padding(.top, 4)
            if logEntries.isEmpty {
                Text("Nothing sent yet — ask your first question with ⌥⌘R.")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center).padding()
            } else {
                List(logEntries, id: \.t) { e in
                    HStack {
                        Text(Self.logDate.string(from: Date(timeIntervalSince1970: TimeInterval(e.t) / 1000)))
                        Spacer()
                        Text("\(e.provider)/\(e.model)").foregroundColor(.secondary)
                        Text("↑\(e.tokensIn) ↓\(e.tokensOut)").foregroundColor(.secondary)
                    }.font(.caption).monospacedDigit()
                }
            }
            HStack {
                Button("Delete everything now") {
                    try? FileManager.default.removeItem(at: dbURL())
                }.foregroundColor(Brand.bad)
                Spacer()
                Text("Auto-deletes after \(settings.retentionDays) days.").font(.caption).foregroundColor(.secondary)
            }
        }.padding(20)
    }

    private var logEntries: [MeetingStore.LLMLogEntry] {
        capture.llmLog()
    }

    private static let logDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short; f.timeStyle = .short
        return f
    }()

    private func dbURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReCatch.sqlite")
    }
}
