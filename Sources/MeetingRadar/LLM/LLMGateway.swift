import Foundation

enum LLMFormat { case text, json }

struct LLMOptions {
    var model: String
    var maxTokens: Int
    var temperature: Double
    var outputLanguage: String
    var timeoutSec: Int
}

protocol LLMGateway {
    func complete(prompt: String, options: LLMOptions) async throws -> String
    func stream(prompt: String, options: LLMOptions) -> AsyncThrowingStream<String, Error>
}

enum LLMProvider: String, CaseIterable {
    case anthropic, openAI, openCodeZen, openRouter, ollama
    case opencodeCLI, claudeCLI, codexCLI
}
