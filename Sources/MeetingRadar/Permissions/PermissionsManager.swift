import Foundation

/// Mic + Screen Recording preflight with deep links. Screen Recording needs relaunch after grant.
enum PermissionsManager {
    static func micGranted() -> Bool { true /* AVCaptureDevice.authorizationStatus check on Mac */ }

    static func screenGranted() -> Bool {
        // CGPreflightScreenCaptureAccess() on Mac
        true
    }

    static func openScreenSettings() {
        // NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func openMicSettings() {
        // NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}
