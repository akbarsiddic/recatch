import Foundation

/// Monotonic meeting clock. All segments stamped in meeting-relative ms.
final class MeetingClock {
    private var startDate = Date()
    private var running = false

    func start() { startDate = Date(); running = true }
    func stop() { running = false }
    func nowMs() -> Int64 { Int64(Date().timeIntervalSince(startDate) * 1000) }
}
