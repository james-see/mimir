import AVFAudio
import Foundation
import Synchronization
import WhisperKit

/// Queued playback of synthesized sentences through `AVAudioEngine`.
///
/// Buffers play strictly back-to-back. Because each buffer's audible start is
/// knowable at enqueue time (start of the queue, or the end of the last
/// pending buffer), the player publishes `(id, visemes, audibleStart)` via
/// `onScheduled` so the renderer can schedule mouth shapes against the real
/// output clock.
///
/// Shared state lives in a `Mutex` (no NSLock in async contexts);
/// `stopAll()` is the barge-in path and cancels pending buffers, drain
/// waiters, and — via the generation counter — the stale completion callbacks
/// from buffers that were cancelled mid-flight.
public final class AudioPlayer: SpeechPlayback, @unchecked Sendable {
    public static let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!

    /// (id, visemes, audible start estimate) — fired synchronously at enqueue.
    public var onScheduled: (@Sendable (UUID, [VisemeCue], Date) -> Void)?

    private struct QueueState {
        var pendingCount = 0
        var scheduledEnd: Date?
        var generation = 0
        var drainWaiters: [CheckedContinuation<Void, Never>] = []
        var engineRunning = false
    }

    private let state = Mutex(QueueState())
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()

    public init() {
        engine.attach(playerNode)
        engine.connect(playerNode, to: engine.mainMixerNode, format: Self.playbackFormat)
        engine.prepare()
    }

    @discardableResult
    public func enqueue(_ speech: SynthesizedSpeech, visemes: [VisemeCue]) -> UUID {
        let id = UUID()
        guard let buffer = Self.convert(speech.audio, to: Self.playbackFormat) else {
            return id
        }

        let (start, myGeneration) = state.withLock { state in
            let start = max(state.scheduledEnd ?? Date(), Date())
            state.scheduledEnd = start.addingTimeInterval(speech.duration)
            state.pendingCount += 1
            return (start, state.generation)
        }

        onScheduled?(id, visemes, start)
        ensureEngineRunning()

        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            self?.bufferCompleted(generation: myGeneration)
        }
        playerNode.play()
        return id
    }

    public func stopAll() {
        let waiters = state.withLock { state in
            state.generation += 1
            state.pendingCount = 0
            state.scheduledEnd = nil
            defer { state.drainWaiters.removeAll() }
            return state.drainWaiters
        }
        playerNode.stop()
        waiters.forEach { $0.resume() }
    }

    public func waitUntilDrained() async {
        await withCheckedContinuation { continuation in
            let parked = state.withLock { state -> Bool in
                if state.pendingCount == 0 { return false }
                state.drainWaiters.append(continuation)
                return true
            }
            if !parked {
                continuation.resume()
            }
        }
    }

    // MARK: - Internals

    private func bufferCompleted(generation myGeneration: Int) {
        let waiters: [CheckedContinuation<Void, Never>] = state.withLock { state in
            guard myGeneration == state.generation else { return [] }
            state.pendingCount -= 1
            guard state.pendingCount <= 0 else { return [] }
            state.pendingCount = 0
            state.scheduledEnd = nil
            defer { state.drainWaiters.removeAll() }
            return state.drainWaiters
        }
        waiters.forEach { $0.resume() }
    }

    private func ensureEngineRunning() {
        let shouldStart = state.withLock { state -> Bool in
            if state.engineRunning { return false }
            state.engineRunning = true
            return true
        }
        guard shouldStart, !engine.isRunning else { return }
        do {
            try engine.start()
        } catch {
            state.withLock { $0.engineRunning = false }
        }
    }

    /// Convert any incoming PCM (Kokoro 24 kHz, system voice 22.05/44.1 kHz)
    /// into the player's fixed connection format.
    private static func convert(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        if buffer.format == format { return buffer }
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        var error: NSError?
        var consumed = false
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil else { return nil }
        return output
    }
}
