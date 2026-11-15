import SwiftUI
import Combine

/// At-a-glance status: is it listening, is the model ready, who answers, what's stored.
struct OverviewPane: View {
    @Binding var pane: DashboardView.Pane
    @StateObject private var capture = AudioCaptureManager.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var feed = TranscriptFeed.shared
    @StateObject private var stats = StatsStore()
    @StateObject private var overlay = OverlayController.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                statusCard
                HStack(alignment: .top, spacing: 16) {
                    liveCard
                    statsCard
                }
                setupCard
            }
            .padding(20)
        }
        .onAppear { stats.refresh() }
        .onReceive(feed.$lines) { _ in stats.refresh() }
    }

    // MARK: Status

    private var statusCard: some View {
        PaneCard {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(capture.state == .listening ? "Listening" : "Idle")
                            .font(.title3).bold()
                        if capture.state == .listening {
                            LevelMeter(level: capture.level)
                        }
                    }
                    Text(capture.state == .listening
                         ? (capture.heardLine == "Nothing heard yet" ? "Waiting for speech…" : "Hearing you now")
                         : "ReCatch starts by itself when a meeting takes the mic.")
                        .font(.callout).foregroundColor(.secondary)
                    if let note = capture.systemNote, capture.state == .listening {
                        Label(note, systemImage: "speaker.slash")
                            .font(.caption).foregroundColor(Brand.warn)
                    }
                    if case .error(let message) = capture.state {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(Brand.bad)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    statusRow("Speech model", modelText, tone: modelTone)
                    statusRow("Answering with", providerText, tone: providerTone)
                    statusRow("Meeting language", capture.detectedLanguageTitle ?? settings.spokenLanguage.title,
                              tone: .secondary)
                }
                .frame(width: 260, alignment: .trailing)
            }
        }
    }

    private func statusRow(_ label: String, _ value: String, tone: Color) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.caption).bold().foregroundColor(tone).lineLimit(1)
        }
    }

    private var modelText: String {
        switch capture.modelPhase {
        case .ready: return "Ready"
        case .downloading: return "Downloading \(Int(capture.modelProgress * 100))%"
        case .loading: return "Loading…"
        case .failed: return "Failed — retry in Settings"
        case .idle: return settings.transcriptionQuality.title
        }
    }
    private var modelTone: Color {
        switch capture.modelPhase {
        case .ready: return Brand.ok
        case .failed: return Brand.bad
        case .idle: return .secondary
        default: return Brand.warn
        }
    }
    private var providerText: String {
        settings.effectiveProvider(for: .rightNow).map { ProviderCatalog.displayName($0) }
            ?? (settings.missingKeyHint ?? "None ready")
    }
    private var providerTone: Color {
        settings.effectiveProvider(for: .rightNow) == nil ? Brand.warn : .primary
    }

    // MARK: Live caption

    private var liveCard: some View {
        PaneCard(title: "Live caption", trailing: AnyView(
            Text(capture.state == .listening ? "LIVE" : "OFF")
                .font(.caption2).bold()
                .foregroundColor(capture.state == .listening ? Brand.ok : .secondary)
        )) {
            VStack(alignment: .leading, spacing: 10) {
                Text(feed.caption.isEmpty ? "Nothing yet." : feed.caption)
                    .font(.body)
                    .foregroundColor(feed.caption.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .lineLimit(6)
                    .animation(.easeOut(duration: 0.15), value: feed.caption)
                Divider()
                HStack(spacing: 14) {
                    Label("\(capture.segmentCount) lines", systemImage: "text.alignleft")
                    Label("\(capture.chunkCount) windows", systemImage: "waveform.path")
                    Spacer()
                }
                .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    Button("Open transcript") { pane = .meetings }
                        .buttonStyle(.bordered)
                    Button(overlay.isVisible ? "Hide overlay" : "Show overlay") {
                        settings.overlayEnabled.toggle()
                        overlay.toggle()
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Today

    private var statsCard: some View {
        PaneCard(title: "Today") {
            VStack(alignment: .leading, spacing: 12) {
                metric("Meetings", "\(stats.todayCount)")
                metric("Transcribed lines", "\(stats.todayLines)")
                metric("Storage", stats.storageText)
                Divider()
                HStack {
                    Text("Kept for \(settings.retentionDays) days").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    BrandLink(title: "Privacy") { pane = .privacy }
                }
            }
        }
        .frame(width: 280)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.callout).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.callout).bold().monospacedDigit()
        }
    }

    // MARK: Setup nudges

    @ViewBuilder
    private var setupCard: some View {
        let missing = setupGaps
        if !missing.isEmpty {
            PaneCard(title: "Finish setting up") {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(missing, id: \.text) { gap in
                        HStack(spacing: 8) {
                            Image(systemName: "circle.dashed").foregroundColor(Brand.warn)
                            Text(gap.text).font(.callout)
                            Spacer()
                            BrandLink(title: gap.action) { pane = gap.pane }
                        }
                    }
                }
            }
        }
    }

    private var setupGaps: [(text: String, action: String, pane: DashboardView.Pane)] {
        var gaps: [(String, String, DashboardView.Pane)] = []
        if settings.effectiveProvider(for: .rightNow) == nil {
            gaps.append(("No provider can answer yet.", "Add key", .providers))
        }
        if capture.modelPhase == .failed {
            gaps.append(("Speech model failed to load.", "Fix", .settings))
        }
        if !PermissionsManager.micGranted() {
            gaps.append(("Microphone access is off.", "Open", .settings))
        }
        return gaps
    }
}

/// Reads the SQLite store off the UI path and republishes numbers the panes show.
@MainActor
final class StatsStore: ObservableObject {
    @Published var todayCount = 0
    @Published var todayLines = 0
    @Published var storageText = "—"

    private var lastLoad = Date.distantPast

    func refresh(force: Bool = false) {
        // Cheap throttle: transcript lines arrive several times a second.
        guard force || Date().timeIntervalSince(lastLoad) > 2 else { return }
        lastLoad = Date()
        guard let store = try? MeetingStore(path: AudioCaptureManager.defaultDBPath()) else { return }
        let meetings = (try? store.listMeetings(limit: 500)) ?? []
        let cal = Calendar.current
        let today = meetings.filter { cal.isDateInToday($0.startedAt) }
        todayCount = today.count
        todayLines = today.reduce(0) { $0 + $1.segments }
        storageText = ByteCountFormatter.string(fromByteCount: store.storageBytes(), countStyle: .file)
    }
}
