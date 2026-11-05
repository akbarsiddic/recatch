import SwiftUI

@main
struct ReCatchApp: App {
    @StateObject private var capture = AudioCaptureManager()
    @State private var showConsent = false
    @State private var consentOK = false

    var body: some Scene {
        MenuBarExtra("Radar", systemImage: icon) {
            Button(capture.state == .listening ? "Stop listening" : "Start listening") {
                if capture.state == .listening { Task { await capture.stopMeeting() } }
                else if consentOK { Task { await capture.startMeeting() } }
                else { showConsent = true }
            }
            Divider()
            Button("Delete everything now") { try? FileManager.default.removeItem(at: dbURL()) }
            Divider()
            SettingsLink(label: { Text("Settings…") })
            QuitButton()
        }
        .sheet(isPresented: $showConsent) {
            VStack(alignment: .leading, spacing: 12) {
                Text("You’re responsible for complying with local rules and letting participants know you’re transcribing.").font(.headline)
                Text("Audio stays on this Mac. Only transcript text is sent to your chosen LLM for the window you request.").font(.body)
                HStack { Spacer(); Button("Cancel") { showConsent = false }; Button("Start listening") { consentOK = true; showConsent = false; Task { await capture.startMeeting() } }.keyboardShortcut(.defaultAction) }
            }.padding(20).frame(width: 420)
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
