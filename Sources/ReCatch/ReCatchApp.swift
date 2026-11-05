import SwiftUI
import AppKit

@main
struct ReCatchApp: App {
    @StateObject private var capture = AudioCaptureManager()
    @StateObject private var settings = AppSettings()
    @State private var showConsent = false
    @State private var consentOK = false
    @State private var debugLines: [(id: UUID, who: String, text: String)] = []
    @State private var wired = false
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("ReCatch", systemImage: icon) {
            menuContent
                .onAppear {
                    guard !wired else { return }
                    wired = true
                    wirePanel()
                    HotkeyPanelController.registerHotkey()
                }
        }
        Settings {
            SettingsView(settings: settings, capture: capture)
        }
        Window("Debug transcripts", id: "debug") {
            DebugTranscriptView(
                lines: debugLines,
                status: "\(capture.chunkCount) chunks · \(capture.segmentCount) segments · \(capture.modelLine)"
            )
        }
        .defaultSize(width: 600, height: 380)
    }

    @ViewBuilder
    private var menuContent: some View {
        if showConsent {
            consentView
        } else {
            statusSection
            Divider()
            Button(capture.state == .listening ? "Stop listening" : "Start listening") {
                if capture.state == .listening { Task { await capture.stopMeeting() } }
                else if consentOK { Task { await capture.startMeeting() } }
                else { showConsent = true }
            }
            .keyboardShortcut("l", modifiers: [.option, .command])
            Button("Ask ReCatch… (⌥⌘R)") {
                Task { @MainActor in HotkeyPanelController.summon() }
            }.disabled(capture.state != .listening)
            Button("Live transcript…") { openWindow(id: "debug") }
            Divider()
            Button("Delete everything now") {
                try? FileManager.default.removeItem(at: dbURL())
                if capture.state == .listening { Task { await capture.stopMeeting() } }
            }
            Divider()
            SettingsLink(label: { Text("Settings…") })
            Button("Quit ReCatch") { NSApplication.shared.terminate(nil) }
        }
    }

    private var consentView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.circle.fill").foregroundStyle(Brand.accent)
                Text(Brand.name).bold()
            }
            Text("You're responsible for complying with local rules and letting participants know you're transcribing.")
            Text("Audio stays on this Mac. Only transcript text is sent to your chosen LLM for the window you request.")
                .foregroundColor(.secondary)
            HStack {
                Button("Cancel") { showConsent = false }
                Button("Start listening") { consentOK = true; showConsent = false; Task { await capture.startMeeting() } }
            }
        }.padding(4).frame(width: 300)
    }

    @ViewBuilder
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(statusColor).frame(width: 8, height: 8)
                Text(statusTitle).bold()
                Spacer()
            }
            if capture.state == .listening {
                HStack {
                    LevelMeter(level: capture.level)
                    Text(capture.heardLine).font(.caption).foregroundColor(.secondary)
                }
                Text(capture.modelLine).font(.caption).foregroundColor(.secondary)
            } else if case .error(let m) = capture.state {
                Text(m).font(.caption).foregroundColor(Brand.bad).frame(width: 300)
            } else {
                Text("Join a Meet, then Start listening.").font(.caption).foregroundColor(.secondary)
            }
        }.padding(.vertical, 2)
    }

    private var statusTitle: String { AppStateDisplay.meta(for: capture.state).title }
    private var statusColor: Color { AppStateDisplay.meta(for: capture.state).color }
    private var icon: String { AppStateDisplay.meta(for: capture.state).icon }

    /// Wire the shared panel to the live meeting exactly once per appearance.
    private func wirePanel() {
        Task { @MainActor in
            PanelSession.shared.transcriptProvider = { [capture] secs in
                capture.transcriptWindow(secondsBack: secs)
            }
            PanelSession.shared.meetingActive = { [capture] in capture.state == .listening }
            PanelSession.shared.enginePhase = { [capture] in await capture.enginePhase() }
            PanelSession.shared.gatewayFor = { [settings] scope in
                settings.gatewayFor(scope)
            }
            PanelSession.shared.optionsFor = { [settings] scope, verbose in
                settings.options(for: scope, verbose: verbose)
            }
            PanelSession.shared.logHandler = { [capture] provider, model, tin, tout, win in
                capture.logLLM(provider: provider, model: model, tokensIn: tin, tokensOut: tout, windowSec: win)
            }
            capture.onSegment = { [weak capture] seg in
                guard capture != nil else { return }
                Task { @MainActor in
                    let who = seg.stream == .mic ? "Me" : "Others"
                    debugLines.append((seg.id, who, seg.text))
                    if debugLines.count > 200 { debugLines.removeFirst(debugLines.count - 200) }
                }
            }
        }
    }

    private func dbURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReCatch.sqlite")
    }
}

/// Single switch mapping AppState → menu display (title, color, icon).
/// Collapses the old title/color/icon switch trio (was: Repeated Switches).
enum AppStateDisplay {
    static func meta(for state: AppState) -> (title: String, color: Color, icon: String) {
        switch state {
        case .idle: return (Brand.name, .gray, "dot.radiowaves.left.and.right")
        case .requestingPermissions: return ("Requesting access…", Brand.warn, "dot.radiowaves.left.and.right")
        case .listening: return ("Listening", Brand.ok, "waveform.circle.fill")
        case .paused: return ("Paused", Brand.warn, "pause.circle")
        case .error: return ("Needs attention", Brand.bad, "exclamationmark.triangle.fill")
        }
    }
}
