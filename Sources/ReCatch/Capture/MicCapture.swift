import Foundation
import AVFoundation

/// Mic ("Me") audio via AVAudioEngine input tap, resampled to 16k mono.
final class MicCapture: NSObject {
    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private let engine = AVAudioEngine()
    private let clock: MeetingClock

    init(clock: MeetingClock) { self.clock = clock }

    func start() throws {
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else { return }
        let converter = AVAudioConverter(from: hwFormat, to: target)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) { [weak self] buffer, _ in
            guard let self, let converter else { return }
            // Convert and forward as Int16 chunk (simplified for scaffold).
            let ratio = target.sampleRate / buffer.format.sampleRate
            let outFrames = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else { return }
            var err: NSError?
            converter.convert(to: out, error: &err) { _, _ in buffer }
            if err != nil { return }
            let chunk = AudioChunk(stream: .mic, pcm16kMono: [], meetingMs: self.clock.nowMs(), sampleRate: 16000)
            self.onChunk?(chunk)
        }
        engine.prepare()
        try engine.start()
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged), name: .AVAudioEngineConfigurationChange, object: engine)
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func routeChanged() {
        // Idempotent restart: teardown + reinstall tap.
        do {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            try engine.start()
            let input = engine.inputNode
            let hwFormat = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) { [weak self] _, _ in
                guard let self else { return }
                self.onChunk?(AudioChunk(stream: .mic, pcm16kMono: [], meetingMs: self.clock.nowMs(), sampleRate: 16000))
            }
        } catch { onError?(error) }
    }
}
