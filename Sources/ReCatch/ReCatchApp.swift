import SwiftUI
import AppKit

/// Launch-time work. Menu-bar apps must be live before any window or menu exists:
/// the old wiring lived in MenuBarExtra's `.onAppear`, which is why a cold start had no hotkey.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppWiring.start()
        StatusItemController.shared.install()

        // First run: open the window so setup happens in front of the user, not in a menu.
        if !AppSettings.shared.onboarded {
            DashboardWindowController.shared.show()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        OverlayController.shared.rememberPosition()
    }

    /// Menu-bar-only app: closing the window must not quit it.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

@main
struct ReCatchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    init() { SelfTest.runIfRequested() }

    var body: some Scene {
        // Every surface is an AppKit window owned by DashboardWindowController: SwiftUI's
        // Settings/Window scenes never activate an .accessory app, which is why the old
        // Settings button appeared dead. This scene exists only to satisfy `App`.
        Settings { EmptyView() }
    }
}

/// Single switch mapping AppState → display (title, color, icon) used by the status item and dashboard.
enum AppStateDisplay {
    static func meta(for state: AppState) -> (title: String, color: Color, icon: String) {
        switch state {
        case .idle: return (Brand.name, .gray, "dot.radiowaves.left.and.right")
        case .requestingPermissions: return ("Requesting access…", Brand.warn, "dot.radiowaves.left.and.right")
        case .listening: return ("Listening", Brand.ok, "waveform")
        case .paused: return ("Paused", Brand.warn, "pause.circle")
        case .error: return ("Needs attention", Brand.bad, "exclamationmark.triangle.fill")
        }
    }
}
