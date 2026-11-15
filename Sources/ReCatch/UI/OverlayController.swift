import SwiftUI
import AppKit
import Combine

/// The always-there surface: a floating, glanceable strip that shows what's being said
/// and lets you catch up without leaving the meeting. Non-activating, survives full screen.
@MainActor
final class OverlayModel: ObservableObject {
    @Published var catchUp: String = ""
    @Published var isLoading = false
    @Published var error: String?
    @Published var expanded = true
    @Published var collapsedHint = ""

    private var task: Task<Void, Never>?

    func refresh() {
        task?.cancel()
        task = Task { [weak self] in
            guard let self else { return }
            self.isLoading = true
            self.error = nil
            defer { self.isLoading = false }
            do {
                _ = try await AnswerEngine.shared.answer(.init(mode: .missed, windowSec: 300)) { [weak self] text in
                    self?.catchUp = text
                }
            } catch is CancellationError {
            } catch let e as AnswerError {
                switch e {
                case .empty(let reason): self.error = reason
                case .failure(let message): self.error = message
                }
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    func cancel() { task?.cancel(); isLoading = false }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel
    @ObservedObject var feed: TranscriptFeed
    @ObservedObject var capture: AudioCaptureManager
    var onStop: () -> Void
    var onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if model.expanded {
                caption
                if model.isLoading || !model.catchUp.isEmpty || model.error != nil {
                    catchUpCard
                }
                actions
            }
        }
        .padding(14)
        .frame(width: model.expanded ? 460 : 260, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Brand.overlayRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Brand.overlayRadius, style: .continuous)
                .strokeBorder(Brand.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 22, y: 10)
        .animation(.snappy(duration: 0.2), value: model.expanded)
        .animation(.snappy(duration: 0.2), value: model.catchUp)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(capture.state == .listening ? Brand.ok : Brand.warn)
                .frame(width: 8, height: 8)
                .shadow(color: (capture.state == .listening ? Brand.ok : Brand.warn).opacity(0.7), radius: 4)
            Text(capture.state == .listening ? "Listening" : "Paused")
                .font(.system(size: 12, weight: .semibold))
            if !model.expanded, !feed.caption.isEmpty {
                Text(feed.caption)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                model.expanded.toggle()
            } label: {
                Image(systemName: model.expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.expanded ? "Collapse" : "Expand")
        }
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(feed.caption.isEmpty ? "Waiting for the first words…" : feed.caption)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(feed.caption.isEmpty ? .secondary : .primary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
            if let note = capture.systemNote {
                Text(note).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }

    private var catchUpCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.isLoading, model.catchUp.isEmpty {
                HStack(spacing: 6) {
                    BrandDots()
                    Text("Catching you up…").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            } else if let e = model.error {
                Text(e).font(.system(size: 12)).foregroundStyle(Brand.warn)
            } else {
                Text(model.catchUp)
                    .font(.system(size: 12))
                    .lineLimit(6)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.raised.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                model.refresh()
            } label: {
                Label(model.isLoading ? "Catching up…" : "Catch me up", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Brand.accent)
            .disabled(model.isLoading)

            Spacer()

            Button("Stop", action: onStop)
                .buttonStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Button {
                onHide()
            } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Hide overlay (⌥⌘R still works)")
        }
    }
}

/// Owns the floating NSPanel. One overlay, installed at launch.
@MainActor
final class OverlayController {
    static let shared = OverlayController()

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
                if state == .listening { self.hiddenByUser = false; self.showIfListening() }
                else if self.panel?.isVisible == true { self.hide() }
            }
            .store(in: &cancellables)
    }

    func showIfListening() {
        guard AudioCaptureManager.shared.state == .listening, !hiddenByUser else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        panel.setFrameOrigin(savedOrigin(for: panel))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel?.orderOut(nil)
    }

    func hideByUser() {
        hiddenByUser = true
        hide()
    }

    func toggle() {
        if panel?.isVisible == true { hideByUser() } else { hiddenByUser = false; showIfListening() }
    }

    private func makePanel() -> NSPanel {
        let size = NSSize(width: 460, height: 220)
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
            feed: TranscriptFeed.shared,
            capture: AudioCaptureManager.shared,
            onStop: { Task { await AudioCaptureManager.shared.stopMeeting() } },
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
