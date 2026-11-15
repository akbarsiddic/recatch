import Foundation
import CoreAudio
import AVFoundation

/// System audio via Core Audio process taps (macOS 14.2+) — what StreamLingo does
/// (`CoreAudioTapSource` + `NSAudioCaptureUsageDescription`).
///
/// The win: capturing audio needs only the **Audio Recording** permission, not Screen Recording.
/// ScreenCaptureKit is kept as a fallback for older systems or when the tap fails.
@available(macOS 14.2, *)
final class SystemAudioTap {
    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onError: (@Sendable (Error) -> Void)?

    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?
    private var sourceRate: Double = 48_000
    private var channels: Int = 2
    private let clock: MeetingClock

    init(clock: MeetingClock) { self.clock = clock }

    struct TapError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func start() throws {
        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        desc.uuid = UUID()
        desc.muteBehavior = .unmuted // keep the meeting audible while we listen
        desc.isPrivate = true

        var tap = AudioObjectID(kAudioObjectUnknown)
        var status = AudioHardwareCreateProcessTap(desc, &tap)
        guard status == noErr, tap != kAudioObjectUnknown else {
            throw TapError(message: "Core Audio tap failed (\(status)). Grant Audio Recording in System Settings → Privacy.")
        }
        tapID = tap

        // Native format of the tap (usually 48 kHz float stereo).
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var asbd = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &addr, 0, nil, &size, &asbd)
        if status == noErr, asbd.mSampleRate > 0 {
            sourceRate = asbd.mSampleRate
            channels = max(1, Int(asbd.mChannelsPerFrame))
        }

        // Aggregate device that exposes the tap as an input.
        let aggUID = UUID().uuidString
        let subTap: [String: Any] = [
            kAudioSubTapUIDKey: desc.uuid.uuidString,
            kAudioSubTapDriftCompensationKey: true,
        ]
        let aggDesc: [String: Any] = [
            kAudioAggregateDeviceNameKey: "ReCatch System Audio",
            kAudioAggregateDeviceUIDKey: aggUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapListKey: [subTap],
        ]
        var agg = AudioObjectID(kAudioObjectUnknown)
        status = AudioHardwareCreateAggregateDevice(aggDesc as CFDictionary, &agg)
        guard status == noErr, agg != kAudioObjectUnknown else {
            cleanup()
            throw TapError(message: "Could not create the tap device (\(status)).")
        }
        aggregateID = agg

        var proc: AudioDeviceIOProcID?
        status = AudioDeviceCreateIOProcIDWithBlock(&proc, aggregateID, nil) { [weak self] _, inData, _, _, _ in
            guard let self else { return }
            self.handle(inData)
        }
        guard status == noErr, let proc else {
            cleanup()
            throw TapError(message: "Could not attach to the tap device (\(status)).")
        }
        procID = proc

        status = AudioDeviceStart(aggregateID, proc)
        guard status == noErr else {
            cleanup()
            throw TapError(message: "Could not start system audio (\(status)).")
        }
        Debug.log("system audio tap started @ \(Int(sourceRate)) Hz, \(channels) ch")
    }

    /// IOProc: interleaved/planar float or int16 → 16 kHz mono Int16.
    private func handle(_ bufferList: UnsafePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: bufferList))
        guard !buffers.isEmpty else { return }

        var channelsData: [[Float]] = []
        for buf in buffers {
            guard let data = buf.mData, buf.mDataByteSize > 0 else { continue }
            let frames = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
            guard frames > 0 else { continue }
            let floats = data.bindMemory(to: Float.self, capacity: frames)
            channelsData.append(Array(UnsafeBufferPointer(start: floats, count: frames)))
        }
        guard !channelsData.isEmpty else { return }

        let mono: [Float]
        if channelsData.count == 1 && channels > 1 {
            // Interleaved stereo in a single buffer.
            mono = PCM.interleavedToMono(channelsData[0], channels: channels)
        } else {
            mono = PCM.channelsToMono(channelsData)
        }
        guard !mono.isEmpty else { return }

        let pcm = PCM.to16kMonoInt16(mono, fromRate: sourceRate)
        guard !pcm.isEmpty else { return }
        onChunk?(AudioChunk(stream: .system, pcm16kMono: pcm, meetingMs: clock.nowMs(), sampleRate: 16_000))
    }

    func stop() {
        if aggregateID != kAudioObjectUnknown, let procID {
            AudioDeviceStop(aggregateID, procID)
            AudioDeviceDestroyIOProcID(aggregateID, procID)
        }
        procID = nil
        cleanup()
    }

    private func cleanup() {
        if aggregateID != kAudioObjectUnknown {
            AudioHardwareDestroyAggregateDevice(aggregateID)
            aggregateID = kAudioObjectUnknown
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
            tapID = kAudioObjectUnknown
        }
    }
}
