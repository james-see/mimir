// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MimirCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "MimirCore", targets: ["MimirCore"])
    ],
    dependencies: [
        // WhisperKit and kokoro-ios join in Tasks 5–6.
    ],
    targets: [
        .target(name: "MimirCore"),
        .testTarget(
            name: "MimirCoreTests",
            dependencies: ["MimirCore"]
        ),
    ]
)
