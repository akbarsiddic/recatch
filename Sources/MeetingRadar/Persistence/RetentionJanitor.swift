import Foundation

/// M3: retention janitor — set expires_at on meeting start, purge hourly + on launch.
enum RetentionJanitor {
    static func expiresAt(from start: Date, days: Int) -> Int64 {
        if days <= 0 { return Int64(Date().timeIntervalSince1970 * 1000) } // delete on end
        return Int64(start.addingTimeInterval(Double(days) * 86400).timeIntervalSince1970 * 1000)
    }

    static func scheduleHourly(store: MeetingStore) {
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            try? store.purgeExpired()
        }
    }
}
