import Foundation

/// OpenAI-compatible adapter: covers OpenAI, OpenCode Zen, OpenRouter, Ollama with one class.
struct OpenAICompatibleAdapter: LLMGateway {
    let baseURL: URL
    let apiKey: String

    static func preset(_ p: LLMProvider) -> (url: String, keyHint: String) {
        switch p {
        case .openAI: return ("https://api.openai.com/v1", "sk-...")
        case .openCodeZen: return ("https://opencode.ai/zen/v1", "zen key")
        case .openRouter: return ("https://openrouter.ai/api/v1", "or key")
        case .ollama: return ("http://localhost:11434/v1", "ollama")
        default: return ("https://api.openai.com/v1", "")
        }
    }

    func complete(prompt: String, options: LLMOptions) async throws -> String {
        var out = ""
        for try await t in stream(prompt: prompt, options: options) { out += t }
        return out
    }

    func stream(prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            Task {
                do {
                    var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
                    req.httpMethod = "POST"
                    req.timeoutInterval = TimeInterval(max(10, options.timeoutSec))
                    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty, key != "ollama" {
                        req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }
                    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.addValue("ReCatch/1.0", forHTTPHeaderField: "HTTP-Referer")
                    let body: [String: Any] = [
                        "model": options.model,
                        "messages": [["role": "user", "content": prompt]],
                        "max_tokens": options.maxTokens,
                        "temperature": options.temperature,
                        "stream": true
                    ]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                        throw NSError(domain: "Radar", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "LLM HTTP \(http.statusCode)"])
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)
                        if payload == "[DONE]" { break }
                        if let d = payload.data(using: .utf8),
                           let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                           let choices = j["choices"] as? [[String: Any]],
                           let delta = choices.first?["delta"] as? [String: Any],
                           let text = delta["content"] as? String {
                            cont.yield(text)
                        }
                    }
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
        }
    }
}

/// Anthropic native adapter (x-api-key + /v1/messages SSE).
struct AnthropicAdapter: LLMGateway {
    let apiKey: String
    func complete(prompt: String, options: LLMOptions) async throws -> String {
        var out = ""
        for try await t in stream(prompt: prompt, options: options) { out += t }
        return out
    }
    func stream(prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            Task {
                do {
                    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    req.httpMethod = "POST"
                    req.timeoutInterval = TimeInterval(max(10, options.timeoutSec))
                    req.addValue(apiKey, forHTTPHeaderField: "x-api-key")
                    req.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
                    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    let parts = prompt.components(separatedBy: "\nTRANSCRIPT:\n")
                    let body: [String: Any] = ["model": options.model, "max_tokens": options.maxTokens,
                        "system": parts.first ?? "", "messages": [["role": "user", "content": parts.last ?? prompt]]]
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                        throw NSError(domain: "Radar", code: http.statusCode)
                    }
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: "), let d = line.dropFirst(6).data(using: .utf8),
                              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                              let delta = j["delta"] as? [String: Any], let text = delta["text"] as? String else { continue }
                        cont.yield(text)
                    }
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
        }
    }
}

/// CLI passthrough: opencode run / claude -p / codex exec. Opt-in, slow (~5-12s), Ask-only.
/// CLI passthrough via stdin (never argv — avoids ps leak + ARG_MAX). Tmp prompt file is 0600.
struct CLIAdapter: LLMGateway {
    let command: String
    let argsTemplate: [String] // "$MODEL" only; prompt goes via stdin

    func complete(prompt: String, options: LLMOptions) async throws -> String {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("mr-prompt-\(UUID().uuidString).txt")
        try prompt.write(to: tmp, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }
        let data = try Data(contentsOf: tmp)
        let args = argsTemplate.map { $0.replacingOccurrences(of: "$MODEL", with: options.model) }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = [command] + args
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        // Drain stderr to /dev/null path to avoid deadlock; keep stdout.
        proc.standardInput = stdin; proc.standardOutput = stdout; proc.standardError = stderr
        try proc.run()
        stdin.fileHandleForWriting.write(data); try? stdin.fileHandleForWriting.close()
        let secs = max(30, options.timeoutSec)
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(secs)) {
            if proc.isRunning { proc.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(3)) {
                if proc.isRunning { proc.interrupt() }
            }
        }
        proc.waitUntilExit()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "Radar", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: "CLI exited \(proc.terminationStatus)"])
        }
        return String(data: out, encoding: .utf8) ?? ""
    }

    func stream(prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            Task {
                do { cont.yield(try await complete(prompt: prompt, options: options)); cont.finish() }
                catch { cont.finish(throwing: error) }
            }
        }
    }

    static func opencode(model: String) -> CLIAdapter {
        CLIAdapter(command: "opencode", argsTemplate: ["run", "--model", "$MODEL"])
    }
    static func claudeCode(model: String) -> CLIAdapter {
        CLIAdapter(command: "claude", argsTemplate: ["-p", "--model", "$MODEL"])
    }
    static func codex(model: String) -> CLIAdapter {
        CLIAdapter(command: "codex", argsTemplate: ["exec", "--skip-git-repo-check", "-m", "$MODEL", "-"])
    }
}
