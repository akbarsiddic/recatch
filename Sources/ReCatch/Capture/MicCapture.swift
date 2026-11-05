import Foundation
import AVFoundation

/// Mic ("Me") audio via AVAudioEngine input tap, resampled to 16k mono Int16.
final class MicCapture: NSObject {
    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private let engine = AVAudioEngine()
    private let clock: MeetingClock
    private var converter: AVAudioConverter?
    private var target: AVAudioFormat?

    init(clock: MeetingClock) { self.clock = clock }

    func start() throws {
        try startEngine()
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged),
                                              name: .AVAudioEngineConfigurationChange, object: engine)
    }

    private func startEngine() throws {
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        guard let target = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000,
                                         channels: 1, interleaved: false) else { return }
        self.target = target
        converter = AVAudioConverter(from: hwFormat, to: target)
        try installTap()
        engine.prepare()
        try engine.start()
    }

    private func installTap() throws {
        let input = engine.inputNode
        let hwFormat = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: hwFormat) { [weak self] buffer, _ in
            guard let self,
                  let converter = self.converter,
                  let target = self.target else { return }
            guard let mono = Self.convertedInt16(buffer, converter: converter, target: target) else { return }
            let chunk = AudioChunk(stream: .mic, pcm16kMono: mono,
                                   meetingMs: self.clock.nowMs(), sampleRate: 16000)
            self.onChunk?(chunk)
        }
    }

    /// Convert one tap buffer → 16 kHz mono Int16. Nil when conversion fails (chunk dropped).
    static func convertedInt16(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter,
                               target: AVAudioFormat) -> [Int16]? {
        let ratio = target.sampleRate / buffer.format.sampleRate
        let outFrames = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up))
        guard outFrames > 0,
              let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outFrames) else { return nil }
        var err: NSError?
        var handedOff = false
        converter.convert(to: out, error: &err) { _, status in
            if !handedOff {
                handedOff = true
                status.pointee = .haveData
                return buffer
            }
            status.pointee = .noDataNow
            return nil
        }
        guard err == nil, out.frameLength > 0,
              let ptr = out.floatChannelData?[0] else { return nil }
        return (0..<Int(out.frameLength)).map { i in
            let s = ptr[i]
            guard s.isFinite else { return Int16(0) }
            return Int16((max(-1.0, min(1.0, s)) * 32767.0).rounded())
        }
    }

    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func routeChanged() {
        // Idempotent restart: teardown → start → reinstall the same converting tap.
        do {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
            try startEngine()
        } catch { onError?(error) }
    }
}
