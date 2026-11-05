import Foundation
import Combine

/// Query state for the hotkey panel. @MainActor so SwiftUI can observe directly.
///
/// Real collaborators are injected by ReCatchApp:
/// - transcriptProvider: meeting transcript window from SQLite (AudioCaptureManager)
/// - gatewayFor: provider + model per feature (AppSettings)
/// - logHandler: persist timestamp+size to llm_log (AudioCaptureManager)
@MainActor
final class PanelViewModel: ObservableObject {
    enum Mode: String, CaseIterable { case now, missed, ask }

    @Published var mode: Mode = .now
    @Published var windowSec: Int = 300
    @Published var question: String = ""
    @Published var result: String = ""
    @Published var asOf: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var verbose = false
    @Published var lastHeardMs: Int64?
    /// Empty-state explainer set on every run ("Start listening first" vs "no speech yet" vs downloading).
    @Published var emptyReason = "Start listening first — press Start listening in the menu, then ask again."

    var meetingActive: () -> Bool = { false }
    /// Engine phase without string-sniffing. Set by the app from WhisperKitEngine.phase.
    var enginePhase: () async -> TranscriptionPhase = { .idle }

    var transcriptProvider: (Int) -> String = { _ in "" }
    var gatewayFor: (FeatureScope) -> (gateway: any LLMGateway, model: String, provider: LLMProvider)? = { _ in nil }
    var optionsFor: (FeatureScope, Bool) -> LLMOptions = { _, _ in
        LLMOptions(model: "", maxTokens: 150, temperature: 0.3, outputLanguage: "English", timeoutSec: 30)
    }
    var logHandler: (String, String, Int, Int, Int) -> Void = { _, _, _, _, _ in }

    private var runTask: Task<Void, Never>?

    var scope: FeatureScope {
        switch mode {
        case .now: return .rightNow
        case .missed: return .missed
        case .ask: return .ask
        }
    }

    func run() {
        runTask?.cancel()
        runTask = Task { await execute() }
    }

    func retry() { run() }
    func cancel() {
        runTask?.cancel()
        isLoading = false
    }

    private func execute() async {
        errorMessage = nil
        emptyReason = ""
        result = ""
        isLoading = true
        defer { isLoading = false }

        let windowBackSec: Int
        switch mode {
        case .now: windowBackSec = 120
        case .missed: windowBackSec = windowSec
        case .ask: windowBackSec = 0 // whole meeting
        }
        let transcript = transcriptProvider(windowBackSec)
        let asOfDate = Date()
        asOf = Self.timeFmt.string(from: asOfDate)

        if !meetingActive() {
            emptyReason = "Not listening yet — press Start listening in the menu, then ask again."
            return
        }
        switch await enginePhase() {
        case .downloading:
            emptyReason = "Downloading model (first run, ~2 GB) — answers appear once it's ready."
        case .failed:
            emptyReason = "Transcription model failed to load (offline?). Check connection, then ask again."
        case .idle, .ready:
            break
        }

        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if emptyReason.isEmpty {
                emptyReason = "Listening, but no speech captured yet. Talk near the mic — if the menu level meter doesn't move, check Mic permission."
            }
            return
        }
        emptyReason = ""
        if mode == .ask, question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "Type a question first."
            return
        }
        guard let g = gatewayFor(scope) else {
            errorMessage = "No provider configured. Add a key in Settings → Providers."
            return
        }
        let opts = optionsFor(scope, verbose)
        let lang = opts.outputLanguage
        let prompt: String
        switch mode {
        case .now:
            prompt = Prompts.rightNow(transcript: transcript, outputLanguage: lang)
        case .missed:
            let label = windowSec >= 3600 ? "\(windowSec / 3600)h" : "\(windowSec / 60)m"
            prompt = Prompts.missed(window: "last \(label)", notes: "", transcript: transcript, outputLanguage: lang)
        case .ask:
            prompt = Prompts.ask(question: question, transcript: transcript, outputLanguage: lang)
        }

        do {
            var out = ""
            for try await token in g.gateway.stream(prompt: prompt, options: opts) {
                try Task.checkCancellation()
                out += token
                result = out
            }
            result = out
            let inTok = max(1, prompt.count / 4), outTok = max(1, out.count / 4)
            logHandler(g.provider.rawValue, opts.model, inTok, outTok, windowSec)
        } catch is CancellationError {
            // superseded by a newer run — leave partial text
        } catch {
            errorMessage = "Couldn't reach \(ProviderCatalog.displayName(g.provider)) (\(error.localizedDescription)). Check key / connection, then retry."
        }
    }

    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}

/// Shared instance: menu-bar apps have one panel and one global hotkey.
enum PanelSession {
    @MainActor static let shared = PanelViewModel()
}
