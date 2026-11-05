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
            DebugTranscriptView(lines: debugLines)
                .onReceive(capture.$state) { _ in }
        }
        .defaultSize(width: 560, height: 360)
    }

    @ViewBuilder
    private var menuContent: some View {
        if showConsent {
            Text("You're responsible for complying with local rules and letting participants know you're transcribing.").font(.headline)
            Text("Audio stays on this Mac. Only transcript text is sent to your chosen LLM for the window you request.").font(.body)
            Button("Start listening") { consentOK = true; showConsent = false; Task { await capture.startMeeting() } }
            Button("Cancel") { showConsent = false }
        } else {
            Text(statusLine).font(.caption).foregroundColor(.secondary)
            Button(capture.state == .listening ? "Stop listening" : "Start listening") {
                if capture.state == .listening { Task { await capture.stopMeeting() } }
                else if consentOK { Task { await capture.startMeeting() } }
                else { showConsent = true }
            }
            Button("Show panel (⌥⌘R)") {
                Task { @MainActor in HotkeyPanelController.summon() }
            }.disabled(capture.state != .listening)
            Divider()
            Button("Delete everything now") { try? FileManager.default.removeItem(at: dbURL()) }
            Divider()
            SettingsLink(label: { Text("Settings…") })
            Button("Quit ReCatch") { NSApplication.shared.terminate(nil) }
        }
    }

    private var statusLine: String {
        switch capture.state {
        case .idle: return "Idle — join a Meet, then Start listening."
        case .requestingPermissions: return "Requesting mic / screen access…"
        case .listening: return "Listening — ⌥⌘R for answers."
        case .paused: return "Paused."
        case .error(let m): return m
        }
    }

    private var icon: String {
        switch capture.state {
        case .listening: return "waveform"
        case .paused: return "pause.circle"
        case .error: return "exclamationmark.triangle"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    /// Wire the shared panel to the live meeting exactly once per appearance.
    private func wirePanel() {
        Task { @MainActor in
            PanelSession.shared.transcriptProvider = { [capture] secs in
                capture.transcriptWindow(secondsBack: secs)
            }
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
