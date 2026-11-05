import Foundation
import ScreenCaptureKit
import CoreMedia
import CoreGraphics
import AVFoundation

/// System ("Others") audio via ScreenCaptureKit. Display-bound: re-resolve filter on Start.
///
/// Sample buffers (typically 48 kHz stereo Float32) are downmixed to mono,
/// resampled to 16 kHz and forwarded as Int16. Unparseable buffers are dropped
/// (pipeline stays alive via the watchdog) rather than crashing capture.
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
        let ms = clock.nowMs()
        if let mono = Self.mono16kInt16(from: sampleBuffer) {
            onChunk?(AudioChunk(stream: .system, pcm16kMono: mono, meetingMs: ms, sampleRate: 16000))
        }
        // else: drop (silence / unparseable) — watchdog + VAD hangover cover the gap.
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        onError?(error)
    }

    // MARK: - Buffer conversion (pure-ish, no hardware)

    /// CMSampleBuffer → 16 kHz mono Int16. Supports Float32 / Int16, interleaved or planar.
    static func mono16kInt16(from sampleBuffer: CMSampleBuffer) -> [Int16]? {
        guard let asbd = sampleBuffer.formatDescription?.audioStreamBasicDescription else { return nil }
        let rate = asbd.mSampleRate
        let channels = Int(asbd.mChannelsPerFrame)
        guard rate > 0, channels > 0 else { return nil }
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isInterleaved = (asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0

        // Stack space for up to 8 channels (planar or interleaved).
        let capacity = 8
        let ablSize = MemoryLayout<AudioBufferList>.size + (capacity - 1) * MemoryLayout<AudioBuffer>.size
        var raw = [UInt8](repeating: 0, count: ablSize)
        var block: CMBlockBuffer?
        let buffers: [(UnsafeRawPointer, Int)] = raw.withUnsafeMutableBytes { ptr in
            let abl = ptr.baseAddress!.assumingMemoryBound(to: AudioBufferList.self)
            let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
                sampleBuffer,
                bufferListSizeNeededOut: nil,
                bufferListOut: abl,
                bufferListSize: ablSize,
                blockBufferAllocator: nil,
                blockBufferMemoryAllocator: nil,
                flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
                blockBufferOut: &block)
            guard status == noErr else { return [] }
            let count = min(Int(abl.pointee.mNumberBuffers), capacity)
            var out: [(UnsafeRawPointer, Int)] = []
            withUnsafePointer(to: &abl.pointee.mBuffers) { bufPtr in
                bufPtr.withMemoryRebound(to: AudioBuffer.self, capacity: count) { buf in
                    for i in 0..<count {
                        if let data = buf[i].mData, buf[i].mDataByteSize > 0 {
                            out.append((UnsafeRawPointer(data), Int(buf[i].mDataByteSize)))
                        }
                    }
                }
            }
            return out
        }
        withExtendedLifetime(block) {}
        guard !buffers.isEmpty else { return nil }

        let mono: [Float]
        if isFloat {
            if isInterleaved, buffers.count == 1 {
                let n = buffers[0].1 / MemoryLayout<Float>.size
                let floats = buffers[0].0.bindMemory(to: Float.self, capacity: n)
                mono = PCM.interleavedToMono(Array(UnsafeBufferPointer(start: floats, count: n)), channels: channels)
            } else {
                // Planar: one buffer per channel.
                let chans: [[Float]] = buffers.map { (ptr, bytes) in
                    let n = bytes / MemoryLayout<Float>.size
                    let f = ptr.bindMemory(to: Float.self, capacity: n)
                    return Array(UnsafeBufferPointer(start: f, count: n))
                }
                mono = PCM.channelsToMono(chans)
            }
        } else {
            // Int16 PCM.
            if isInterleaved, buffers.count == 1 {
                let n = buffers[0].1 / MemoryLayout<Int16>.size
                let ints = buffers[0].0.bindMemory(to: Int16.self, capacity: n)
                let floats = UnsafeBufferPointer(start: ints, count: n).map { Float($0) / 32768.0 }
                mono = PCM.interleavedToMono(floats, channels: channels)
            } else {
                let chans: [[Float]] = buffers.map { (ptr, bytes) in
                    let n = bytes / MemoryLayout<Int16>.size
                    let ints = ptr.bindMemory(to: Int16.self, capacity: n)
                    return UnsafeBufferPointer(start: ints, count: n).map { Float($0) / 32768.0 }
                }
                mono = PCM.channelsToMono(chans)
            }
        }
        guard !mono.isEmpty else { return nil }
        return PCM.to16kMonoInt16(mono, fromRate: rate)
    }
}
