import AppKit
import SwiftUI
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let summonPanel = Self("summonPanel", default: .init(.r, modifiers: [.option, .command]))
}

/// ⌥⌘R brings the dashboard forward on the Ask pane.
///
/// There used to be a second floating panel here. Two surfaces is one too many: the overlay
/// shows live captions and catch-up, the dashboard is where you ask anything deeper.
enum HotkeyPanelController {
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
        DashboardRouter.shared.open(.ask)
    }

    @MainActor
    static func dismiss() {
        DashboardWindowController.shared.close()
    }
}
