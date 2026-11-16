import SwiftUI
import AppKit
import Combine

/// The always-there surface. Deliberately NOT captions: ReCatch is not a translation app,
/// the user can hear the meeting. This shows what the meeting *means* right now — a live
/// summary — plus an inline Ask chat, so a question never costs a window switch.
@MainActor
final class OverlayModel: ObservableObject {
    struct Turn: Identifiable {
        let id = UUID()
        let question: String
        var answer: String
    }

    /// Live one-or-two-line summary, refreshed on a timer.
    @Published var now: String = ""
    /// Fuller catch-up ("what did I miss"), only on demand.
    @Published var catchUp: String = ""
    @Published var chat: [Turn] = []
    @Published var isLoadingNow = false
    @Published var isLoadingCatchUp = false
    @Published var asking = false
    @Published var error: String?
    @Published var expanded = true

    private var autoTask: Task<Void, Never>?
    private var catchTask: Task<Void, Never>?
    private var askTask: Task<Void, Never>?

    /// Re-summarise every 60 s while listening. One cheap `.now` call — no caption latency
    /// requirement, so this tolerates the Accurate tier running on CPU.
    func startAutoSummary() {
        guard autoTask == nil else { return }
        autoTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func stopAutoSummary() {
        autoTask?.cancel(); autoTask = nil
        catchTask?.cancel(); catchTask = nil
        askTask?.cancel(); askTask = nil
        isLoadingNow = false; isLoadingCatchUp = false; asking = false
    }

    func reset() {
        stopAutoSummary()
        now = ""; catchUp = ""; chat = []; error = nil
    }

    func refreshNow() async {
        guard !isLoadingNow else { return }
        isLoadingNow = true
        defer { isLoadingNow = false }
        do {
            _ = try await AnswerEngine.shared.answer(.init(mode: .now, windowSec: 180)) { [weak self] text in
                self?.now = text
            }
        } catch {
            // Keep the last good line: a failed refresh should not blank the overlay.
        }
    }

    func catchMeUp() {
        catchTask?.cancel()
        isLoadingCatchUp = true
        error = nil
        catchTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isLoadingCatchUp = false }
            do {
                _ = try await AnswerEngine.shared.answer(.init(mode: .missed, windowSec: 300)) { [weak self] text in
                    self?.catchUp = text
                }
            } catch is CancellationError {
            } catch {
                self.error = Self.describe(error)
            }
        }
    }

    func ask(_ question: String) {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        askTask?.cancel()
        chat.append(Turn(question: q, answer: ""))
        let index = chat.count - 1
        asking = true
        error = nil
        askTask = Task { [weak self] in
            guard let self else { return }
            defer { self.asking = false }
            do {
                _ = try await AnswerEngine.shared.answer(.init(mode: .ask, windowSec: 1800, question: q)) { [weak self] text in
                    guard let self, self.chat.indices.contains(index) else { return }
                    self.chat[index].answer = text
                }
            } catch is CancellationError {
            } catch {
                self.error = Self.describe(error)
                if self.chat.indices.contains(index), self.chat[index].answer.isEmpty {
                    self.chat.remove(at: index)
                }
            }
        }
    }

    private static func describe(_ error: Error) -> String {
        if let e = error as? AnswerError {
            switch e {
            case .empty(let reason): return reason
            case .failure(let message): return message
            }
        }
        return error.localizedDescription
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @ObservedObject var capture: AudioCaptureManager
    var onHide: () -> Void

    @State private var draft = ""
    @FocusState private var typing: Bool

    private var listening: Bool { capture.state == .listening }

    /// `.now` answers arrive as "Now: …". The card is already labelled, so drop the prefix.
    private var summaryLine: String {
        var s = model.now.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["Now: ", "Now:", "now: "] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
            break
        }
        return s
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if model.expanded {
                summaryCard
                if !model.catchUp.isEmpty { catchUpCard }
                if !model.chat.isEmpty { chatThread }
                if let e = model.error {
                    Text(e).font(.system(size: 11)).foregroundStyle(Brand.warn).lineLimit(2)
                }
                askRow
            } else if !summaryLine.isEmpty {
                Text(summaryLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(width: model.expanded ? 440 : 320, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Brand.overlayRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Brand.overlayRadius, style: .continuous)
                .strokeBorder(Brand.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        .animation(.snappy(duration: 0.18), value: model.expanded)
        .animation(.snappy(duration: 0.18), value: model.chat.count)
        .animation(.snappy(duration: 0.18), value: model.catchUp)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(listening ? Brand.ok : Brand.warn)
                .frame(width: 8, height: 8)
                .shadow(color: (listening ? Brand.ok : Brand.warn).opacity(0.7), radius: 4)
            Text(listening ? "Listening" : "Paused")
                .font(.system(size: 12, weight: .semibold))
            if let since = capture.meetingStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.clock(Int(ctx.date.timeIntervalSince(since))))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            languageChip
            Button {
                model.expanded.toggle()
            } label: {
                Image(systemName: model.expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.expanded ? "Collapse" : "Expand")

            Button(action: onHide) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide overlay (⌥⌘R still works)")
        }
    }

    private static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// Same one-click language change as the dashboard, without leaving the meeting.
    private var languageChip: some View {
        Menu {
            ForEach(SpokenLanguage.allCases) { l in
                Button(l.title) { capture.applyLanguage(l) }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "globe").font(.system(size: 9, weight: .bold))
                Text(capture.detectedLanguageTitle ?? AppSettings.shared.spokenLanguage.title)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Meeting language")
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("NOW")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Brand.accent)
                    .tracking(0.8)
                if model.isLoadingNow { BrandDots() }
                Spacer()
                Button {
                    model.catchMeUp()
                } label: {
                    Text(model.isLoadingCatchUp ? "Catching up…" : "Catch me up")
                        .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Brand.accent)
                .disabled(model.isLoadingCatchUp)
            }
            Text(summaryLine.isEmpty ? "Listening for the first words…" : summaryLine)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(summaryLine.isEmpty ? .secondary : .primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let note = capture.systemNote {
                Text(note).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var catchUpCard: some View {
        Text(model.catchUp)
            .font(.system(size: 11))
            .lineLimit(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .textSelection(.enabled)
            .padding(10)
            .background(Brand.raised.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// The last two exchanges. No scroll view: chat here is ephemeral — you ask, you read,
    /// you go back to the meeting. Older turns belong in the dashboard.
    private var chatThread: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(model.chat.suffix(2))) { turn in
                VStack(alignment: .leading, spacing: 3) {
                    Text(turn.question)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    if turn.answer.isEmpty {
                        BrandDots()
                    } else {
                        Text(turn.answer)
                            .font(.system(size: 12))
                            .lineLimit(6)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var askRow: some View {
        HStack(spacing: 8) {
            TextField("Ask about this meeting…", text: $draft)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .focused($typing)
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(canSend ? Brand.accent : Color.secondary.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
            .help("Ask (⏎)")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Brand.raised.opacity(0.7), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !model.asking
    }

    private func send() {
        guard canSend else { return }
        model.ask(draft)
        draft = ""
    }
}

/// Owns the floating NSPanel. One overlay, installed at launch.
@MainActor
final class OverlayController: ObservableObject {
    static let shared = OverlayController()

    /// The panel's real visibility. The menu used to read `settings.overlayEnabled` instead,
    /// so "Show/Hide overlay" could claim the opposite of what was on screen.
    @Published private(set) var isVisible = false

    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private let model = OverlayModel()
    private var hiddenByUser = false
    private static let frameKey = "recatch.overlayFrame"

    func installIfEnabled(settings: AppSettings) {
        bind(capture: AudioCaptureManager.shared)
        // AppSettings is UserDefaults-backed, so react to objectWillChange rather than a @Published.
        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                if settings.overlayEnabled { self.showIfListening() } else { self.hide() }
            }
            .store(in: &cancellables)
    }

    private func bind(capture: AudioCaptureManager) {
        capture.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in
                guard let self else { return }
                if state == .listening {
                    self.hiddenByUser = false
                    self.showIfListening()
                } else if self.panel?.isVisible == true {
                    self.hide()
                }
            }
            .store(in: &cancellables)

        // The panel grows and shrinks with its content (summary → catch-up → chat).
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.fitPanel() }
            }
            .store(in: &cancellables)
    }

    func showIfListening() {
        guard AudioCaptureManager.shared.state == .listening, !hiddenByUser else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(savedOrigin(for: panel))
        panel.orderFrontRegardless()
        isVisible = true
        model.startAutoSummary()
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        model.stopAutoSummary()
    }

    func hideByUser() {
        hiddenByUser = true
        hide()
    }

    func toggle() {
        if panel?.isVisible == true { hideByUser() } else { hiddenByUser = false; showIfListening() }
    }

    /// The view has a fixed width and an intrinsic height, so the panel follows the content.
    private func fitPanel() {
        guard let p = panel, let v = p.contentView else { return }
        v.layoutSubtreeIfNeeded()
        let fit = v.fittingSize
        guard fit.height > 1, fit.width > 1 else { return }
        let size = NSSize(width: fit.width.rounded(.up), height: fit.height.rounded(.up))
        guard abs(size.height - p.frame.height) > 1 || abs(size.width - p.frame.width) > 1 else { return }
        // Bottom-left anchored: the overlay sits near the bottom of the screen and grows upward.
        p.setContentSize(size)
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 440, height: 260)
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isMovableByWindowBackground = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        p.animationBehavior = .utilityWindow
        p.contentView = NSHostingView(rootView: OverlayView(
            model: model,
            capture: AudioCaptureManager.shared,
            onHide: { [weak self] in self?.hideByUser() }
        ))
        p.contentView?.wantsLayer = true
        return p
    }

    /// Bottom-center by default, then wherever the user dragged it last.
    private func savedOrigin(for panel: NSPanel) -> NSPoint {
        if let s = UserDefaults.standard.string(forKey: Self.frameKey) {
            let parts = s.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 { return NSPoint(x: parts[0], y: parts[1]) }
        }
        guard let screen = NSScreen.main else { return NSPoint(x: 200, y: 200) }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        return NSPoint(x: visible.midX - size.width / 2, y: visible.minY + 90)
    }

    /// Called on hide so the next launch puts it back where the user left it.
    func rememberPosition() {
        guard let p = panel else { return }
        UserDefaults.standard.set("\(p.frame.origin.x),\(p.frame.origin.y)", forKey: Self.frameKey)
    }
}
