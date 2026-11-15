import Foundation

/// The single place the answer path reads live state from. Filled once at launch by AppWiring,
/// read by both the hotkey panel and the overlay — no duplicated wiring, no string sniffing.
@MainActor
final class QueryContext {
    static let shared = QueryContext()

    var transcriptProvider: (Int) -> String = { _ in "" }
    var meetingActive: () -> Bool = { false }
    var enginePhase: () async -> TranscriptionPhase = { .idle }
    var gatewayFor: (FeatureScope) -> (gateway: any LLMGateway, model: String, provider: LLMProvider)? = { _ in nil }
    var optionsFor: (FeatureScope, Bool) -> LLMOptions = { _, _ in
        LLMOptions(model: "", maxTokens: 220, temperature: 0.3, outputLanguage: "English", timeoutSec: 30)
    }
    var logHandler: (String, String, Int, Int, Int) -> Void = { _, _, _, _, _ in }
    /// Human sentence explaining why nothing can answer (missing key / missing CLI).
    var settingsHint: () -> String? = { nil }
}

enum AnswerError: Error {
    /// Nothing to answer from — carries a sentence to show instead of an answer.
    case empty(String)
    /// Configuration/transport problem — carries an actionable sentence.
    case failure(String)
}

/// One answer, three modes. Shared by the hotkey panel and the overlay so they behave identically.
@MainActor
final class AnswerEngine {
    static let shared = AnswerEngine()

    struct Request {
        var mode: PanelMode
        var windowSec: Int = 300
        var question: String = ""
        var verbose: Bool = false
    }

    /// Timestamp of the transcript window that produced the last answer ("as of 14:32").
    private(set) var asOf = ""

    /// Streams tokens through `onToken` and returns the final text.
    func answer(_ r: Request, onToken: @MainActor @escaping (String) -> Void) async throws -> String {
        let ctx = QueryContext.shared
        asOf = Self.timeFmt.string(from: Date())

        let windowBackSec: Int
        switch r.mode {
        case .now: windowBackSec = 120
        case .missed: windowBackSec = r.windowSec
        case .ask: windowBackSec = 0
        }

        guard ctx.meetingActive() else {
            throw AnswerError.empty("Not listening yet. Start listening, then ask again.")
        }
        switch await ctx.enginePhase() {
        case .downloading:
            throw AnswerError.empty("Downloading the speech model (first run) — answers appear once it's ready.")
        case .failed:
            throw AnswerError.empty("Speech model failed to load. Check your connection, then ask again.")
        case .idle, .ready, .loading:
            break
        }

        let transcript = ctx.transcriptProvider(windowBackSec)
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AnswerError.empty("Listening, but nothing has been said yet.")
        }
        if r.mode == .ask, r.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AnswerError.failure("Type a question first.")
        }

        let scope = r.mode.scope
        guard let g = ctx.gatewayFor(scope) else {
            throw AnswerError.failure(ctx.settingsHint() ?? "No provider configured. Add a key in Settings → Providers.")
        }
        let opts = ctx.optionsFor(scope, r.verbose)
        let lang = opts.outputLanguage
        let prompt: String
        switch r.mode {
        case .now:
            prompt = Prompts.rightNow(transcript: transcript, outputLanguage: lang)
        case .missed:
            let label = r.windowSec >= 3600 ? "\(r.windowSec / 3600)h" : "\(r.windowSec / 60)m"
            prompt = Prompts.missed(window: "last \(label)", notes: "", transcript: transcript, outputLanguage: lang)
        case .ask:
            prompt = Prompts.ask(question: r.question, transcript: transcript, outputLanguage: lang)
        }

        var out = ""
        do {
            for try await token in g.gateway.stream(prompt: prompt, options: opts) {
                try Task.checkCancellation()
                out += token
                onToken(out)
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AnswerError.failure("Couldn't reach \(ProviderCatalog.displayName(g.provider)): \(error.localizedDescription)")
        }
        let inTok = max(1, prompt.count / 4), outTok = max(1, out.count / 4)
        ctx.logHandler(g.provider.rawValue, opts.model, inTok, outTok, r.windowSec)
        return out
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}

/// What the panel asks for. Lives here so AnswerEngine and the views agree.
enum PanelMode: String, CaseIterable {
    case now, missed, ask

    var scope: FeatureScope {
        switch self {
        case .now: return .rightNow
        case .missed: return .missed
        case .ask: return .ask
        }
    }
}
