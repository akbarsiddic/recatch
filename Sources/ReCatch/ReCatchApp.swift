import SwiftUI
import AppKit

@main
struct ReCatchApp: App {
    @StateObject private var capture = AudioCaptureManager()
    @State private var showConsent = false
    @State private var consentOK = false

    var body: some Scene {
        MenuBarExtra("Radar", systemImage: icon) {
            if showConsent {
                Text("You're responsible for complying with local rules and letting participants know you're transcribing.").font(.headline)
                Text("Audio stays on this Mac. Only transcript text is sent to your chosen LLM for the window you request.").font(.body)
                Button("Start listening") { consentOK = true; showConsent = false; Task { await capture.startMeeting() } }
                Button("Cancel") { showConsent = false }
            } else {
                Button(capture.state == .listening ? "Stop listening" : "Start listening") {
                    if capture.state == .listening { Task { await capture.stopMeeting() } }
                    else if consentOK { Task { await capture.startMeeting() } }
                    else { showConsent = true }
                }
                Divider()
                Button("Delete everything now") { try? FileManager.default.removeItem(at: dbURL()) }
                Divider()
                SettingsLink(label: { Text("Settings…") })
                Button("Quit ReCatch") { NSApplication.shared.terminate(nil) }
            }
        }
        Settings { SettingsView() }
    }

    var icon: String {
        switch capture.state {
        case .listening: return "waveform"
        case .paused: return "pause.circle"
        case .error: return "exclamationmark.triangle"
        default: return "dot.radiowaves.left.and.right"
        }
    }

    func dbURL() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReCatch.sqlite")
    }
}

struct SettingsView: View {
    var body: some View {
        TabView {
            Form { Text("Hotkey, overlay, live-Now toggle go here.") }.tabItem { Text("General") }
            Form { Text("Provider picker: Anthropic / OpenAI / Zen / Ollama / opencode CLI. Keys in Keychain.") }.tabItem { Text("Providers") }
            Form { Text("What leaves my machine: llm_log timestamp + size.") }.tabItem { Text("Privacy") }
        }.frame(width: 480, height: 320)
    }
}
