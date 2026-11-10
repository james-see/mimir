import AVFAudio
import XCTest
@testable import MimirCore

final class VisemeEngineTests: XCTestCase {

    private let engine = DefaultVisemeEngine()
    private let sampleRate: Double = 24000

    private func speech(
        samples: [Float],
        timings: [PhonemeCue]? = nil
    ) -> SynthesizedSpeech {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            buffer.floatChannelData![0].update(from: source.baseAddress!, count: samples.count)
        }
        return SynthesizedSpeech(audio: buffer, sampleRate: sampleRate, phonemeTimings: timings)
    }

    private func sine(seconds: Double, frequency: Double, amplitude: Float = 0.5) -> [Float] {
        let frames = Int(sampleRate * seconds)
        return (0..<frames).map { amplitude * sin(2 * .pi * Float(frequency) * Float($0) / Float(sampleRate)) }
    }

    // MARK: - Envelope path

    func testSilenceYieldsOnlyRest() {
        let speech = speech(samples: [Float](repeating: 0, count: Int(sampleRate)))
        let cues = engine.cues(for: speech)
        XCTAssertTrue(cues.allSatisfy { $0.id == .rest })
    }

    func testLoudToneProducesOpenMouthCues() {
        let speech = speech(samples: sine(seconds: 0.5, frequency: 300))
        let cues = engine.cues(for: speech)
        let voiced = cues.filter { $0.id != .rest }
        XCTAssertFalse(voiced.isEmpty)
        XCTAssertTrue(voiced.allSatisfy { $0.weight > 0.5 }, "loud tone should yield strong jaw weights")
        XCTAssertEqual(cues.last?.id, .rest, "buffer ends with rest")
    }

    func testHighFrequencyReadsSibilantLowFrequencyDoesNot() {
        let hissy = speech(samples: sine(seconds: 0.5, frequency: 3000))
        let boomy = speech(samples: sine(seconds: 0.5, frequency: 200))

        let hissyIds = Set(engine.cues(for: hissy).map(\.id))
        let boomyIds = Set(engine.cues(for: boomy).map(\.id))
        XCTAssertTrue(hissyIds.contains(.sz))
        XCTAssertFalse(boomyIds.contains(.sz))
        XCTAssertTrue(boomyIds.contains(.aa))
    }

    func testShortInteriorDropoutReadsAsLipClosure() {
        var samples = sine(seconds: 0.3, frequency: 300)
        samples += [Float](repeating: 0, count: Int(sampleRate * 0.02))  // 20 ms gap
        samples += sine(seconds: 0.3, frequency: 300)
        let cues = engine.cues(for: speech(samples: samples))
        XCTAssertTrue(cues.contains { $0.id == .mbp })
    }

    func testLongPauseReadsAsRestNotClosure() {
        var samples = sine(seconds: 0.3, frequency: 300)
        samples += [Float](repeating: 0, count: Int(sampleRate * 0.2))  // 200 ms pause
        samples += sine(seconds: 0.3, frequency: 300)
        let cues = engine.cues(for: speech(samples: samples))
        XCTAssertFalse(cues.contains { $0.id == .mbp })
    }

    // MARK: - Aligned path

    func testAlignedCuesFollowTokenWindows() throws {
        // "The sky." — IPA tokens the way Kokoro/Misaki emits them.
        let timings = [
            PhonemeCue(time: 0.10, phoneme: "ðə", end: 0.28),
            PhonemeCue(time: 0.32, phoneme: "skaɪ", end: 0.66),
        ]
        let cues = engine.cues(for: speech(samples: sine(seconds: 0.8, frequency: 300), timings: timings))

        let first = try XCTUnwrap(cues.first)
        XCTAssertEqual(first.id, .th)
        XCTAssertEqual(first.time, 0.10, accuracy: 0.001)
        // "skaɪ" → s, k, vowel — an open 'aa' must land inside the word window.
        XCTAssertTrue(cues.contains { $0.id == .aa && $0.time >= 0.32 && $0.time <= 0.66 })
        XCTAssertEqual(cues.last?.id, .rest)
        // Times are non-decreasing.
        for (a, b) in zip(cues, cues.dropFirst()) {
            XCTAssertLessThanOrEqual(a.time, b.time)
        }
    }

    func testAlignedWordFallbackClassifiesSpelling() {
        let timings = [PhonemeCue(time: 0.0, phoneme: "Mom", end: 0.4)]
        let cues = engine.cues(for: speech(samples: sine(seconds: 0.5, frequency: 300), timings: timings))
        XCTAssertEqual(cues.first?.id, .mbp)
        XCTAssertTrue(cues.contains { $0.id == .oh })
    }

    func testNilTimingsFallsBackToEnvelope() {
        let speech = speech(samples: sine(seconds: 0.4, frequency: 300), timings: nil)
        let cues = engine.cues(for: speech)
        XCTAssertTrue(cues.contains { $0.id == .aa })
    }

    func testCueWeightsAreBounded() {
        let timings = [
            PhonemeCue(time: 0.0, phoneme: "ðə", end: 0.2),
            PhonemeCue(time: 0.2, phoneme: "skaɪ", end: 0.5),
        ]
        let speech1 = speech(samples: sine(seconds: 0.6, frequency: 300), timings: timings)
        let speech2 = speech(samples: sine(seconds: 0.6, frequency: 300))
        for cue in engine.cues(for: speech1) + engine.cues(for: speech2) {
            XCTAssertGreaterThanOrEqual(cue.weight, 0)
            XCTAssertLessThanOrEqual(cue.weight, 1)
            XCTAssertGreaterThanOrEqual(cue.time, 0)
        }
    }

    // MARK: - Classifier basics

    func testClassifierWordCases() {
        XCTAssertEqual(DefaultVisemeEngine.classifyPhonemes("Mom"), [.mbp, .oh, .mbp])
        XCTAssertEqual(DefaultVisemeEngine.classifyPhonemes("skaɪ"), [.sz, .kg, .aa, .ee])
        XCTAssertEqual(DefaultVisemeEngine.classifyPhonemes("the"), [.th, .ih])
        XCTAssertEqual(DefaultVisemeEngine.classifyPhonemes("ssss"), [.sz], "consecutive dupes collapse")
        XCTAssertEqual(DefaultVisemeEngine.classifyPhonemes("ˈ"), [], "stress marks classify to nothing")
    }
}
