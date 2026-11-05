import Foundation
import Combine

/// Owns both streams. Single start/stop, watchdog for silence.
final class AudioCaptureManager: ObservableObject {
    @Published var state: AppState = .idle
    var onChunk: (@Sendable (AudioChunk) -> Void)?

    private let clock = MeetingClock()
    private var mic: MicCapture?
    private var system: AnyObject?
    private var watchdog: Timer?

    @MainActor
    func startMeeting() async {
        state = .requestingPermissions
        clock.start()
        let micCap = MicCapture(clock: clock)
        micCap.onChunk = { [weak self] c in Task { @MainActor in self?.onChunk?(c) } }
        do { try micCap.start() } catch { state = .error("Mic failed: \(error.localizedDescription)"); return }
        self.mic = micCap
        if #available(macOS 14.0, *) {
            let sys = SystemAudioCapture(clock: clock)
            sys.onChunk = { [weak self] c in Task { @MainActor in self?.onChunk?(c) } }
            sys.onError = { [weak self] e in Task { @MainActor in self?.state = .error("System audio: \(e.localizedDescription)") } }
            do { try await sys.start(displayID: nil) } catch { state = .error("System audio: \(error.localizedDescription)"); return }
            self.system = sys
        }
        state = .listening
        watchdog = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in /* flag .noSignal if silent */ }
    }

    @MainActor
    func stopMeeting() async {
        watchdog?.invalidate(); watchdog = nil
        mic?.stop(); mic = nil
        if #available(macOS 14.0, *), let sys = system as? SystemAudioCapture { await sys.stop() }
        system = nil
        clock.stop()
        state = .idle
    }

    @MainActor
    func pause() { state = .paused }
    @MainActor
    func resume() { if state == .paused { state = .listening } }
}
