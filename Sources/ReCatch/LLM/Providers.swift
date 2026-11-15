import Foundation

/// Every brain ReCatch can use. One case per thing a person actually has:
/// an API key (Groq, OpenAI, DeepSeek, …) or a coding agent they already pay for (Claude Code, opencode, …).
enum LLMProvider: String, CaseIterable, Identifiable {
    // API keys
    case groq, openAI, anthropic, deepSeek, openRouter, openCodeZen, nineRouter, ollama, custom
    // Agents you already have installed
    case claudeCLI, opencodeCLI, codexCLI, geminiCLI, commandCodeCLI

    var id: String { rawValue }
}

enum ProviderKind {
    /// Anthropic Messages API (x-api-key + /v1/messages).
    case anthropic
    /// OpenAI /chat/completions — Groq, DeepSeek, OpenRouter, Ollama, 9router, any custom endpoint.
    case openAICompatible
    /// A local CLI that uses an existing subscription. Slow, Ask-only, $0.
    case cli
}

/// Everything static about a provider. Nothing here reads Keychain or the filesystem.
struct ProviderSpec {
    let provider: LLMProvider
    let name: String
    let kind: ProviderKind
    /// Default endpoint. nil for CLI providers.
    let baseURL: String?
    /// Keychain account name. nil = no key needed.
    let keyAccount: String?
    /// True when the endpoint works without a key (Ollama, 9router, self-hosted).
    let keyOptional: Bool
    let defaultModel: String
    /// Suggestions for the model field — not a whitelist, users can type any id.
    let models: [String]
    let cliCommand: String?
    let cliArgs: [String]?
    let note: String?

    var isCLI: Bool { kind == .cli }
}

enum ProviderCatalog {
    /// Ordered by "most likely to just work": fastest/free first, paid last.
    static let all: [ProviderSpec] = [
        ProviderSpec(
            provider: .groq, name: "Groq", kind: .openAICompatible,
            baseURL: "https://api.groq.com/openai/v1", keyAccount: "groq", keyOptional: false,
            defaultModel: "openai/gpt-oss-120b",
            models: ["openai/gpt-oss-120b", "openai/gpt-oss-20b", "qwen/qwen3.8-27b", "allam-2-7b"],
            cliCommand: nil, cliArgs: nil,
            note: "Fastest option — answers in well under a second. Free tier available."),
        ProviderSpec(
            provider: .openAI, name: "OpenAI", kind: .openAICompatible,
            baseURL: "https://api.openai.com/v1", keyAccount: "openai", keyOptional: false,
            defaultModel: "gpt-4o-mini",
            models: ["gpt-4o-mini", "gpt-4o", "gpt-5", "o4-mini"],
            cliCommand: nil, cliArgs: nil, note: nil),
        ProviderSpec(
            provider: .anthropic, name: "Anthropic", kind: .anthropic,
            baseURL: nil, keyAccount: "anthropic", keyOptional: false,
            defaultModel: "claude-sonnet-4-5",
            models: ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-1"],
            cliCommand: nil, cliArgs: nil, note: nil),
        ProviderSpec(
            provider: .deepSeek, name: "DeepSeek", kind: .openAICompatible,
            baseURL: "https://api.deepseek.com/v1", keyAccount: "deepseek", keyOptional: false,
            defaultModel: "deepseek-chat",
            models: ["deepseek-chat", "deepseek-reasoner"],
            cliCommand: nil, cliArgs: nil, note: "Cheap and good at mixed Indonesian/English."),
        ProviderSpec(
            provider: .openRouter, name: "OpenRouter", kind: .openAICompatible,
            baseURL: "https://openrouter.ai/api/v1", keyAccount: "openrouter", keyOptional: false,
            defaultModel: "anthropic/claude-sonnet-4",
            models: ["anthropic/claude-sonnet-4", "openai/gpt-4o-mini", "google/gemini-2.5-flash"],
            cliCommand: nil, cliArgs: nil, note: "One key, almost every model."),
        ProviderSpec(
            provider: .openCodeZen, name: "OpenCode Zen", kind: .openAICompatible,
            baseURL: "https://opencode.ai/zen/v1", keyAccount: "opencode-zen", keyOptional: false,
            defaultModel: "opencode-zen/ultracode",
            models: ["opencode-zen/ultracode"],
            cliCommand: nil, cliArgs: nil, note: nil),
        ProviderSpec(
            provider: .nineRouter, name: "9router", kind: .openAICompatible,
            baseURL: "http://localhost:20128/v1", keyAccount: "9router", keyOptional: true,
            defaultModel: "claude-sonnet-4",
            models: ["claude-sonnet-4", "gpt-5", "gemini-2.5-pro"],
            cliCommand: nil, cliArgs: nil,
            note: "Local router — run it with `npx 9router`, then it answers on port 20128. No key needed."),
        ProviderSpec(
            provider: .ollama, name: "Ollama (local)", kind: .openAICompatible,
            baseURL: "http://localhost:11434/v1", keyAccount: nil, keyOptional: true,
            defaultModel: "qwen2.5:7b",
            models: ["qwen2.5:7b", "llama3.2", "gemma3"],
            cliCommand: nil, cliArgs: nil, note: "Fully offline. Start it with `ollama serve`."),
        ProviderSpec(
            provider: .custom, name: "Custom endpoint", kind: .openAICompatible,
            baseURL: "", keyAccount: "custom", keyOptional: true,
            defaultModel: "",
            models: [],
            cliCommand: nil, cliArgs: nil,
            note: "Any OpenAI-compatible server. Paste its base URL, including /v1."),
        ProviderSpec(
            provider: .claudeCLI, name: "Claude Code", kind: .cli,
            baseURL: nil, keyAccount: nil, keyOptional: true,
            defaultModel: "sonnet",
            models: ["sonnet", "opus", "haiku"],
            cliCommand: "claude", cliArgs: ["-p", "--model", "$MODEL"],
            note: "Uses your Claude subscription — $0 extra, ~5–12s."),
        ProviderSpec(
            provider: .opencodeCLI, name: "opencode", kind: .cli,
            baseURL: nil, keyAccount: nil, keyOptional: true,
            defaultModel: "opencode-zen/ultracode",
            models: ["opencode-zen/ultracode"],
            cliCommand: "opencode", cliArgs: ["run", "--model", "$MODEL"],
            note: "Uses your opencode setup — $0 extra, slow."),
        ProviderSpec(
            provider: .codexCLI, name: "Codex", kind: .cli,
            baseURL: nil, keyAccount: nil, keyOptional: true,
            defaultModel: "gpt-5",
            models: ["gpt-5", "gpt-5-codex"],
            cliCommand: "codex", cliArgs: ["exec", "--skip-git-repo-check", "-m", "$MODEL", "-"],
            note: "Uses your ChatGPT plan — $0 extra, slow."),
        ProviderSpec(
            provider: .geminiCLI, name: "Gemini CLI", kind: .cli,
            baseURL: nil, keyAccount: nil, keyOptional: true,
            defaultModel: "gemini-2.5-pro",
            models: ["gemini-2.5-pro", "gemini-2.5-flash"],
            cliCommand: "gemini", cliArgs: ["-m", "$MODEL", "-p"],
            note: "Uses your Google account — $0 extra, slow."),
        ProviderSpec(
            provider: .commandCodeCLI, name: "Command Code", kind: .cli,
            baseURL: nil, keyAccount: nil, keyOptional: true,
            defaultModel: "",
            models: [],
            cliCommand: "command-code", cliArgs: ["-p"],
            note: "Set the exact command in Advanced if your binary has another name."),
    ]

    static func spec(_ p: LLMProvider) -> ProviderSpec {
        all.first { $0.provider == p } ?? all[0]
    }

    static func displayName(_ p: LLMProvider) -> String { spec(p).name }
    static func defaultModel(_ p: LLMProvider) -> String { spec(p).defaultModel }
    static func keyAccount(_ p: LLMProvider) -> String? { spec(p).keyAccount }
    static func slowNote(_ p: LLMProvider) -> String? { spec(p).note }

    // MARK: - Live status (reads Keychain + PATH; cheap)

    enum Readiness: Equatable {
        case ready
        case needsKey
        case cliMissing(String)
        case needsBaseURL
        case notRunning

        var isUsable: Bool { self == .ready }
        var label: String {
            switch self {
            case .ready: return "Ready"
            case .needsKey: return "Add key"
            case .cliMissing(let cmd): return "\(cmd) not found"
            case .needsBaseURL: return "Set URL"
            case .notRunning: return "Not running"
            }
        }
    }

    /// Can this provider answer right now, on this machine, with what's stored?
    static func readiness(_ p: LLMProvider, baseURLOverride: String = "") -> Readiness {
        let s = spec(p)
        if s.kind == .cli {
            guard let cmd = s.cliCommand else { return .cliMissing("?") }
            return executableExists(cmd) ? .ready : .cliMissing(cmd)
        }
        if p == .custom, baseURLOverride.trimmingCharacters(in: .whitespaces).isEmpty { return .needsBaseURL }
        if let acct = s.keyAccount, !s.keyOptional {
            let key = KeychainStore.load(provider: acct) ?? ""
            if key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .needsKey }
        }
        // A localhost endpoint (Ollama, 9router) is only ready if something is actually listening.
        let url = baseURLOverride.isEmpty ? (s.baseURL ?? "") : baseURLOverride
        if s.keyOptional, LocalEndpoint.isLoopback(url), !LocalEndpoint.isUp(url) {
            return .notRunning
        }
        return .ready
    }

    /// First provider that can actually answer — so a fresh install works without visiting Settings.
    static func firstReady(baseURLOverride: String = "") -> LLMProvider? {
        all.first { readiness($0.provider, baseURLOverride: $0.provider == .custom ? baseURLOverride : "").isUsable }?.provider
    }

    // MARK: - PATH lookup (no subprocess)

    /// GUI apps get a bare PATH, so search the places CLIs actually install to.
    static func executableExists(_ command: String) -> Bool {
        resolveExecutable(command) != nil
    }

    static func resolveExecutable(_ command: String) -> String? {
        if command.contains("/") {
            return FileManager.default.isExecutableFile(atPath: command) ? command : nil
        }
        let home = NSHomeDirectory()
        var dirs = [
            "\(home)/.opencode/bin", "\(home)/.local/bin", "\(home)/.bun/bin", "\(home)/.cargo/bin",
            "\(home)/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
        ]
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            dirs += path.split(separator: ":").map(String.init)
        }
        // nvm / fnm / volta install node CLIs deep inside versioned dirs.
        for base in ["\(home)/.nvm/versions/node", "\(home)/.fnm/node-versions", "\(home)/.volta/bin"] {
            if let versions = try? FileManager.default.contentsOfDirectory(atPath: base) {
                for v in versions {
                    dirs.append("\(base)/\(v)/bin")
                    dirs.append("\(base)/\(v)/installation/bin")
                }
            }
        }
        for dir in dirs {
            let full = dir.hasSuffix("/") ? dir + command : dir + "/" + command
            if FileManager.default.isExecutableFile(atPath: full) { return full }
        }
        return nil
    }
}

/// "Is the local server actually up?" — so Ollama/9router never claim to be ready when they aren't.
enum LocalEndpoint {
    private static var cache: [String: (up: Bool, at: Date)] = [:]

    static func isLoopback(_ url: String) -> Bool {
        guard let host = URL(string: url)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "0.0.0.0"
    }

    static func isUp(_ url: String) -> Bool {
        if let c = cache[url], Date().timeIntervalSince(c.at) < 15 { return c.up }
        let up = probe(url)
        cache[url] = (up, Date())
        return up
    }

    /// Non-blocking connect with a 300 ms ceiling. Loopback refuses instantly when nothing listens.
    private static func probe(_ url: String) -> Bool {
        guard let u = URL(string: url), let host = u.host else { return false }
        let port = u.port ?? (u.scheme == "https" ? 443 : 80)
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let addr = res else { return false }
        defer { freeaddrinfo(res) }
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, O_NONBLOCK)
        if connect(fd, addr.pointee.ai_addr, addr.pointee.ai_addrlen) == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, 300) > 0 else { return false }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0
    }
}
