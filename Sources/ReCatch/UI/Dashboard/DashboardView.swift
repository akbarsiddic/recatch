import SwiftUI

/// Docker-Desktop-shaped shell: sidebar of panes, one detail area, live status always visible.
struct DashboardView: View {
    @StateObject private var capture = AudioCaptureManager.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var overlay = OverlayController.shared
    @StateObject private var router = DashboardRouter.shared
    @State private var showOnboarding =
        ProcessInfo.processInfo.environment["RECATCH_SKIP_ONBOARDING"] == nil && !AppSettings.shared.onboarded

    /// RECATCH_PANE lets the screenshot/self-test harness open a specific pane.
    static var initialPane: Pane {
        guard let raw = ProcessInfo.processInfo.environment["RECATCH_PANE"] else { return .overview }
        return Pane(rawValue: raw) ?? .overview
    }

    enum Pane: String, CaseIterable, Identifiable {
        case overview, ask, meetings, providers, settings, privacy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .overview: return "Overview"
            case .ask: return "Ask"
            case .meetings: return "Meetings"
            case .providers: return "Providers"
            case .settings: return "Settings"
            case .privacy: return "Privacy"
            }
        }
        var icon: String {
            switch self {
            case .overview: return "gauge.with.dots.needle.bottom.50percent"
            case .ask: return "questionmark.bubble"
            case .meetings: return "list.bullet.rectangle"
            case .providers: return "cpu"
            case .settings: return "slider.horizontal.3"
            case .privacy: return "lock.shield"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                topBar
                Divider()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .frame(minWidth: 880, minHeight: 600)
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
                .interactiveDismissDisabled()
        }
        .onReceive(NotificationCenter.default.publisher(for: .recatchOpenSettings)) { _ in
            router.pane = .settings
        }
        .onAppear { if router.pane == .overview { router.pane = DashboardView.initialPane } }
    }

    /// Explicit sidebar instead of NavigationSplitView: the system sidebar is a vibrancy view
    /// that renders blank over a dark window and cannot be captured. This one is plain SwiftUI,
    /// so what you see is what is drawn.
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Pane.allCases) { p in
                Button {
                    router.pane = p
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: p.icon)
                            .font(.system(size: 13, weight: .medium))
                            .frame(width: 18)
                        Text(p.title).font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(router.pane == p ? Brand.accent.opacity(0.16) : Color.clear)
                    .foregroundStyle(router.pane == p ? Brand.accent : Color.primary)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Divider()
            HStack(spacing: 6) {
                BrandMark(size: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(Brand.name).font(.caption).bold()
                    Text(version).font(.system(size: 9)).foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .frame(width: 190)
        .background(Brand.surface)
    }

    private var version: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
        return "Version \(v)"
    }

    // MARK: - Top bar: state, model, provider, primary action

    private var topBar: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppStateDisplay.meta(for: capture.state).color)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(AppStateDisplay.meta(for: capture.state).title).font(.headline).lineLimit(1)
                Text(subtitle).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(0)
            if capture.state == .listening {
                LevelMeter(level: capture.level)
            }
            Button {
                Task { @MainActor in
                    if capture.state == .listening {
                        MeetingWatcher.shared.noteManualStop()
                        await capture.stopMeeting()
                    } else {
                        await capture.startMeeting()
                    }
                }
            } label: {
                Label(capture.state == .listening ? "Stop listening" : "Start listening",
                      systemImage: capture.state == .listening ? "stop.fill" : "waveform")
                    .frame(minWidth: 118)
            }
            .buttonStyle(.borderedProminent)
            .tint(capture.state == .listening ? Brand.bad : Brand.accent)
            .keyboardShortcut("l", modifiers: [.option, .command])

            languageMenu

            Button {
                router.pane = .ask
            } label: {
                Label("Ask", systemImage: "questionmark.bubble")
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(Brand.raised)
    }

    /// The language chip: always visible, one click to change, remembered for next time.
    private var languageMenu: some View {
        Menu {
            ForEach(SpokenLanguage.allCases) { l in
                Button {
                    capture.applyLanguage(l)
                } label: {
                    if l == settings.spokenLanguage {
                        Label(l.title, systemImage: "checkmark")
                    } else {
                        Text(l.title)
                    }
                }
            }
            Divider()
            Text("Auto learns from the first paragraphs and remembers it.")
        } label: {
            Label(capture.detectedLanguageTitle ?? settings.spokenLanguage.title,
                  systemImage: "globe")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Meeting language — click to change")
    }

    private var subtitle: String {
        switch capture.state {
        case .listening:
            let who = capture.detectedLanguageTitle.map { " · \($0)" } ?? ""
            return "\(capture.modelLine)\(who) · \(capture.segmentCount) lines"
        case .error(let message): return message
        case .requestingPermissions: return "Waiting for microphone access…"
        default:
            return settings.effectiveProvider(for: .rightNow)
                .map { "Ready · answering with \(ProviderCatalog.displayName($0))" }
                ?? (settings.missingKeyHint ?? "No provider ready — open Providers")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch router.pane {
        case .overview: OverviewPane(pane: $router.pane)
        case .ask: AskPane()
        case .meetings: MeetingsPane()
        case .providers: ProvidersPane()
        case .settings: SettingsPane(showOnboarding: $showOnboarding)
        case .privacy: PrivacyPane()
        }
    }
}

/// Which pane the window shows. The hotkey and the menu bar both drive this, so Ask never
/// spawns a second window.
@MainActor
final class DashboardRouter: ObservableObject {
    static let shared = DashboardRouter()
    @Published var pane: DashboardView.Pane = .overview
    func open(_ pane: DashboardView.Pane) {
        self.pane = pane
        DashboardWindowController.shared.show()
    }
}

// MARK: - Shared bits

/// Section header used by every pane.
struct PaneHeader: View {
    var title: String
    var subtitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2).bold()
            if let subtitle {
                Text(subtitle).font(.callout).foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Card used across panes. Slightly raised, brand radius, no heavy borders.
struct PaneCard<Content: View>: View {
    var title: String?
    var trailing: AnyView?
    @ViewBuilder var content: Content

    init(title: String? = nil, trailing: AnyView? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if title != nil || trailing != nil {
                HStack {
                    if let title { Text(title).font(.headline) }
                    Spacer()
                    if let trailing { trailing }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.raised)
        .clipShape(RoundedRectangle(cornerRadius: Brand.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Brand.cardRadius).stroke(Brand.line, lineWidth: 1))
    }
}

/// Status pill: "Ready", "Add key", "Not running".
struct ReadinessPill: View {
    var text: String
    var tone: Color
    var body: some View {
        Text(text)
            .font(.caption2).bold()
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tone.opacity(0.15))
            .foregroundStyle(tone)
            .clipShape(Capsule())
    }
}
