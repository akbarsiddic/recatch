import Foundation

/// Pure DSP helpers for the capture path. Foundation-only so they stay unit-testable.
/// Conventions: mono Float in [-1, 1], Int16 full-scale, target 16 kHz.
enum PCM {
    /// Float [-1,1] → Int16 with clamp. NaN/Inf → 0.
    static func floatToInt16(_ samples: [Float]) -> [Int16] {
        samples.map { s in
            guard s.isFinite else { return 0 }
            let c = max(-1.0, min(1.0, s))
            return Int16((c * 32767.0).rounded())
        }
    }

    /// Interleaved multi-channel → mono (mean across channels).
    static func interleavedToMono(_ interleaved: [Float], channels: Int) -> [Float] {
        guard channels > 1 else { return interleaved }
        let frames = interleaved.count / channels
        var out = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var acc: Float = 0
            for ch in 0..<channels { acc += interleaved[f * channels + ch] }
            out[f] = acc / Float(channels)
        }
        return out
    }

    /// Non-interleaved channels → mono (mean; uses shortest channel).
    static func channelsToMono(_ channels: [[Float]]) -> [Float] {
        guard let first = channels.first else { return [] }
        guard channels.count > 1 else { return first }
        let frames = channels.map(\.count).min() ?? 0
        var out = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var acc: Float = 0
            for ch in channels { acc += ch[f] }
            out[f] = acc / Float(channels.count)
        }
        return out
    }

    /// Linear resample for arbitrary rate conversion (48k→16k, 44.1k→16k, …).
    static func resampleLinear(_ x: [Float], from: Double, to: Double) -> [Float] {
        guard !x.isEmpty, from > 0, to > 0 else { return x.isEmpty ? [] : x }
        if from == to { return x }
        let ratio = from / to
        let n = Int(Double(x.count) / ratio)
        guard n > 0 else { return [] }
        var out = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let pos = Double(i) * ratio
            let lo = Int(pos)
            let frac = Float(pos - Double(lo))
            let a = x[min(lo, x.count - 1)]
            let b = x[min(lo + 1, x.count - 1)]
            out[i] = a + (b - a) * frac
        }
        return out
    }

    /// Full one-shot: mono float at `fromRate` → 16 kHz Int16.
    static func to16kMonoInt16(_ mono: [Float], fromRate: Double) -> [Int16] {
        floatToInt16(resampleLinear(mono, from: fromRate, to: 16_000))
    }
}
