import AVFAudio
import Foundation
import KokoroSwift
import MLX
import MLXUtilsLibrary

/// On-device neural voice: Kokoro 82M running under MLX Swift.
///
/// Actor-isolated because `KokoroTTS` holds mutable internal state (its G2P
/// language cache) and MLX arrays are value-semantic — all use is serialized
/// here, and sentence-level calls from the ConversationEngine naturally queue.
public actor KokoroSynthesizer: SpeechSynthesizer {
    public enum SynthesisError: Error, Equatable, CustomStringConvertible {
        case voiceFileUnreadable(String)
        case voiceNotFound(String)

        public var description: String {
            switch self {
            case .voiceFileUnreadable(let path): "Could not read voice presets at \(path)"
            case .voiceNotFound(let name): "Unknown Kokoro voice: \(name)"
            }
        }
    }

    public static let defaultVoice = "af_heart"

    public nonisolated let sampleRate: Double

    private let tts: KokoroTTS
    private let voices: [String: MLXArray]
    private let fallbackVoice: String

    /// - Parameters:
    ///   - modelURL: path to `kokoro-v1_0.safetensors`
    ///   - voicesURL: path to `voices.npz` (packed voice embeddings)
    ///   - defaultVoice: voice used when the caller passes nil
    public init(modelURL: URL, voicesURL: URL, defaultVoice: String = KokoroSynthesizer.defaultVoice) throws {
        guard let voices = NpyzReader.read(fileFromPath: voicesURL), !voices.isEmpty else {
            throw SynthesisError.voiceFileUnreadable(voicesURL.path)
        }
        self.voices = voices
        self.fallbackVoice = defaultVoice
        self.tts = KokoroTTS(modelPath: modelURL)
        self.sampleRate = Double(KokoroTTS.Constants.samplingRate)
    }

    public var availableVoices: [String] {
        voices.keys.map { String($0.split(separator: ".").first ?? "") }.sorted()
    }

    public func synthesize(_ text: String, voice: String?) async throws -> SynthesizedSpeech {
        let name = voice ?? fallbackVoice
        let key = name.hasSuffix(".npy") ? name : name + ".npy"
        guard let embedding = voices[key] else {
            throw SynthesisError.voiceNotFound(name)
        }
        // Kokoro voice naming: a* = American English, everything else is British.
        let language: Language = name.first == "a" ? .enUS : .enGB
        let (samples, tokens) = try tts.generateAudio(voice: embedding, language: language, text: text)

        let buffer = Self.makeBuffer(samples: samples, sampleRate: sampleRate)
        // Word-level alignment: time from the token stream, phonetic form when
        // the G2P resolved one (falls back to the surface word).
        let timings = tokens?.compactMap { token -> PhonemeCue? in
            guard let start = token.start_ts else { return nil }
            return PhonemeCue(
                time: start,
                phoneme: token.phonemes ?? token.text,
                end: token.end_ts
            )
        }
        return SynthesizedSpeech(audio: buffer, sampleRate: sampleRate, phonemeTimings: timings)
    }

    private static func makeBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!  // swiftlint:disable:this force_unwrapping
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return buffer
    }
}
