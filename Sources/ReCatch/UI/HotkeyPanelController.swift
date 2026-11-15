import AppKit
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let summonPanel = Self("summonPanel", default: .init(.r, modifiers: [.option, .command]))
}

/// Nonactivating floating panel for ⌥⌘R. Esc dismisses (via onExitCommand in the view).
enum HotkeyPanelController {
    private static var panel: NSPanel?
    private static var registered = false

    /// Idempotent: KeyboardShortcuts would otherwise stack handlers on every call.
    static func registerHotkey() {
        guard !registered else { return }
        registered = true
        KeyboardShortcuts.onKeyUp(for: .summonPanel) {
            Task { @MainActor in summon() }
        }
    }

    @MainActor
    static func summon() {
        if panel == nil {
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 420),
                styleMask: [.titled, .closable, .nonactivatingPanel, .utilityWindow],
                backing: .buffered, defer: false)
            p.isFloatingPanel = true
            p.hidesOnDeactivate = false
            p.title = "ReCatch"
            p.contentView = NSHostingView(rootView: HotkeyPanelView(model: PanelSession.shared))
            p.center()
            panel = p
        }
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        PanelSession.shared.run()
    }
    @MainActor
    static func dismiss() {
        PanelSession.shared.cancel()
        panel?.orderOut(nil)
    }
}
