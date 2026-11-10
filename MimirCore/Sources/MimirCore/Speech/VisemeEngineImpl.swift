import Accelerate
import AVFAudio
import Foundation

/// The default viseme engine. Two paths:
///
/// **Aligned** — when the synthesizer emitted `phonemeTimings` (Kokoro does:
/// word-level timestamps + IPA phonemes), each word window is subdivided
/// across its classified mouth shapes.
///
/// **Envelope** — any PCM: 512/256-hop frames measure RMS and zero-crossing
/// rate; loud low-ZCR frames read as vowels, high-ZCR as sibilants, short
/// mid-speech dropouts as lip closures (`mbp`), silence as `rest`. Deliberately
/// simple — a few honest shapes beat a dozen twitchy guesses.
public struct DefaultVisemeEngine: VisemeEngine {
    public init() {}

    public func cues(for speech: SynthesizedSpeech) -> [VisemeCue] {
        if let timings = speech.phonemeTimings, !timings.isEmpty {
            return alignedCues(timings: timings, duration: speech.duration)
        }
        return envelopeCues(speech: speech)
    }

    // MARK: - Aligned path

    func alignedCues(timings: [PhonemeCue], duration: TimeInterval) -> [VisemeCue] {
        var cues: [VisemeCue] = []
        for (index, cue) in timings.enumerated() {
            let end = cue.end ?? timings[safe: index + 1]?.time ?? duration
            guard end > cue.time else { continue }
            let visemes = Self.classifyPhonemes(cue.phoneme)
            guard !visemes.isEmpty else { continue }
            let segment = (end - cue.time) / Double(visemes.count)
            for (order, viseme) in visemes.enumerated() {
                cues.append(VisemeCue(time: cue.time + segment * Double(order), id: viseme, weight: 0.9))
            }
        }
        cues.append(VisemeCue(time: duration, id: .rest, weight: 1))
        return cues
    }

    /// Classify an IPA phoneme string (or a plain surface word as fallback)
    /// into viseme classes, in order, with consecutive duplicates removed.
    /// ASCII words get digraph handling ("th", "sh", "ch", "ng") since
    /// letter-wise mapping would read "the" as t+h.
    static func classifyPhonemes(_ text: String) -> [Viseme] {
        var result: [Viseme] = []
        let chars = Array(text.lowercased())
        var index = 0
        while index < chars.count {
            var viseme = characterMap[chars[index]]
            // Digraphs: only relevant for plain-spelling fallback words.
            if index + 1 < chars.count {
                let pair = String(chars[index...index + 1])
                switch pair {
                case "th": viseme = .th
                case "sh", "ch", "zh": viseme = .sz
                case "ng": viseme = .kg
                default: break
                }
                if ["th", "sh", "ch", "zh", "ng"].contains(pair) {
                    index += 1  // consume the digraph's second letter
                }
            }
            if let viseme, result.last != viseme {
                result.append(viseme)
            }
            index += 1
        }
        return result
    }

    private static let characterMap: [Character: Viseme] = [
        // vowels (IPA + plain ASCII)
        "a": .aa, "ɑ": .aa, "ɐ": .aa, "æ": .aa,
        "o": .oh, "ɒ": .oh, "ɔ": .oh,
        "u": .oo, "ʊ": .oo, "ɥ": .oo, "w": .oo,
        "i": .ih, "e": .ih, "ɪ": .ee, "ə": .ih, "ɛ": .ih, "ɜ": .ih, "ʌ": .ih,
        // consonant classes
        "m": .mbp, "b": .mbp, "p": .mbp,
        "f": .fv, "v": .fv,
        "θ": .th, "ð": .th,
        "l": .l, "t": .l, "d": .l, "n": .l,
        "s": .sz, "z": .sz, "ʃ": .sz, "ʒ": .sz, "ʧ": .sz, "ʤ": .sz,
        "k": .kg, "g": .kg, "ŋ": .kg,
        "r": .r, "ɹ": .r, "ɾ": .r,
        // stress marks & diacritics fall through to nil (skipped)
    ]

    // MARK: - Envelope path

    /// Analysis window: 128-sample frames at 64-sample hops. Fine-grained
    /// enough that a 20 ms lip closure produces several fully-silent frames —
    /// with 512-sample windows, energy bleed from neighboring speech would
    /// hide short dropouts entirely.
    private static let frameLength = 128
    private static let hopLength = 64
    private static let silenceDb: Float = -45
    /// Zero-crossing rates (fraction of samples that flip sign).
    private static let sibilantZcr: Float = 0.12
    private static let brightZcr: Float = 0.05

    private struct Frame {
        var start: Int
        var rms: Float
        var zcr: Float
        var viseme: Viseme
        var weight: Float
    }

    func envelopeCues(speech: SynthesizedSpeech) -> [VisemeCue] {
        let buffer = speech.audio
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else {
            return [VisemeCue(time: 0, id: .rest, weight: 1)]
        }
        let count = Int(buffer.frameLength)
        let sampleRate = speech.sampleRate

        var frames: [Frame] = []
        var offset = 0
        while offset + Self.frameLength <= count {
            var rms: Float = 0
            vDSP_rmsqv(samples + offset, 1, &rms, vDSP_Length(Self.frameLength))
            var crossings = 0
            for i in (offset + 1)..<(offset + Self.frameLength) {
                if (samples[i] >= 0) != (samples[i - 1] >= 0) { crossings += 1 }
            }
            let zcr = Float(crossings) / Float(Self.frameLength)
            let db = 20 * log10(max(rms, 1e-7))
            let viseme: Viseme
            if db < Self.silenceDb {
                viseme = .rest
            } else if zcr >= Self.sibilantZcr {
                viseme = .sz
            } else if zcr >= Self.brightZcr {
                viseme = .ee
            } else {
                viseme = .aa
            }
            // Log-scale loudness → jaw weight: -45 dB → 0, -20 dB → 1.
            let weight = min(max((db + 45) / 25, 0), 1)
            frames.append(Frame(start: offset, rms: rms, zcr: zcr, viseme: viseme, weight: weight))
            offset += Self.hopLength
        }

        // Group consecutive frames of like viseme; weight = run peak.
        struct Run {
            var viseme: Viseme
            var start: Int
            var frames: Int
            var weight: Float
        }
        var runs: [Run] = []
        for frame in frames {
            if var last = runs.last, last.viseme == frame.viseme {
                last.frames += 1
                last.weight = max(last.weight, frame.weight)
                runs[runs.count - 1] = last
            } else {
                runs.append(Run(viseme: frame.viseme, start: frame.start, frames: 1, weight: frame.weight))
            }
        }
        // Short interior dropouts between speech reads as lip closure.
        let dropoutFrames = Int(0.045 * sampleRate / Double(Self.hopLength))
        for index in runs.indices {
            let run = runs[index]
            guard run.viseme == .rest,
                  run.frames <= dropoutFrames,
                  index > 0, index + 1 < runs.count,
                  runs[index - 1].viseme != .rest,
                  runs[index + 1].viseme != .rest
            else { continue }
            runs[index].viseme = .mbp
        }

        var cues = runs.map {
            VisemeCue(time: Double($0.start) / sampleRate, id: $0.viseme, weight: $0.weight)
        }
        cues.append(VisemeCue(time: speech.duration, id: .rest, weight: 1))
        return cues
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
