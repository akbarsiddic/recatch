import Foundation
import SwiftUI
import Combine

/// Live transcript buffer shared by the debug window, the overlay and the panel.
@MainActor
final class TranscriptFeed: ObservableObject {
    static let shared = TranscriptFeed()

    struct Line: Identifiable {
        let id: UUID
        let who: String
        let text: String
        let at: Date
    }

    @Published private(set) var lines: [Line] = []
    /// Last settled utterance.
    @Published private(set) var latest = ""
    /// The still-changing caption line (rolling preview). Empty between utterances.
    @Published private(set) var partial = ""
    @Published var status = "Waiting"

    func append(_ seg: TranscriptSegment) {
        let who = seg.stream == .mic ? "Me" : "Others"
        lines.append(Line(id: seg.id, who: who, text: seg.text, at: Date()))
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
        latest = seg.text
        status = "\(lines.count) lines"
    }

    /// What the overlay shows: the live partial while speaking, else the last settled line.
    var caption: String { partial.isEmpty ? latest : partial }

    func setPartial(_ line: String) {
        partial = line
    }

    func reset() {
        lines.removeAll()
        latest = ""
        partial = ""
        status = "Waiting"
    }
}

/// Everything that must exist the moment the app launches — not when a menu is opened.
@MainActor
enum AppWiring {
    private static var started = false
    private static var cancellables: Set<AnyCancellable> = []

    static func start() {
        guard !started else { return }
        started = true

        let capture = AudioCaptureManager.shared
        let settings = AppSettings.shared
        let ctx = QueryContext.shared

        ctx.transcriptProvider = { [capture] secs in capture.transcriptWindow(secondsBack: secs) }
        ctx.meetingActive = { [capture] in capture.state == .listening }
        ctx.enginePhase = { [capture] in await capture.enginePhase() }
        ctx.gatewayFor = { [settings] scope in settings.gatewayFor(scope) }
        ctx.optionsFor = { [settings] scope, verbose in settings.options(for: scope, verbose: verbose) }
        ctx.logHandler = { [capture] provider, model, tin, tout, win in
            capture.logLLM(provider: provider, model: model, tokensIn: tin, tokensOut: tout, windowSec: win)
        }
        ctx.settingsHint = { [settings] in settings.missingKeyHint }

        capture.onSegment = { seg in
            Task { @MainActor in
                TranscriptFeed.shared.append(seg)
                TranscriptFeed.shared.setPartial("")
            }
        }
        capture.onPartial = { line in
            TranscriptFeed.shared.setPartial(line)
        }
        // The capture manager must know which model and which language to expect.
        capture.quality = settings.transcriptionQuality
        capture.languageHint = settings.spokenLanguage.hint
        settings.objectWillChange
            .sink { _ in
                capture.quality = settings.transcriptionQuality
                capture.languageHint = settings.spokenLanguage.hint
            }
            .store(in: &cancellables)

        HotkeyPanelController.registerHotkey()
        OverlayController.shared.installIfEnabled(settings: settings)
        MeetingWatcher.shared.start(capture: capture, settings: settings)
    }
}
