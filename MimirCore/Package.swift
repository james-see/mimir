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
        .package(url: "https://github.com/mlalma/kokoro-ios.git", from: "1.0.8"),
        // Declared explicitly so MimirCore can link NpyzReader/MLXArray
        // directly (kokoro-ios's library is dynamic and re-exports nothing).
        // Versions pinned exactly to kokoro-ios 1.0.8's own requirements.
        .package(url: "https://github.com/ml-explore/mlx-swift", exact: "0.30.2"),
        .package(url: "https://github.com/mlalma/MisakiSwift", exact: "1.0.6"),
        .package(url: "https://github.com/mlalma/MLXUtilsLibrary.git", exact: "0.0.6"),
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", from: "1.1.1"),
    ],
    targets: [
        .target(
            name: "MimirCore",
            dependencies: [
                .product(name: "KokoroSwift", package: "kokoro-ios"),
                .product(name: "MisakiSwift", package: "MisakiSwift"),
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXUtilsLibrary", package: "MLXUtilsLibrary"),
                .product(name: "WhisperKit", package: "argmax-oss-swift")
            ]
        ),
        .testTarget(
            name: "MimirCoreTests",
            dependencies: ["MimirCore"]
        ),
    ]
)
