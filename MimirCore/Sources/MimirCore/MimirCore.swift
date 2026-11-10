/// MimirCore — platform-free conversation brain for the Mimir app.
///
/// All pipeline stages are protocols; concrete backends (Ollama, WhisperKit,
/// Kokoro, SceneKit) conform in their own files.
public enum MimirCoreVersion {
    public static let current = "0.1.0"
}
