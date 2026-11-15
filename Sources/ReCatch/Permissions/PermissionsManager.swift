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

    /// Core Audio process taps ask for "Audio Recording" (kTCCServiceAudioCapture).
    /// It has no preflight API, so this is best-effort: the tap itself is the real test.
    static func audioRecordingGranted() -> Bool {
        UserDefaults.standard.bool(forKey: "recatch.audioRecordingConfirmed")
    }

    static func requestAudioRecording() {
        openAudioSettings()
    }

    /// Called when a Core Audio tap actually starts — the only honest proof the
    /// Audio Recording grant exists (TCC exposes no preflight API for it).
    static func confirmAudioRecording() {
        UserDefaults.standard.set(true, forKey: "recatch.audioRecordingConfirmed")
    }

    static func openAudioSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
    }

    static func openScreenSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
    }

    static func openMicSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }
}
