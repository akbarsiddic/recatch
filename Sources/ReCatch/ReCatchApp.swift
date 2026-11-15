import SwiftUI
import AppKit

/// Launch-time work. Menu-bar apps must be live before any menu is opened:
/// the old wiring lived in MenuBarExtra's `.onAppear`, which is why a cold start had no hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppWiring.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        OverlayController.shared.rememberPosition()
    }
}

@main
struct ReCatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var capture = AudioCaptureManager.shared
    @StateObject private var settings = AppSettings.shared
    @State private var showConsent = false
    @State private var consentOK = false
    @Environment(\.openWindow) private var openWindow

    init() { SelfTest.runIfRequested() }

    var body: some Scene {
        MenuBarExtra("ReCatch", systemImage: icon) {
            menuContent
        }
        Settings {
            SettingsView(settings: settings, capture: capture)
        }
        Window("Live transcript", id: "debug") {
            DebugTranscriptView(
                lines: TranscriptFeed.shared.lines.map { (id: $0.id, who: $0.who, text: $0.text) },
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
                if capture.state == .listening {
                    MeetingWatcher.shared.noteManualStop()
                    Task { await capture.stopMeeting() }
                } else if consentOK {
                    Task { await capture.startMeeting() }
                } else {
                    showConsent = true
                }
            }
            .keyboardShortcut("l", modifiers: [.option, .command])
            Button("Ask ReCatch… (⌥⌘R)") {
                Task { @MainActor in HotkeyPanelController.summon() }
            }
            Button(settings.overlayEnabled ? "Hide overlay" : "Show overlay") {
                OverlayController.shared.toggle()
            }
            Button("Live transcript…") { openWindow(id: "debug") }
            Divider()
            Button("Delete everything now") {
                try? FileManager.default.removeItem(at: dbURL())
                TranscriptFeed.shared.reset()
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
            Text("Audio stays on this Mac. Only transcript text is sent to your chosen provider for the window you request.")
                .foregroundColor(.secondary)
            HStack {
                Button("Cancel") { showConsent = false }
                Button("Start listening") {
                    consentOK = true
                    showConsent = false
                    Task { await capture.startMeeting() }
                }
            }
        }.padding(4).frame(width: 320)
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
                if let note = capture.systemNote {
                    Text(note).font(.caption2).foregroundColor(.secondary).frame(width: 300, alignment: .leading)
                }
            } else if case .error(let m) = capture.state {
                Text(m).font(.caption).foregroundColor(Brand.bad).frame(width: 320, alignment: .leading)
            } else {
                Text("Join a meeting — ReCatch starts listening by itself.")
                    .font(.caption).foregroundColor(.secondary).frame(width: 300, alignment: .leading)
            }
            Text(providerLine).font(.caption2).foregroundColor(.secondary)
        }.padding(.vertical, 2)
    }

    /// Which brain will answer — visible without opening Settings.
    private var providerLine: String {
        guard let p = settings.effectiveProvider(for: .rightNow) else {
            return settings.missingKeyHint ?? "No provider ready"
        }
        return "Answering with \(ProviderCatalog.displayName(p)) · \(settings.model(for: .rightNow))"
    }

    private var statusTitle: String { AppStateDisplay.meta(for: capture.state).title }
    private var statusColor: Color { AppStateDisplay.meta(for: capture.state).color }
    private var icon: String { AppStateDisplay.meta(for: capture.state).icon }

    private func dbURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReCatch.sqlite")
    }
}

/// Single switch mapping AppState → menu display (title, color, icon).
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
