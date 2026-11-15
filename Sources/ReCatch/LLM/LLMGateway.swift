import Foundation

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

// Provider enum + catalog live in Providers.swift.
