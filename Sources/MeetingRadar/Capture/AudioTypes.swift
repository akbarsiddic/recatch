import Foundation

enum AudioStream: String, Codable, Sendable { case system, mic }

struct AudioChunk: Sendable {
    let stream: AudioStream
    let pcm16kMono: [Int16]
    let meetingMs: Int64
    let sampleRate: Double
}

enum AppState: Equatable {
    case idle
    case requestingPermissions
    case listening
    case paused
    case error(String)
}
