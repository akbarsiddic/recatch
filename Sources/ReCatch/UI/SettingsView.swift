import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var capture: AudioCaptureManager
    @State private var keys: [LLMProvider: String] = [:]
    @State private var savedFlash: String?

    var body: some View {
        TabView {
            general.tabItem { Text("General") }
            providers.tabItem { Text("Providers") }
            privacy.tabItem { Text("Privacy") }
        }
        .frame(width: 560, height: 400)
        .onAppear {
            for p in LLMProvider.allCases {
                if let acct = ProviderCatalog.keyAccount(p) {
                    keys[p] = KeychainStore.load(provider: acct) ?? ""
                }
            }
        }
    }

    // MARK: - General

    private var general: some View {
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
                Text(hint).font(.caption).foregroundColor(.orange)
            }
        }.padding(20)
    }

    // MARK: - Providers

    private var providers: some View {
        Form {
            Picker("Default brain:", selection: $settings.defaultProvider) {
                ForEach(LLMProvider.allCases, id: \.self) { Text(ProviderCatalog.displayName($0)).tag($0) }
            }
            Divider()
            ForEach(FeatureScope.allCases) { f in
                HStack {
                    Text(f.title).frame(width: 130, alignment: .leading)
                    Picker("", selection: Binding(
                        get: { settings.provider(for: f) },
                        set: { settings.setProvider($0, for: f) })) {
                        ForEach(LLMProvider.allCases, id: \.self) { Text(ProviderCatalog.displayName($0)).tag($0) }
                    }.labelsHidden().frame(width: 150)
                    TextField("model", text: Binding(
                        get: { settings.model(for: f) },
                        set: { settings.setModel($0, for: f) }))
                    .textFieldStyle(.roundedBorder)
                }
            }
            Text("Tip: cheap model for Right now, stronger for Ask.").font(.caption).foregroundColor(.secondary)
            Divider()
            ForEach(LLMProvider.allCases.filter { ProviderCatalog.keyAccount($0) != nil }, id: \.self) { p in
                HStack {
                    Text(ProviderCatalog.displayName(p)).frame(width: 130, alignment: .leading)
                    SecureField("API key", text: Binding(
                        get: { keys[p] ?? "" },
                        set: { keys[p] = $0 }))
                    .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        if let acct = ProviderCatalog.keyAccount(p) {
                            KeychainStore.save(provider: acct, key: keys[p] ?? "")
                            savedFlash = "\(ProviderCatalog.displayName(p)) key saved."
                        }
                    }
                }
            }
            if let note = ProviderCatalog.slowNote(settings.defaultProvider) {
                Text(note).font(.caption).foregroundColor(.secondary)
            }
            if let flash = savedFlash {
                Text(flash).font(.caption).foregroundColor(.green)
            }
        }.padding(20)
    }

    // MARK: - Privacy

    private var privacy: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio never leaves this Mac. Only transcript text is sent to your LLM for the window you request.")
                .font(.callout)
            Text("What left this machine (timestamp + size only):")
                .font(.headline).padding(.top, 4)
            List(logEntries, id: \.t) { e in
                HStack {
                    Text(Self.logDate.string(from: Date(timeIntervalSince1970: TimeInterval(e.t) / 1000)))
                    Spacer()
                    Text("\(e.provider)/\(e.model)").foregroundColor(.secondary)
                    Text("↑\(e.tokensIn) ↓\(e.tokensOut)").foregroundColor(.secondary)
                }.font(.caption).monospacedDigit()
            }
            HStack {
                Button("Delete everything now") {
                    try? FileManager.default.removeItem(at: dbURL())
                }.foregroundColor(.red)
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
