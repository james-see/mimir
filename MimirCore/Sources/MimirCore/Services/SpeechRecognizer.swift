import Foundation

/// One recognized piece of speech. `isFinal` marks an utterance boundary —
/// the moment the engine should answer.
public struct Transcription: Sendable, Equatable {
    public let text: String
    public let isFinal: Bool

    public init(text: String, isFinal: Bool) {
        self.text = text
        self.isFinal = isFinal
    }
}

/// Mic in, words out.
public protocol SpeechRecognizer: Sendable {
    /// Transcriptions published as they happen. Buffering: the stream exists
    /// for the life of the recognizer, across start/stop cycles.
    func transcriptionStream() -> AsyncThrowingStream<Transcription, Error>
    /// Request permission on first call, load the model if needed, start
    /// capture. Idempotent.
    func start() async throws
    /// Pause capture; the stream stays open for a later start().
    func stop()
}
