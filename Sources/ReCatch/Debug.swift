import Foundation

/// Opt-in stderr tracing: `RECATCH_DEBUG=1 ./build/ReCatch.app/Contents/MacOS/ReCatch`.
/// Never logs audio or keys — only pipeline shape ("chunk 6.9s → whisper").
enum Debug {
    private static let enabled = ProcessInfo.processInfo.environment["RECATCH_DEBUG"] == "1"

    static func log(_ message: @autoclosure () -> String) {
        guard enabled else { return }
        FileHandle.standardError.write(("[recatch] " + message() + "\n").data(using: .utf8)!)
    }
}
