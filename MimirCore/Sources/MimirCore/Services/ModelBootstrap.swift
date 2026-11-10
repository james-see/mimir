import CryptoKit
import Foundation

/// Resolves the on-disk locations of the Kokoro model assets and, when they
/// are missing, downloads them from their public sources (Hugging Face for
/// the model, the KokoroTestApp repo for the packed voice embeddings).
///
/// Assets live in ~/Library/Application Support/Mimir/Models/ so they are
/// shared across app installs and never touch git.
public struct ModelBootstrap: Sendable {
    public struct Assets: Sendable, Equatable {
        public let modelURL: URL
        public let voicesURL: URL
    }

    public enum BootstrapError: Error, Equatable, LocalizedError {
        case downloadFailed(String)
        public var errorDescription: String? {
            switch self { case .downloadFailed(let message): message }
        }
    }

    public static let modelFileName = "kokoro-v1_0.safetensors"
    public static let voicesFileName = "voices.npz"

    private static let modelSource = URL(
        string: "https://github.com/mlalma/KokoroTestApp/raw/main/Resources/kokoro-v1_0.safetensors"
    )!
    private static let voicesSource = URL(
        string: "https://github.com/mlalma/KokoroTestApp/raw/main/Resources/voices.npz"
    )!

    /// Known-good sizes (bytes) — a mismatch means a truncated download.
    private static let modelBytes = 327_115_152
    private static let voicesBytes = 14_629_684
    /// Upstream git-lfs sha256 for the model weights (Apache-2.0 Kokoro-82M).
    public static let modelSHA256 = "4e9ecdf03b8b6cf906070390237feda473dc13327cb8d56a43deaa374c02acd8"

    public let directory: URL

    public init(
        directory: URL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Mimir/Models", isDirectory: true)
    ) {
        self.directory = directory
    }

    /// Asset locations if already on disk and complete, nil when a download
    /// is needed. A truncated/placeholder file does not count as existing.
    public func existingAssets() -> Assets? {
        let model = directory.appendingPathComponent(Self.modelFileName)
        let voices = directory.appendingPathComponent(Self.voicesFileName)
        guard sizeOf(voices) == Self.voicesBytes,
              sizeOf(model) == Self.modelBytes else {
            return nil
        }
        return Assets(modelURL: model, voicesURL: voices)
    }

    /// Download both assets if missing or incomplete. Idempotent.
    public func ensureAssets(progress: (@Sendable (String) -> Void)? = nil) async throws -> Assets {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = directory.appendingPathComponent(Self.modelFileName)
        let voices = directory.appendingPathComponent(Self.voicesFileName)

        if sizeOf(voices) != Self.voicesBytes {
            progress?("Downloading voice presets…")
            try await download(Self.voicesSource, to: voices, expectedBytes: Self.voicesBytes)
        }
        if sizeOf(model) != Self.modelBytes {
            progress?("Downloading Kokoro model (~312 MB)…")
            try await download(Self.modelSource, to: model, expectedBytes: Self.modelBytes)
        }
        return Assets(modelURL: model, voicesURL: voices)
    }

    private func sizeOf(_ url: URL) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)??.intValue
    }

    private func download(_ source: URL, to destination: URL, expectedBytes: Int) async throws {
        let (data, response) = try await URLSession.shared.data(from: source)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BootstrapError.downloadFailed("HTTP \(http.statusCode) for \(source.lastPathComponent)")
        }
        guard data.count == expectedBytes else {
            throw BootstrapError.downloadFailed(
                "\(source.lastPathComponent): got \(data.count) bytes, expected \(expectedBytes)"
            )
        }
        if destination.lastPathComponent == Self.modelFileName {
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == Self.modelSHA256 else { throw BootstrapError.downloadFailed("Kokoro checksum mismatch; download was not installed.") }
        }
        try data.write(to: destination, options: .atomic)
    }
}
