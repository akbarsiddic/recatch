import Foundation

/// Counting semaphore for async code. An actor cannot do this: `await` inside an actor
/// method releases the actor, so two callers interleave and both reach the hardware.
final class AsyncSemaphore: @unchecked Sendable {
    private let lock = NSLock()
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(_ count: Int) { self.count = count }

    func wait() async {
        lock.lock()
        if count > 0 {
            count -= 1
            lock.unlock()
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
            lock.unlock()
        }
    }

    func signal() {
        lock.lock()
        if waiters.isEmpty {
            count += 1
            lock.unlock()
        } else {
            let next = waiters.removeFirst()
            lock.unlock()
            next.resume()
        }
    }
}

/// The meeting language, decided once and read by every inference call.
/// An actor because the transcriber closure is @Sendable and the value changes mid-meeting.
actor LanguageBox {
    private var hint: LanguageHint
    init(_ hint: LanguageHint) { self.hint = hint }
    func set(_ h: LanguageHint) { hint = h }
    func get() -> LanguageHint { hint }
}
