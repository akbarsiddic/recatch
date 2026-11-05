// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ReCatch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ReCatch", targets: ["ReCatch"])
    ],
    dependencies: [
        // WhisperKit for on-device ASR (P0). Comment out if you want stub-only build.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.5.0"),
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts.git", from: "2.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ReCatch",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            path: "Sources/ReCatch",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
