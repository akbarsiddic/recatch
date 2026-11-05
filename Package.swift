// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "MeetingRadar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MeetingRadar", targets: ["MeetingRadar"])
    ],
    dependencies: [
        // WhisperKit for on-device ASR (P0). Comment out if you want stub-only build.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.5.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "MeetingRadar",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/MeetingRadar",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
