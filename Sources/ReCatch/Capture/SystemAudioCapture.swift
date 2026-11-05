import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics

/// System ("Others") audio via ScreenCaptureKit. Display-bound: re-resolve filter on Start.
@available(macOS 14.0, *)
final class SystemAudioCapture: NSObject, SCStreamDelegate, SCStreamOutput {
    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private var stream: SCStream?
    private let clock: MeetingClock
    private let queue = DispatchQueue(label: "radar.system-audio")

    init(clock: MeetingClock) { self.clock = clock }

    func start(displayID: CGDirectDisplayID?) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let display: SCDisplay
        if let id = displayID,
           let found = content.displays.first(where: { $0.displayID == id }) {
            display = found
        } else {
            guard let main = content.displays.first else {
                throw NSError(domain: "Radar", code: 1, userInfo: [NSLocalizedDescriptionKey: "No display found"])
            }
            display = main
        }
        let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.sampleRate = 48000
        config.channelCount = 2
        config.excludesCurrentProcessAudio = true
        config.queueDepth = 5
        let s = SCStream(filter: filter, configuration: config, delegate: self)
        self.stream = s
        try s.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
        try await s.startCapture()
    }

    func stop() async {
        guard let s = stream else { return }
        do { try await s.stopCapture() } catch { onError?(error) }
        stream = nil
    }

    // MARK: - SCStreamDelegate
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio else { return }
        // Minimal PCM extraction: real impl converts CMSampleBuffer -> 16k mono Int16.
        // M0: forward a placeholder chunk with timing so pipeline stays alive.
        let chunk = AudioChunk(stream: .system, pcm16kMono: [], meetingMs: clock.nowMs(), sampleRate: 16000)
        onChunk?(chunk)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }
}
