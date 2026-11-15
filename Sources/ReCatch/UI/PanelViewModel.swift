import Foundation
import Combine

/// Query state for the hotkey panel. Thin: all the work lives in AnswerEngine.
@MainActor
final class PanelViewModel: ObservableObject {
    typealias Mode = PanelMode

    @Published var mode: Mode = .now
    @Published var windowSec: Int = 300
    @Published var question: String = ""
    @Published var result: String = ""
    @Published var asOf: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var verbose = false
    /// Empty-state explainer set on every run ("not listening" vs "nothing said yet" vs downloading).
    @Published var emptyReason = ""

    private var runTask: Task<Void, Never>?

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

        let req = AnswerEngine.Request(mode: mode, windowSec: windowSec, question: question, verbose: verbose)
        do {
            _ = try await AnswerEngine.shared.answer(req) { [weak self] text in
                self?.result = text
            }
            asOf = AnswerEngine.shared.asOf
        } catch is CancellationError {
            // superseded by a newer run — leave partial text
        } catch let e as AnswerError {
            switch e {
            case .empty(let reason): emptyReason = reason
            case .failure(let message): errorMessage = message
            }
        } catch {
            errorMessage = "Something went wrong: \(error.localizedDescription)"
        }
    }
}

/// Shared instance: menu-bar apps have one panel and one global hotkey.
enum PanelSession {
    @MainActor static let shared = PanelViewModel()
}
