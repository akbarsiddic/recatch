import Foundation

/// OpenAI-compatible adapter: covers Groq, OpenAI, DeepSeek, OpenRouter, OpenCode Zen,
/// Ollama, 9router and any custom endpoint with one class.
struct OpenAICompatibleAdapter: LLMGateway {
    let baseURL: URL
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
                    var req = URLRequest(url: baseURL.appendingPathComponent("chat/completions"))
                    req.httpMethod = "POST"
                    req.timeoutInterval = TimeInterval(max(10, options.timeoutSec))
                    let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !key.isEmpty, key != "ollama" {
                        req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                    }
                    req.addValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.addValue("ReCatch/1.0", forHTTPHeaderField: "HTTP-Referer")
                    var body: [String: Any] = [
                        "model": options.model,
                        "messages": [["role": "user", "content": prompt]],
                        "max_tokens": options.maxTokens,
                        "temperature": options.temperature,
                        "stream": true
                    ]
                    // Reasoning models (gpt-oss, deepseek-reasoner) spend tokens thinking first;
                    // without headroom the answer arrives empty.
                    if options.model.contains("reasoner") || options.model.contains("gpt-oss") {
                        // Reasoning models bill their thinking against max_tokens. Groq only
                        // accepts low/medium/high, so keep "low" and give the answer room.
                        body["reasoning_effort"] = "low"
                    }
                    req.httpBody = try JSONSerialization.data(withJSONObject: body)
                    let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                    if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
                        var detail = ""
                        for try await line in bytes.lines { detail += line; if detail.count > 400 { break } }
                        throw NSError(domain: "ReCatch", code: http.statusCode, userInfo: [
                            NSLocalizedDescriptionKey: Self.explain(http.statusCode, detail: detail)
                        ])
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
                            cont.yield(text) // reasoning/reasoning_content is deliberately dropped
                        }
                    }
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
        }
    }

    /// Turn an HTTP failure into something a human can act on.
    static func explain(_ status: Int, detail: String) -> String {
        switch status {
        case 401, 403: return "Key rejected (HTTP \(status)). Check it in Settings → Providers."
        case 404: return "Model or endpoint not found (HTTP 404). Check the model name."
        case 429: return "Rate limited (HTTP 429). Wait a moment or pick another model."
        case 400...499: return "Request rejected (HTTP \(status)). \(detail.prefix(160))"
        default: return "Provider error (HTTP \(status)). \(detail.prefix(160))"
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
                        throw NSError(domain: "ReCatch", code: http.statusCode, userInfo: [
                            NSLocalizedDescriptionKey: OpenAICompatibleAdapter.explain(http.statusCode, detail: "")
                        ])
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

/// CLI passthrough: `claude -p`, `opencode run`, `codex exec`, `gemini -p`, …
/// Prompt goes over stdin (never argv — avoids ps leak + ARG_MAX). Tmp file is 0600.
struct CLIAdapter: LLMGateway {
    let command: String
    let argsTemplate: [String]

    func complete(prompt: String, options: LLMOptions) async throws -> String {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("recatch-prompt-\(UUID().uuidString).txt")
        try prompt.write(to: tmp, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tmp.path)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let args = argsTemplate.map { $0.replacingOccurrences(of: "$MODEL", with: options.model) }
        let proc = Process()
        // GUI apps have a bare PATH; resolve the binary ourselves.
        if let resolved = ProviderCatalog.resolveExecutable(command) {
            proc.executableURL = URL(fileURLWithPath: resolved)
            proc.arguments = args
        } else {
            proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            proc.arguments = [command] + args
        }
        let stdin = Pipe(), stdout = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = FileHandle.nullDevice
        // Inherit a sane environment; CLIs read their own config from $HOME.
        proc.environment = ProcessInfo.processInfo.environment
        try proc.run()
        stdin.fileHandleForWriting.write(Data(prompt.utf8))
        try? stdin.fileHandleForWriting.close()

        let secs = max(30, options.timeoutSec)
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(secs)) {
            if proc.isRunning { proc.terminate() }
        }
        proc.waitUntilExit()
        let out = stdout.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0 else {
            throw NSError(domain: "ReCatch", code: Int(proc.terminationStatus), userInfo: [
                NSLocalizedDescriptionKey: "\(command) exited \(proc.terminationStatus)"
            ])
        }
        let text = String(data: out, encoding: .utf8) ?? ""
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NSError(domain: "ReCatch", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "\(command) returned nothing — it may need a login (run it once in Terminal)."
            ])
        }
        return text
    }

    func stream(prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { cont in
            Task {
                do { cont.yield(try await complete(prompt: prompt, options: options)); cont.finish() }
                catch { cont.finish(throwing: error) }
            }
        }
    }
}
