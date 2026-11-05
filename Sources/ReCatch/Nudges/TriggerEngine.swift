import Foundation

/// P3 trigger engine — behind feature flag. Others-stream only. Me excluded from triggers.
final class TriggerEngine {
    var aliases: [String] = []
    var enabled = false

    /// Stage A: alias fuzzy match (normalized, token-level). Stage B: question gate EN+ID.
    func shouldNudge(segmentText: String) -> Bool {
        guard enabled else { return false }
        let norm = segmentText.lowercased()
        let aliasHit = aliases.contains { norm.contains($0.lowercased()) }
        let questionWords = ["?", "what", "who", "how", "apa", "kapan", "bagaimana", "tolong", "bisa", "apakah"]
        let questionHit = questionWords.contains { norm.contains($0) }
        return aliasHit || questionHit
    }
}
