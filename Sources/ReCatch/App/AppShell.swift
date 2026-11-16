import AppKit
import SwiftUI
import Combine

/// The app has a real window now.
///
/// Why not SwiftUI's `Settings`/`Window` scenes: in an `.accessory` (menu-bar-only) app those
/// windows are created but the app is never activated, so they open *behind* whatever you are
/// looking at — which reads as "the Settings button is dead". Owning the NSWindow and calling
/// `activate` is the only reliable way in.
@MainActor
final class DashboardWindowController: NSObject, NSWindowDelegate {
    static let shared = DashboardWindowController()

    private var window: NSWindow?
    /// Published so the status-item menu can say "Open Dashboard" / "Close Dashboard".
    let isOpen = CurrentValueSubject<Bool, Never>(false)

    func prepare() {
        guard window == nil else { return }
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        w.title = Brand.name
        w.titlebarAppearsTransparent = true
        w.titleVisibility = .hidden
        w.isReleasedWhenClosed = false
        w.minSize = NSSize(width: 880, height: 600)
        w.delegate = self
        w.contentView = NSHostingView(rootView: DashboardView())
        w.center()
        w.setFrameAutosaveName("ReCatchDashboard")
        window = w
    }

    func show() {
        prepare()
        // Dock icon while the window is open (Docker Desktop's behaviour), menu-bar-only otherwise.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        isOpen.send(true)
    }

    func toggle() { isOpen.value ? close() : show() }

    func close() {
        window?.orderOut(nil)
        window?.close()
        isOpen.send(false)
        NSApp.setActivationPolicy(.accessory)
    }

    func windowWillClose(_ notification: Notification) {
        isOpen.send(false)
        NSApp.setActivationPolicy(.accessory)
    }
}

/// The menu-bar item. Left click opens the dashboard; right click is the small quick menu.
///
/// This replaces `MenuBarExtra`, whose content is built once when the menu opens and never
/// redraws — so the live level meter and "hearing you now" line were always stale.
@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var item: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []

    func install() {
        guard item == nil else { return }
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        status.button?.target = self
        status.button?.action = #selector(handleClick)
        status.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        status.button?.imagePosition = .imageLeading
        item = status

        let capture = AudioCaptureManager.shared
        // Icon + title follow capture state without opening anything.
        capture.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] state in self?.render(state) }
            .store(in: &cancellables)
        capture.$level
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.render(capture.state) }
            .store(in: &cancellables)
        render(capture.state)
    }

    private func render(_ state: AppState) {
        guard let button = item?.button else { return }
        let meta = AppStateDisplay.meta(for: state)
        button.image = menuBarImage(listening: state == .listening)
        // Listening gets a word; everything else stays a quiet icon.
        button.title = state == .listening ? "  Listening" : ""
        button.toolTip = "\(Brand.name) — \(meta.title)"
    }

    /// The brand menu-bar mark: the coral arc, plus a dot while listening.
    private func menuBarImage(listening: Bool) -> NSImage? {
        let base = listening ? "recatchMenuBarListening" : "recatchMenuBarIdle"
        let url = Bundle.main.url(forResource: base + "@2x", withExtension: "png")
            ?? Bundle.main.url(forResource: base, withExtension: "png")
        guard let url, let img = NSImage(contentsOfFile: url.path) else { return nil }
        img.isTemplate = true
        img.size = NSSize(width: 18, height: 18)
        return img
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return showDashboard() }
        if event.type == .rightMouseUp {
            showQuickMenu()
        } else {
            showDashboard()
        }
    }

    private func showDashboard() { DashboardWindowController.shared.show() }

    /// Built fresh on every right click, so it can never show stale state.
    private func showQuickMenu() {
        let capture = AudioCaptureManager.shared
        let menu = NSMenu()

        let status = NSMenuItem(title: AppStateDisplay.meta(for: capture.state).title, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())

        menu.addItem(withTitle: capture.state == .listening ? "Stop listening" : "Start listening",
                     action: #selector(toggleListening), keyEquivalent: "l").keyEquivalentModifierMask = [.option, .command]
        menu.addItem(withTitle: "Ask ReCatch…  ⌥⌘R", action: #selector(ask), keyEquivalent: "r").keyEquivalentModifierMask = [.option, .command]
        menu.addItem(withTitle: OverlayController.shared.isVisible ? "Hide overlay" : "Show overlay",
                     action: #selector(toggleOverlay), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Open ReCatch", action: #selector(openDashboard), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ReCatch", action: #selector(quit), keyEquivalent: "q")

        for it in menu.items where it.action != nil { it.target = self }
        item?.menu = menu
        item?.button?.performClick(nil)
        item?.menu = nil // back to left/right click handling
    }

    @objc private func toggleListening() {
        Task { @MainActor in
            let capture = AudioCaptureManager.shared
            if capture.state == .listening {
                MeetingWatcher.shared.noteManualStop()
                await capture.stopMeeting()
            } else {
                await capture.startMeeting()
            }
        }
    }

    @objc private func ask() { Task { @MainActor in HotkeyPanelController.summon() } }
    @objc private func toggleOverlay() { OverlayController.shared.toggle() }
    @objc private func openDashboard() { DashboardWindowController.shared.show() }
    @objc private func openSettings() {
        DashboardWindowController.shared.show()
        NotificationCenter.default.post(name: .recatchOpenSettings, object: nil)
    }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}

extension Notification.Name {
    static let recatchOpenSettings = Notification.Name("recatch.openSettings")
}
