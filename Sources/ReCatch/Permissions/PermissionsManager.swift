import Foundation
import AVFoundation
import AppKit
import CoreGraphics

/// Mic + Screen Recording preflight with deep links. Screen Recording needs relaunch after grant.
enum PermissionsManager {
    static func micGranted() -> Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    static func requestMic() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    static func screenGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestScreen() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openScreenSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func openMicSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}
