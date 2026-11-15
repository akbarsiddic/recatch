import Foundation
import CoreAudio

/// Is any app currently holding the input device? (Meet, Zoom, Teams, Voice Memos…)
enum MicActivity {
    static func isInputRunning() -> Bool {
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &device) == noErr,
              device != 0 else { return false }

        var runAddr = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var running: UInt32 = 0
        var runSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &runAddr, 0, nil, &runSize, &running) == noErr else { return false }
        return running != 0
    }
}

/// Zero-click listening: a meeting takes the mic → ReCatch starts. Long silence → it stops.
/// Manual stop always wins (60s cooldown) so the app never fights the person using it.
@MainActor
final class MeetingWatcher {
    static let shared = MeetingWatcher()

    private var timer: Timer?
    private weak var capture: AudioCaptureManager?
    private weak var settings: AppSettings?
    private var inUseTicks = 0
    private var silentTicks = 0
    private var lastSegmentCount = 0
    private var autoStarted = false
    private var userStoppedAt: Date?

    func start(capture: AudioCaptureManager, settings: AppSettings) {
        self.capture = capture
        self.settings = settings
        timer?.invalidate()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Call when the person stops listening themselves, so auto-start backs off for a minute.
    func noteManualStop() {
        userStoppedAt = Date()
        autoStarted = false
    }

    private func tick() {
        guard let capture, let settings else { return }

        if capture.state == .listening {
            if capture.segmentCount != lastSegmentCount {
                lastSegmentCount = capture.segmentCount
                silentTicks = 0
            } else {
                silentTicks += 1
            }
            // Auto-started meetings end themselves after 3 minutes of nothing said.
            if autoStarted, silentTicks >= 90 {
                autoStarted = false
                Task { await capture.stopMeeting() }
            }
            return
        }

        guard settings.autoListen, capture.state == .idle else { return }
        if let stopped = userStoppedAt, Date().timeIntervalSince(stopped) < 60 { return }

        if MicActivity.isInputRunning() {
            inUseTicks += 1
        } else {
            inUseTicks = 0
        }
        // 2 ticks = ~4s of someone holding the mic: long enough to skip a stray blip.
        if inUseTicks >= 2 {
            inUseTicks = 0
            autoStarted = true
            silentTicks = 0
            lastSegmentCount = 0
            Task { await capture.startMeeting() }
        }
    }
}
