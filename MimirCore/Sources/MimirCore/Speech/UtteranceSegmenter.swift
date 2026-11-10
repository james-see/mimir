import Foundation

/// Turns a stream of RMS-measured sample chunks into utterance boundaries.
/// Pure logic — no AVFoundation — so the whole VAD path is unit-tested.
///
/// State machine: below threshold, incoming audio fills a short pre-roll ring
/// (so the first syllable survives). A loud chunk starts an utterance; a
/// sustained quiet stretch (`silenceToFinalize`) or the max duration ends it.
/// Utterances shorter than `minimumSpeechDuration` are dropped.
public struct UtteranceSegmenter: Sendable {
    public enum Event: Equatable, Sendable {
        case speechStart
        case utteranceEnd([Float])
    }

    public var loudThreshold: Float = 0.02
    public var silenceToFinalize: TimeInterval = 0.7
    public var minimumSpeechDuration: TimeInterval = 0.3
    public var maximumSpeechDuration: TimeInterval = 30
    public var preRollDuration: TimeInterval = 0.2

    public let sampleRate: Int

    private var ring: [Float] = []
    private var current: [Float] = []
    private var inSpeech = false
    private var pendingSilence: TimeInterval = 0
    /// Loud time only — trailing silence must not count toward the minimum
    /// duration or every blip would survive.
    private var loudTime: TimeInterval = 0

    public init(sampleRate: Int = 16_000) {
        self.sampleRate = sampleRate
    }

    public mutating func process(rms: Float, samples: [Float]) -> [Event] {
        let dt = TimeInterval(samples.count) / TimeInterval(sampleRate)
        let isLoud = rms >= loudThreshold

        if inSpeech {
            current.append(contentsOf: samples)
            if isLoud {
                pendingSilence = 0
                loudTime += dt
            } else {
                pendingSilence += dt
            }

            let speechDuration = TimeInterval(current.count) / TimeInterval(sampleRate)
            let maxed = speechDuration >= maximumSpeechDuration
            // ε-guard: accumulated 0.1s chunks land at 0.6999…, not 0.7.
            guard maxed || pendingSilence >= silenceToFinalize - 1e-9 else { return [] }

            var events: [Event] = []
            if loudTime >= minimumSpeechDuration - 1e-9 {
                events.append(.utteranceEnd(current))
            }
            current.removeAll()
            pendingSilence = 0
            loudTime = 0
            inSpeech = false
            return events
        }

        ring.append(contentsOf: samples)
        let maxRing = Int(preRollDuration * TimeInterval(sampleRate))
        if ring.count > maxRing {
            ring.removeFirst(ring.count - maxRing)
        }
        guard isLoud else { return [] }

        inSpeech = true
        current = ring
        ring.removeAll()
        loudTime = dt  // the chunk that started speech counts as loud
        pendingSilence = 0
        return [.speechStart]
    }

    public mutating func reset() {
        ring.removeAll()
        current.removeAll()
        inSpeech = false
        pendingSilence = 0
    }
}
