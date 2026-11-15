import Foundation
import Combine

/// Which question a model answers. Per-feature overrides live in Settings → Providers.
enum FeatureScope: String, CaseIterable, Identifiable {
    case rightNow = "now"
    case missed
    case ask
    var id: String { rawValue }
    var title: String {
        switch self {
        case .rightNow: return "Right now"
        case .missed: return "What did I miss"
        case .ask: return "Ask"
        }
    }
}

/// Speech model tier. StreamLingo's "Base / Large V3 Turbo" split, same reasoning:
/// a small model loads in seconds and never stalls; the big one is an opt-in upgrade.
enum TranscriptionQuality: String, CaseIterable, Identifiable {
    case fast, accurate
    var id: String { rawValue }
    var title: String { self == .fast ? "Fast" : "Accurate" }
    var subtitle: String { self == .fast ? "Whisper Base · smaller and faster" : "Whisper Large V3 Turbo · best accuracy" }
    var modelID: String {
        self == .fast ? "openai_whisper-base" : "openai_whisper-large-v3_turbo_954MB"
    }
    var approxSize: String { self == .fast ? "~140 MB" : "~954 MB" }
    var note: String {
        self == .fast
            ? "Loads in seconds. Handles English + Indonesian. Start here."
            : "Bigger download, slower first load. Use if Fast misses words."
    }
}

/// Language being spoken in the meeting. Auto-detection on a 12 s window is unreliable —
/// Whisper happily "hears" English in Indonesian audio and hallucinates a transcript.
/// Naming the language is the difference between a transcript and fiction.
enum SpokenLanguage: String, CaseIterable, Identifiable {
    case auto, english, indonesian, spanish, japanese, korean, chinese, arabic, portuguese, german, french
    var id: String { rawValue }
    var title: String {
        switch self {
        case .auto: return "Auto-detect"
        case .english: return "English"
        case .indonesian: return "Indonesian"
        case .spanish: return "Spanish"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        case .chinese: return "Chinese"
        case .arabic: return "Arabic"
        case .portuguese: return "Portuguese"
        case .german: return "German"
        case .french: return "French"
        }
    }
    /// Whisper ISO code, or nil for auto.
    var code: String? {
        switch self {
        case .auto: return nil
        case .english: return "en"
        case .indonesian: return "id"
        case .spanish: return "es"
        case .japanese: return "ja"
        case .korean: return "ko"
        case .chinese: return "zh"
        case .arabic: return "ar"
        case .portuguese: return "pt"
        case .german: return "de"
        case .french: return "fr"
        }
    }
    var hint: LanguageHint {
        guard let code else { return .auto }
        return LanguageHint(rawValue: code) ?? .auto
    }
}

/// UserDefaults-backed settings. Secrets stay in Keychain (see KeychainStore).
final class AppSettings: ObservableObject {
    /// One settings object for the whole app (menu, panel, overlay all read the same values).
    static let shared = AppSettings()

    private let d = UserDefaults.standard
    private enum K {
        static let defaultProvider = "recatch.provider"
        static let modelPrefix = "recatch.model."
        static let providerPrefix = "recatch.provider."
        static let baseURLPrefix = "recatch.baseURL."
        static let cliPrefix = "recatch.cli."
        static let outputLanguage = "recatch.outputLanguage"
        static let retentionDays = "recatch.retentionDays"
        static let overlayEnabled = "recatch.overlayEnabled"
        static let autoListen = "recatch.autoListen"
        static let transcriptionQuality = "recatch.transcriptionQuality"
        static let spokenLanguage = "recatch.spokenLanguage"
    }

    init() {}

    // MARK: - Provider choice

    /// The provider the user picked. Falls back to Groq (free tier, fastest) on a fresh install.
    var defaultProvider: LLMProvider {
        get { LLMProvider(rawValue: d.string(forKey: K.defaultProvider) ?? "") ?? .groq }
        set { d.set(newValue.rawValue, forKey: K.defaultProvider); objectWillChange.send() }
    }

    func provider(for f: FeatureScope) -> LLMProvider {
        LLMProvider(rawValue: d.string(forKey: K.providerPrefix + f.rawValue) ?? "") ?? defaultProvider
    }
    func setProvider(_ p: LLMProvider, for f: FeatureScope) {
        d.set(p.rawValue, forKey: K.providerPrefix + f.rawValue); objectWillChange.send()
    }

    /// The provider that will actually answer: the chosen one if it's usable,
    /// otherwise the first one that is (so the app never dead-ends on setup).
    func effectiveProvider(for f: FeatureScope) -> LLMProvider? {
        let chosen = provider(for: f)
        if ProviderCatalog.readiness(chosen, baseURLOverride: baseURL(for: chosen)).isUsable { return chosen }
        return ProviderCatalog.firstReady(baseURLOverride: baseURL(for: .custom))
    }

    /// Why the chosen provider can't answer, or nil when it's fine.
    func readiness(for p: LLMProvider) -> ProviderCatalog.Readiness {
        ProviderCatalog.readiness(p, baseURLOverride: baseURL(for: p))
    }

    // MARK: - Model

    func model(for f: FeatureScope) -> String {
        let p = provider(for: f)
        if let m = d.string(forKey: K.modelPrefix + f.rawValue), !m.isEmpty { return m }
        return ProviderCatalog.defaultModel(p)
    }
    func setModel(_ m: String, for f: FeatureScope) {
        d.set(m, forKey: K.modelPrefix + f.rawValue); objectWillChange.send()
    }

    // MARK: - Endpoint overrides

    /// Per-provider endpoint override. Empty = use the catalog default.
    func baseURL(for p: LLMProvider) -> String {
        d.string(forKey: K.baseURLPrefix + p.rawValue) ?? ""
    }
    func setBaseURL(_ url: String, for p: LLMProvider) {
        d.set(url.trimmingCharacters(in: .whitespacesAndNewlines), forKey: K.baseURLPrefix + p.rawValue)
        objectWillChange.send()
    }
    /// Effective endpoint: user override first, catalog default second.
    func resolvedBaseURL(for p: LLMProvider) -> String? {
        let override = baseURL(for: p)
        if !override.isEmpty { return override }
        return ProviderCatalog.spec(p).baseURL
    }

    /// Binary name override for CLI providers (Command Code ships under several names).
    func cliCommand(for p: LLMProvider) -> String {
        let override = d.string(forKey: K.cliPrefix + p.rawValue) ?? ""
        return override.isEmpty ? (ProviderCatalog.spec(p).cliCommand ?? "") : override
    }
    func setCLICommand(_ cmd: String, for p: LLMProvider) {
        d.set(cmd.trimmingCharacters(in: .whitespacesAndNewlines), forKey: K.cliPrefix + p.rawValue)
        objectWillChange.send()
    }

    /// Fast by default — a live app must be usable within seconds of first launch.
    var transcriptionQuality: TranscriptionQuality {
        get { TranscriptionQuality(rawValue: d.string(forKey: K.transcriptionQuality) ?? "") ?? .fast }
        set { d.set(newValue.rawValue, forKey: K.transcriptionQuality); objectWillChange.send() }
    }

    /// Language spoken in the meeting (not the answer language).
    var spokenLanguage: SpokenLanguage {
        get { SpokenLanguage(rawValue: d.string(forKey: K.spokenLanguage) ?? "") ?? .auto }
        set { d.set(newValue.rawValue, forKey: K.spokenLanguage); objectWillChange.send() }
    }

    // MARK: - Misc

    /// Answers are written in the meeting's own language — ReCatch does not translate.
    /// Empty string means "same language as the transcript" (used for auto-detect).
    var outputLanguage: String {
        spokenLanguage == .auto ? "" : spokenLanguage.title
    }

    var retentionDays: Int {
        get {
            let v = d.integer(forKey: K.retentionDays)
            return v <= 0 ? 3 : v
        }
        set { d.set(max(1, min(7, newValue)), forKey: K.retentionDays); objectWillChange.send() }
    }

    var overlayEnabled: Bool {
        get { d.object(forKey: K.overlayEnabled) as? Bool ?? true }
        set { d.set(newValue, forKey: K.overlayEnabled); objectWillChange.send() }
    }

    /// Start listening by itself when a meeting takes the mic.
    var autoListen: Bool {
        get { d.object(forKey: K.autoListen) as? Bool ?? true }
        set { d.set(newValue, forKey: K.autoListen); objectWillChange.send() }
    }

    // MARK: - Gateway construction

    func gateway(for provider: LLMProvider) -> (any LLMGateway)? {
        let spec = ProviderCatalog.spec(provider)
        switch spec.kind {
        case .anthropic:
            guard let key = KeychainStore.load(provider: spec.keyAccount ?? "anthropic"), !key.isEmpty else { return nil }
            return AnthropicAdapter(apiKey: key)
        case .openAICompatible:
            guard let raw = resolvedBaseURL(for: provider), let url = URL(string: raw) else { return nil }
            let key = spec.keyAccount.flatMap { KeychainStore.load(provider: $0) } ?? ""
            if !spec.keyOptional, key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            return OpenAICompatibleAdapter(baseURL: url, apiKey: key)
        case .cli:
            let cmd = cliCommand(for: provider)
            guard !cmd.isEmpty else { return nil }
            return CLIAdapter(command: cmd, argsTemplate: spec.cliArgs ?? [])
        }
    }

    /// Resolve gateway + model + provider, falling back to whatever is usable.
    func gatewayFor(_ f: FeatureScope) -> (gateway: any LLMGateway, model: String, provider: LLMProvider)? {
        if let p = effectiveProvider(for: f), let g = gateway(for: p) {
            let model = model(for: f).isEmpty ? ProviderCatalog.defaultModel(p) : model(for: f)
            return (g, model, p)
        }
        // Chosen provider failed to build (bad URL / missing key) — try any ready one with its default model.
        for spec in ProviderCatalog.all where readiness(for: spec.provider).isUsable {
            if let g = gateway(for: spec.provider) {
                return (g, ProviderCatalog.defaultModel(spec.provider), spec.provider)
            }
        }
        return nil
    }

    func options(for f: FeatureScope, verbose: Bool) -> LLMOptions {
        let p = effectiveProvider(for: f) ?? defaultProvider
        let model = model(for: f).isEmpty ? ProviderCatalog.defaultModel(p) : model(for: f)
        let isCLI = ProviderCatalog.spec(p).isCLI
        // Catch-up needs room for sections; reasoning models (gpt-oss) spend tokens thinking first.
        let base = f == .missed ? 1400 : (f == .ask ? 900 : 400)
        return LLMOptions(model: model,
                          maxTokens: verbose ? base + 400 : base,
                          temperature: 0.3,
                          outputLanguage: outputLanguage,
                          timeoutSec: isCLI ? 90 : 30)
    }

    /// Human sentence for the empty state when nothing can answer.
    var missingKeyHint: String? {
        if let p = effectiveProvider(for: .rightNow), gateway(for: p) != nil { return nil }
        let chosen = defaultProvider
        switch readiness(for: chosen) {
        case .ready: return "No provider could be reached. Check Settings → Providers."
        case .needsKey: return "Add your \(ProviderCatalog.displayName(chosen)) key in Settings → Providers."
        case .needsBaseURL: return "Set the base URL for your custom endpoint in Settings → Providers."
        case .cliMissing(let cmd): return "\(cmd) is not installed. Pick another provider in Settings → Providers."
        case .notRunning: return "\(ProviderCatalog.displayName(chosen)) is not running on this Mac. Start it, or pick another provider."
        }
    }
}
