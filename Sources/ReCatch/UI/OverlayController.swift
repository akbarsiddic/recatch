import SwiftUI
import AppKit
import Combine

/// The always-there surface. Deliberately NOT captions: ReCatch is not a translation app,
/// the user can hear the meeting. This shows what the meeting *means* right now — a live
/// summary — plus an inline Ask chat, so a question never costs a window switch.
@MainActor
final class OverlayModel: ObservableObject {
    /// Live one-or-two-line summary, refreshed on a timer.
    @Published var now: String = ""
    /// Fuller catch-up ("what did I miss"), only on demand.
    @Published var catchUp: String = ""
    @Published var chat: [ChatTurn] = []
    @Published var isLoadingNow = false
    @Published var isLoadingCatchUp = false
    @Published var asking = false
    @Published var error: String?
    @Published var expanded = true
    /// Height of the scrollable content, measured by the view. The panel clamps to it so it is
    /// neither a void when the summary is short nor unbounded when the catch-up is long.
    @Published var contentHeight: CGFloat = 0
    /// Measured header + ask row + padding. A guessed constant left a visible void under short
    /// content, because the real chrome is not a fixed number.
    @Published var chromeHeight: CGFloat = 116

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
                // Until the first summary lands, retry fast: a fixed 60 s interval made the
                // card sit on "waiting for speech" long after speech had started.
                let idle = await MainActor.run { self?.now.isEmpty ?? true }
                try? await Task.sleep(for: .seconds(idle ? 10 : 60))
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
        chat.append(ChatTurn(question: q))
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
                let message = Self.describe(error)
                if self.chat.indices.contains(index) { self.chat[index].error = message }
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

private struct OverlayHeaderHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct OverlayAskHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

private struct OverlayContentHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @ObservedObject var capture: AudioCaptureManager
    var onHide: () -> Void

    @State private var draft = ""
    @State private var pulse = false
    @State private var headerH: CGFloat = 0
    @State private var askH: CGFloat = 0
    @FocusState private var typing: Bool
    @Environment(\.colorScheme) private var scheme

    /// Explicit, opaque surface. A semantic/material colour resolved against whatever app was
    /// behind the panel, so secondary text lost contrast over dark windows.
    private var surface: Color {
        scheme == .dark ? Color(white: 0.135) : Color(white: 0.985)
    }

    private var listening: Bool { capture.state == .listening }
    static let expandedSize = NSSize(width: 440, height: 430)
    static let collapsedSize = NSSize(width: 320, height: 84)
    /// Content-sized, clamped. 180 pt floor so a one-line summary still looks deliberate;
    /// 430 pt ceiling so a long catch-up scrolls instead of stretching the panel.
    static func expandedHeight(content: CGFloat, chrome: CGFloat) -> CGFloat {
        min(max(180, chrome + content), expandedSize.height)
    }

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
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 8)
                .background(GeometryReader { g in
                    Color.clear.preference(key: OverlayHeaderHeight.self, value: g.size.height)
                })
            if model.expanded {
                Divider().opacity(0.4)
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            nowSection
                            summarySection
                            if !model.chat.isEmpty { chatSection }
                            if let e = model.error {
                                Text(e).font(.system(size: 11)).foregroundStyle(Brand.warn).lineLimit(2)
                            }
                            Color.clear.frame(height: 1).id("bottom")
                        }
                        .padding(.vertical, 10)
                        .padding(.trailing, 10)
                        .background(GeometryReader { g in
                            Color.clear.preference(key: OverlayContentHeight.self, value: g.size.height)
                        })
                    }
                    // Native scrollers, forced to the overlay style in configureNativeScrollers:
                    // thin and fading rather than the legacy permanent bar.
                    .mask(
                        VStack(spacing: 0) {
                            Rectangle()
                            LinearGradient(colors: [.black, .black.opacity(0)],
                                           startPoint: .top, endPoint: .bottom)
                                .frame(height: 20)
                        }
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onPreferenceChange(OverlayContentHeight.self) { h in
                        if abs(model.contentHeight - h) > 0.5 { model.contentHeight = h }
                    }
                    .onChange(of: model.chat.last?.answer) { _, _ in
                        withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                    .onChange(of: model.catchUp) { _, _ in
                        withAnimation(.snappy(duration: 0.2)) { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                Divider().opacity(0.4)
                askRow
                    .padding(.top, 8)
                    .background(GeometryReader { g in
                        Color.clear.preference(key: OverlayAskHeight.self, value: g.size.height)
                    })
            } else if !summaryLine.isEmpty {
                Text(summaryLine)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        // Fixed, not content-sized: a long summary must scroll, not stretch the panel.
        .frame(width: model.expanded ? Self.expandedSize.width : Self.collapsedSize.width,
               height: model.expanded
                   ? Self.expandedHeight(content: model.contentHeight, chrome: model.chromeHeight)
                   : Self.collapsedSize.height,
               alignment: .topLeading)
        .background(surface, in: RoundedRectangle(cornerRadius: Brand.overlayRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Brand.overlayRadius, style: .continuous)
                .strokeBorder(Brand.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        .animation(.snappy(duration: 0.18), value: model.expanded)
        .animation(.snappy(duration: 0.18), value: model.chat.count)
        .onPreferenceChange(OverlayHeaderHeight.self) { h in headerH = h; publishChrome() }
        .onPreferenceChange(OverlayAskHeight.self) { h in askH = h; publishChrome() }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(listening ? Brand.ok : Brand.warn)
                .frame(width: 8, height: 8)
                .shadow(color: (listening ? Brand.ok : Brand.warn).opacity(0.7), radius: 4)
            Text(listening ? "Listening" : "Paused")
                .font(.system(size: 12, weight: .semibold))

            // Elapsed time: dark and semibold so it reads at a glance, and it pulses while a
            // catch-up is in flight so the header itself shows the work.
            if let since = capture.meetingStartedAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Text(Self.clock(Int(ctx.date.timeIntervalSince(since))))
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.primary)
                        .opacity(model.isLoadingCatchUp && pulse ? 0.35 : 1)
                }
            }

            Spacer()
            languageChip
            Button {
                model.expanded.toggle()
            } label: {
                Image(systemName: model.expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.expanded ? "Collapse" : "Expand")

            Button(action: onHide) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide overlay (⌥⌘R still works)")
        }
    }

    /// 28 pt outer padding + header + two hairlines + the ask row.
    private func publishChrome() {
        let chrome = 28 + headerH + 2 + askH
        if abs(model.chromeHeight - chrome) > 0.5 { model.chromeHeight = chrome }
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

    /// NOW: what the meeting is about at this moment. Accent-tinted so it never reads as
    /// the same block as the summary below it.
    private var nowSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionLabel(title: "Now", compact: true)
                if model.isLoadingNow { BrandDots() }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 6) {
                if summaryLine.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        skeletonBar(fraction: 0.94)
                        skeletonBar(fraction: 0.62)
                        Text(listening ? "Waiting for speech…" : "Not listening")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text(ChatThreadView.styled(summaryLine))
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(4)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                if let note = capture.systemNote {
                    Text(note).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Brand.accent.opacity(0.18), lineWidth: 1)
            )
        }
    }

    /// SUMMARY: the catch-up, on demand. The button lives here permanently so it is always
    /// reachable, not only after a summary already exists.
    private var summarySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                SectionLabel(title: "Summary", compact: true)
                Spacer()
                catchMeUpButton
            }
            Group {
                if model.isLoadingCatchUp && model.catchUp.isEmpty {
                    HStack(spacing: 6) {
                        BrandDots()
                        Text("Reading the last few minutes…")
                    }
                } else if model.catchUp.isEmpty {
                    Text("Catch up on what was said before you started paying attention.")
                } else {
                    Text(ChatThreadView.styled(model.catchUp))
                        .textSelection(.enabled)
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(model.catchUp.isEmpty ? .secondary : .primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Brand.raised.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var chatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(title: "Chat", compact: true)
            ChatThreadView(turns: Array(model.chat.suffix(2)), compact: true)
        }
    }

    private func skeletonBar(fraction: CGFloat) -> some View {
        GeometryReader { geo in
            Capsule()
                .fill(Color.secondary.opacity(pulse ? 0.32 : 0.14))
                .frame(width: geo.size.width * fraction, height: 9)
        }
        .frame(height: 9)
    }

    /// A real button: icon, capsule, padding, whole thing clickable.
    private var catchMeUpButton: some View {
        Button {
            model.catchMeUp()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 9, weight: .bold))
                    .rotationEffect(.degrees(model.isLoadingCatchUp ? 360 : 0))
                    .animation(model.isLoadingCatchUp
                               ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                               : .default,
                               value: model.isLoadingCatchUp)
                Text(model.isLoadingCatchUp ? "Catching up" : "Catch me up")
                    .font(.system(size: 10, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Brand.accent.opacity(0.15), in: Capsule())
            .overlay(Capsule().strokeBorder(Brand.accent.opacity(0.4), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Brand.accent)
        .disabled(model.isLoadingCatchUp)
        .help("Summarise the last few minutes")
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
                    .contentShape(Rectangle())
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

/// SwiftUI does not expose the scroller style, and the legacy style draws a permanent grey bar
/// over the rounded card. Reach the backing NSScrollView and ask for the overlay scroller:
/// native, thin, fading, and absent when the content fits.
enum NativeScroller {
    @discardableResult
    static func configure(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView {
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
            scroll.drawsBackground = false
            scroll.hasVerticalScroller = true
            return scroll
        }
        for sub in view.subviews {
            if let found = configure(sub) { return found }
        }
        return nil
    }
}

/// A borderless NSPanel refuses key status by default, which is why the Ask field could not be
/// typed into: clicks went nowhere because the panel never became key. `becomesKeyOnlyIfNeeded`
/// means it only takes focus when a control asks for it, so the app is not activated by a click.
final class OverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func mouseDown(with event: NSEvent) {
        // Click anywhere in the overlay and it takes the keyboard, so the Ask field is typable.
        if !isKeyWindow { makeKey() }
        super.mouseDown(with: event)
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

        // Height follows the clamped content height, so the panel never grows past its ceiling
        // and never sits as a half-empty box either.
        model.$expanded
            .combineLatest(model.$contentHeight, model.$chromeHeight)
            .receive(on: RunLoop.main)
            .sink { [weak self] expanded, content, chrome in
                guard let self, let p = self.panel else { return }
                let width = expanded ? OverlayView.expandedSize.width : OverlayView.collapsedSize.width
                let height = expanded
                    ? OverlayView.expandedHeight(content: content, chrome: chrome)
                    : OverlayView.collapsedSize.height
                guard abs(p.frame.width - width) > 1 || abs(p.frame.height - height) > 1 else { return }
                p.setContentSize(NSSize(width: width, height: height))
                // Resizing rebuilds the hosting tree; re-apply the overlay scroller style.
                if let content = p.contentView { NativeScroller.configure(content) }
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

    private func makePanel() -> NSPanel {
        let size = OverlayView.expandedSize
        let p = OverlayPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: false)
        // Take the keyboard on click (the Ask field needs it); .nonactivatingPanel keeps the
        // app from activating, so the meeting stays frontmost.
        p.becomesKeyOnlyIfNeeded = false
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
        if let content = p.contentView {
            // The hosting view builds its NSScrollView lazily, so retry after layout.
            DispatchQueue.main.async { [weak self] in NativeScroller.configure(content) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                NativeScroller.configure(content)
            }
        }
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

    /// Test hook: the real overlay panel's view while a meeting is running.
    func testPanelView() -> NSView? {
        showIfListening()
        return panel?.contentView
    }

    /// Called on hide so the next launch puts it back where the user left it.
    func rememberPosition() {
        guard let p = panel else { return }
        UserDefaults.standard.set("\(p.frame.origin.x),\(p.frame.origin.y)", forKey: Self.frameKey)
    }
}
