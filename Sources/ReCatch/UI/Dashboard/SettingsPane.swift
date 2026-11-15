import SwiftUI

/// Settings, in the dashboard rather than a separate window (that window never came forward).
struct SettingsPane: View {
    @Binding var showOnboarding: Bool
    @StateObject private var settings = AppSettings.shared
    @StateObject private var capture = AudioCaptureManager.shared
    @State private var micOK = PermissionsManager.micGranted()
    @State private var audioOK = PermissionsManager.audioRecordingGranted()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PaneHeader(title: "Settings", subtitle: "Meeting language, speech model, and access.")
                languageCard
                modelCard
                listeningCard
                permissionsCard
                PaneCard(title: "Setup") {
                    HStack {
                        Text("Walk through the first-run steps again.").font(.callout)
                        Spacer()
                        Button("Run setup again") { showOnboarding = true }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: Language

    private var languageCard: some View {
        PaneCard(title: "Meeting language") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Picker("", selection: $settings.spokenLanguage) {
                        ForEach(SpokenLanguage.allCases) { l in
                            Text(l.title).tag(l)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(width: 200)
                    Spacer()
                }

                Text(settings.spokenLanguage == .auto
                     ? "Detected once from the first ~25 seconds, then locked for the whole meeting. You can override it any time from the overlay."
                     : "Always used as the starting language. Answers still come back in this language — ReCatch does not translate.")
                    .font(.caption).foregroundColor(.secondary)

                if let detected = capture.detectedLanguageTitle {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(Brand.ok)
                        Text("This meeting: \(detected)").font(.caption).bold()
                    }
                }
            }
        }
    }

    // MARK: Model

    private var modelCard: some View {
        PaneCard(title: "Speech model") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(TranscriptionQuality.allCases) { q in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: settings.transcriptionQuality == q
                              ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(settings.transcriptionQuality == q ? Brand.accent : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(q.title).font(.callout).bold()
                                Text(q.approxSize).font(.caption2).foregroundColor(.secondary)
                                if capture.quality == q, capture.modelPhase == .ready {
                                    ReadinessPill(text: "downloaded", tone: Brand.ok)
                                }
                            }
                            Text(q.subtitle).font(.caption).foregroundColor(.secondary)
                            Text(q.note).font(.caption2).foregroundColor(.secondary)
                        }
                        Spacer()
                        if settings.transcriptionQuality != q {
                            Button(capture.quality == q && capture.modelPhase == .ready ? "Use" : "Download & use") {
                                settings.transcriptionQuality = q
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { settings.transcriptionQuality = q }
                }

                if capture.modelPhase == .downloading || capture.modelPhase == .loading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: capture.modelProgress)
                        Text(capture.modelLine).font(.caption2).foregroundColor(.secondary)
                    }
                } else if capture.modelPhase == .failed {
                    HStack(spacing: 8) {
                        Label(capture.modelLine, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(Brand.bad)
                        Spacer()
                        Button("Retry") { Task { await capture.retryModel() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    Text(capture.modelLine).font(.caption2).foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: Listening

    private var listeningCard: some View {
        PaneCard(title: "Listening") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle("Start automatically when a meeting takes the mic", isOn: $settings.autoListen)
                    .tint(Brand.accent)
                Toggle("Show the floating overlay while listening", isOn: $settings.overlayEnabled)
                    .tint(Brand.accent)
                Text("Automatic start backs off for a minute after you stop manually.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Permissions

    private var permissionsCard: some View {
        PaneCard(title: "Access") {
            VStack(alignment: .leading, spacing: 10) {
                permissionRow("Microphone", ok: micOK, why: "Needed to hear you.",
                              fix: { PermissionsManager.openMicSettings() })
                permissionRow("Audio recording", ok: audioOK, why: "Hears other people through system audio. No screen recording needed.",
                              fix: { PermissionsManager.openAudioSettings() })
                Button("Check again") {
                    micOK = PermissionsManager.micGranted()
                    audioOK = PermissionsManager.audioRecordingGranted()
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func permissionRow(_ title: String, ok: Bool, why: String, fix: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ok ? Brand.ok : Brand.bad)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout).bold()
                Text(why).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if !ok {
                Button("Open System Settings", action: fix).buttonStyle(.bordered)
            }
        }
    }
}
