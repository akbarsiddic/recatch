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

/// Static catalog: provider → display name, default model, keychain account (nil = no key needed).
enum ProviderCatalog {
    static func displayName(_ p: LLMProvider) -> String {
        switch p {
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .openCodeZen: return "OpenCode Zen"
        case .openRouter: return "OpenRouter"
        case .ollama: return "Ollama (local)"
        case .opencodeCLI: return "opencode CLI"
        case .claudeCLI: return "Claude CLI"
        case .codexCLI: return "Codex CLI"
        }
    }

    static func defaultModel(_ p: LLMProvider) -> String {
        switch p {
        case .anthropic: return "claude-sonnet-4-5"
        case .openAI: return "gpt-4o-mini"
        case .openCodeZen: return "opencode-zen/ultracode"
        case .openRouter: return "anthropic/claude-sonnet-4"
        case .ollama: return "qwen2.5:7b"
        case .opencodeCLI: return "opencode-zen/ultracode"
        case .claudeCLI: return "sonnet"
        case .codexCLI: return "gpt-5"
        }
    }

    /// Keychain account, or nil when no key is needed (local / CLI subscription).
    static func keyAccount(_ p: LLMProvider) -> String? {
        switch p {
        case .anthropic: return "anthropic"
        case .openAI: return "openai"
        case .openCodeZen: return "opencode-zen"
        case .openRouter: return "openrouter"
        case .ollama, .opencodeCLI, .claudeCLI, .codexCLI: return nil
        }
    }

    static func slowNote(_ p: LLMProvider) -> String? {
        switch p {
        case .opencodeCLI, .claudeCLI, .codexCLI:
            return "CLI uses your subscription ($0 extra) but is slow (~5–12s) — Ask only."
        case .ollama:
            return "Runs fully offline. Start it with `ollama serve` first."
        default:
            return nil
        }
    }
}

/// UserDefaults-backed settings. Secrets stay in Keychain (see KeychainStore).
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard
    private enum K {
        static let defaultProvider = "recatch.provider"
        static let modelPrefix = "recatch.model."
        static let providerPrefix = "recatch.provider."
        static let outputLanguage = "recatch.outputLanguage"
        static let retentionDays = "recatch.retentionDays"
        static let overlayEnabled = "recatch.overlayEnabled"
    }

    init() {}

    var defaultProvider: LLMProvider {
        get { LLMProvider(rawValue: d.string(forKey: K.defaultProvider) ?? "") ?? .anthropic }
        set { d.set(newValue.rawValue, forKey: K.defaultProvider); objectWillChange.send() }
    }

    func provider(for f: FeatureScope) -> LLMProvider {
        LLMProvider(rawValue: d.string(forKey: K.providerPrefix + f.rawValue) ?? "") ?? defaultProvider
    }
    func setProvider(_ p: LLMProvider, for f: FeatureScope) {
        d.set(p.rawValue, forKey: K.providerPrefix + f.rawValue); objectWillChange.send()
    }

    func model(for f: FeatureScope) -> String {
        let p = provider(for: f)
        if let m = d.string(forKey: K.modelPrefix + f.rawValue), !m.isEmpty { return m }
        return ProviderCatalog.defaultModel(p)
    }
    func setModel(_ m: String, for f: FeatureScope) {
        d.set(m, forKey: K.modelPrefix + f.rawValue); objectWillChange.send()
    }

    var outputLanguage: String {
        get { d.string(forKey: K.outputLanguage) ?? "English" }
        set { d.set(newValue, forKey: K.outputLanguage); objectWillChange.send() }
    }

    var retentionDays: Int {
        get {
            let v = d.integer(forKey: K.retentionDays)
            return v <= 0 ? 3 : v
        }
        set { d.set(max(1, min(7, newValue)), forKey: K.retentionDays); objectWillChange.send() }
    }

    var overlayEnabled: Bool {
        get { d.bool(forKey: K.overlayEnabled) }
        set { d.set(newValue, forKey: K.overlayEnabled); objectWillChange.send() }
    }

    // MARK: - Gateway construction

    func gateway(for provider: LLMProvider) -> (any LLMGateway)? {
        switch provider {
        case .anthropic:
            guard let k = KeychainStore.load(provider: "anthropic"), !k.isEmpty else { return nil }
            return AnthropicAdapter(apiKey: k)
        case .openAI, .openCodeZen, .openRouter, .ollama:
            let preset = OpenAICompatibleAdapter.preset(provider)
            let account = ProviderCatalog.keyAccount(provider)
            let key = account.flatMap { KeychainStore.load(provider: $0) } ?? ""
            if provider != .ollama, key.isEmpty { return nil }
            return OpenAICompatibleAdapter(baseURL: URL(string: preset.url)!, apiKey: key)
        case .opencodeCLI:
            return CLIAdapter(command: "opencode", argsTemplate: ["run", "--model", "$MODEL"])
        case .claudeCLI:
            return CLIAdapter(command: "claude", argsTemplate: ["-p", "--model", "$MODEL"])
        case .codexCLI:
            return CLIAdapter(command: "codex", argsTemplate: ["exec", "--skip-git-repo-check", "-m", "$MODEL", "-"])
        }
    }

    func gatewayFor(_ f: FeatureScope) -> (gateway: any LLMGateway, model: String, provider: LLMProvider)? {
        let p = provider(for: f)
        guard let g = gateway(for: p) else { return nil }
        return (g, model(for: f), p)
    }

    func options(for f: FeatureScope, verbose: Bool) -> LLMOptions {
        LLMOptions(model: model(for: f), maxTokens: verbose ? 600 : 150,
                   temperature: 0.3, outputLanguage: outputLanguage,
                   timeoutSec: 30)
    }

    var missingKeyHint: String? {
        let p = defaultProvider
        if let acct = ProviderCatalog.keyAccount(p),
           (KeychainStore.load(provider: acct) ?? "").isEmpty {
            return "Add your \(ProviderCatalog.displayName(p)) key in Settings → Providers."
        }
        return nil
    }
}
