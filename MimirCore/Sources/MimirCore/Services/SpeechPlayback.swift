import Foundation

/// Plays synthesized audio back in order, handing the renderer the viseme
/// track that goes with each buffer.
public protocol SpeechPlayback: Sendable {
    /// Queue a sentence for playback. Returns an opaque handle.
    @discardableResult
    func enqueue(_ speech: SynthesizedSpeech, visemes: [VisemeCue]) -> UUID

    /// Stop everything immediately (barge-in). Pending `waitUntilDrained()`
    /// calls return right away.
    func stopAll()

    /// Suspends until every enqueued buffer has finished playing.
    func waitUntilDrained() async
}
