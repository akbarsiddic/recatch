import SwiftUI

/// Providers: who answers, and is it actually reachable. "Ready" means a real round-trip passed.
struct ProvidersPane: View {
    @StateObject private var settings = AppSettings.shared
    @State private var keys: [LLMProvider: String] = [:]
    @State private var testing: LLMProvider?
    @State private var result: [LLMProvider: String] = [:]
    @State private var flash: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PaneHeader(title: "Providers",
                           subtitle: "Bring your own key, or reuse a coding agent you already pay for.")
                routingCard
                PaneCard(title: "Available") {
                    VStack(spacing: 0) {
                        ForEach(Array(ProviderCatalog.all.enumerated()), id: \.element.provider) { index, spec in
                            if index > 0 { Divider().padding(.vertical, 2) }
                            row(spec)
                        }
                    }
                }
                Text("Keys live in the macOS Keychain — never in preferences, logs, or the transcript.")
                    .font(.caption).foregroundColor(.secondary)
                if let flash { Text(flash).font(.caption).foregroundColor(Brand.ok) }
            }
            .padding(20)
        }
    }

    // MARK: Routing

    private var routingCard: some View {
        PaneCard(title: "Which brain answers") {
            VStack(spacing: 8) {
                ForEach(FeatureScope.allCases) { f in
                    HStack(spacing: 10) {
                        Text(f.title).font(.callout).frame(width: 130, alignment: .leading)
                        Picker("", selection: Binding(
                            get: { settings.provider(for: f) },
                            set: { settings.setProvider($0, for: f) })) {
                            ForEach(ProviderCatalog.all, id: \.provider) { spec in
                                Text(spec.name).tag(spec.provider)
                            }
                        }
                        .labelsHidden().frame(width: 170)
                        TextField(ProviderCatalog.defaultModel(settings.provider(for: f)), text: Binding(
                            get: { settings.model(for: f) },
                            set: { settings.setModel($0, for: f) }))
                        .textFieldStyle(.roundedBorder)
                        if let ready = settings.effectiveProvider(for: f) {
                            ReadinessPill(text: ProviderCatalog.displayName(ready), tone: Brand.ok)
                        } else {
                            ReadinessPill(text: "not ready", tone: Brand.warn)
                        }
                        Spacer()
                    }
                }
                Text("Right now wants the fastest model you have. Ask can afford a slower, smarter one.")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func row(_ spec: ProviderSpec) -> some View {
        let ready = settings.readiness(for: spec.provider)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(spec.name).font(.callout).bold()
                ReadinessPill(text: ready.label, tone: ready.isUsable ? Brand.ok : Brand.warn)
                if let note = spec.note {
                    Text(note).font(.caption2).foregroundColor(.secondary).lineLimit(1)
                }
                Spacer()
                if let res = result[spec.provider] {
                    Text(res)
                        .font(.caption2)
                        .foregroundColor(res.hasPrefix("OK") ? Brand.ok : Brand.bad)
                        .lineLimit(1)
                }
                Button(testing == spec.provider ? "Testing…" : "Test") {
                    Task { await test(spec.provider) }
                }
                .buttonStyle(.bordered)
                .disabled(testing != nil || !ready.isUsable)
            }

            if spec.kind == .cli {
                HStack(spacing: 8) {
                    TextField(spec.cliCommand ?? "", text: Binding(
                        get: { settings.cliCommand(for: spec.provider) },
                        set: { settings.setCLICommand($0, for: spec.provider) }))
                        .textFieldStyle(.roundedBorder).frame(width: 170)
                    Text("reads the prompt from stdin").font(.caption2).foregroundColor(.secondary)
                }
            } else {
                if let account = spec.keyAccount {
                    HStack(spacing: 8) {
                        SecureField(spec.keyOptional ? "optional key" : "API key",
                                    text: Binding(get: { keys[spec.provider] ?? "" },
                                                  set: { keys[spec.provider] = $0 }))
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                        Button("Save") {
                            KeychainStore.save(provider: account, key: keys[spec.provider] ?? "")
                            flash = "\(spec.name) key saved."
                            settings.objectWillChange.send()
                        }
                        .buttonStyle(.bordered)
                        if KeychainStore.has(provider: account) {
                            Label("stored", systemImage: "checkmark.circle.fill")
                                .font(.caption2).foregroundColor(Brand.ok)
                        }
                    }
                }
                if [LLMProvider.custom, .nineRouter, .ollama].contains(spec.provider) {
                    HStack(spacing: 8) {
                        TextField(spec.baseURL ?? "https://…/v1", text: Binding(
                            get: { settings.baseURL(for: spec.provider) },
                            set: { settings.setBaseURL($0, for: spec.provider) }))
                            .textFieldStyle(.roundedBorder).frame(maxWidth: 320)
                        Text(spec.baseURL.map { "default \($0)" } ?? "")
                            .font(.caption2).foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func test(_ p: LLMProvider) async {
        testing = p
        defer { testing = nil }
        guard let g = settings.gateway(for: p) else { result[p] = "FAIL: not configured"; return }
        let model = settings.model(for: .rightNow).isEmpty
            ? ProviderCatalog.defaultModel(p) : settings.model(for: .rightNow)
        var opts = settings.options(for: .rightNow, verbose: false)
        opts.model = model
        let started = Date()
        do {
            let out = try await g.complete(prompt: "Reply with exactly: OK", options: opts)
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            result[p] = "OK · \(ms) ms · \(out.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))"
        } catch {
            result[p] = "FAIL: \(error.localizedDescription)"
        }
    }
}
