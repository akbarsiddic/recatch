import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var capture: AudioCaptureManager
    @State private var keys: [LLMProvider: String] = [:]
    @State private var savedFlash: String?

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
        .frame(width: 680, height: 480)
        .onAppear {
            for p in LLMProvider.allCases {
                if let acct = ProviderCatalog.keyAccount(p) {
                    keys[p] = KeychainStore.load(provider: acct) ?? ""
                }
            }
        }
    }

    // MARK: - General

    var generalForm: some View {
        Form {
            KeyboardShortcuts.Recorder("Summon panel:", name: .summonPanel)
            Picker("Answer language:", selection: $settings.outputLanguage) {
                ForEach(["English", "Indonesian", "Japanese", "Spanish", "Arabic"], id: \.self) { Text($0) }
            }
            Stepper("Keep transcripts: \(settings.retentionDays) days",
                    value: Binding(get: { settings.retentionDays },
                                   set: { settings.retentionDays = $0 }), in: 1...7)
            Toggle("Overlay pill (experimental)", isOn: $settings.overlayEnabled)
            if let hint = settings.missingKeyHint {
                HStack(spacing: 6) {
                    Image(systemName: "key.fill").foregroundStyle(Brand.warn)
                    Text(hint).font(.caption)
                }
            }
            Section {
                Text("How it works: mic + system audio stay on this Mac, transcribed on-device. Only the transcript window you ask about is sent to your LLM.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }.padding(20)
    }

    // MARK: - Providers

    var providersForm: some View {
        Form {
            Picker("Default brain:", selection: $settings.defaultProvider) {
                ForEach(LLMProvider.allCases, id: \.self) { Text(ProviderCatalog.displayName($0)).tag($0) }
            }
            .tint(Brand.accent)
            Divider()
            ForEach(FeatureScope.allCases) { f in
                HStack {
                    Text(f.title).frame(width: 110, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { settings.provider(for: f) },
                        set: { settings.setProvider($0, for: f) })) {
                        ForEach(LLMProvider.allCases, id: \.self) { Text(ProviderCatalog.displayName($0)).tag($0) }
                    }.labelsHidden().frame(width: 140)
                    TextField("model", text: Binding(
                        get: { settings.model(for: f) },
                        set: { settings.setModel($0, for: f) }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Tip: a cheap model for Right now, a stronger one for Ask.")
                .font(.caption).foregroundColor(.secondary)
            Divider()
            ForEach(LLMProvider.allCases.filter { ProviderCatalog.keyAccount($0) != nil }, id: \.self) { p in
                HStack {
                    Image(systemName: keySaved(p) ? "key.fill" : "key")
                        .foregroundStyle(keySaved(p) ? Brand.accent : .secondary)
                        .frame(width: 20)
                    Text(ProviderCatalog.displayName(p)).frame(width: 110, alignment: .leading)
                    SecureField("API key", text: Binding(
                        get: { keys[p] ?? "" },
                        set: { keys[p] = $0 }))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: .infinity)
                    Button("Save") {
                        if let acct = ProviderCatalog.keyAccount(p) {
                            KeychainStore.save(provider: acct, key: keys[p] ?? "")
                            savedFlash = "\(ProviderCatalog.displayName(p)) key saved in Keychain."
                        }
                    }
                }
            }
            if let note = ProviderCatalog.slowNote(settings.defaultProvider) {
                Text(note).font(.caption).foregroundColor(.secondary)
            }
            if let flash = savedFlash {
                Text(flash).font(.caption).foregroundColor(Brand.accent)
            }
        }.padding(20)
    }

    private func keySaved(_ p: LLMProvider) -> Bool {
        guard let acct = ProviderCatalog.keyAccount(p) else { return true }
        return !(KeychainStore.load(provider: acct) ?? "").isEmpty
    }

    // MARK: - Privacy

    var privacyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "lock.shield.fill").foregroundStyle(Brand.accent)
                Text("Audio never leaves this Mac. Only transcript text is sent to your LLM for the window you request.")
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
