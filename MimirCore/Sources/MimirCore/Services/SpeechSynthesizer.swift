import AVFAudio
import Foundation

/// Phoneme alignment data when the TTS backend can provide it.
public struct PhonemeCue: Sendable, Equatable {
    /// Seconds from the start of the audio buffer.
    public let time: TimeInterval
    public let phoneme: String
    /// Seconds from the start of the buffer, when known (Kokoro word tokens).
    public let end: TimeInterval?

    public init(time: TimeInterval, phoneme: String, end: TimeInterval? = nil) {
        self.time = time
        self.phoneme = phoneme
        self.end = end
    }
}

/// One synthesized sentence: PCM audio plus optional phoneme alignment.
///
/// Marked `@unchecked Sendable` because `AVAudioPCMBuffer` is a reference
/// type; it is treated as immutable after creation and never mutated once
/// published.
public struct SynthesizedSpeech: @unchecked Sendable {
    public let audio: AVAudioPCMBuffer
    public let sampleRate: Double
    public let phonemeTimings: [PhonemeCue]?

    public init(audio: AVAudioPCMBuffer, sampleRate: Double, phonemeTimings: [PhonemeCue]? = nil) {
        self.audio = audio
        self.sampleRate = sampleRate
        self.phonemeTimings = phonemeTimings
    }

    public var duration: TimeInterval {
        sampleRate > 0 ? Double(audio.frameLength) / sampleRate : 0
    }
}

/// Text in, speech out.
public protocol SpeechSynthesizer: Sendable {
    func synthesize(_ text: String, voice: String?) async throws -> SynthesizedSpeech
}
