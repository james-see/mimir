import XCTest
@testable import MimirCore

final class UtteranceSegmenterTests: XCTestCase {

    /// 0.1 s chunks @ 16 kHz.
    private let chunk = 1600

    private func loud(_ rms: Float = 0.5) -> (rms: Float, samples: [Float]) {
        (rms, [Float](repeating: rms, count: chunk))
    }

    private var quiet: (rms: Float, samples: [Float]) {
        (0.001, [Float](repeating: 0, count: chunk))
    }

    func testSpeechStartAndUtteranceEnd() {
        var segmenter = UtteranceSegmenter()
        XCTAssertTrue(segmenter.process(rms: quiet.rms, samples: quiet.samples).isEmpty)
        XCTAssertTrue(segmenter.process(rms: quiet.rms, samples: quiet.samples).isEmpty)

        XCTAssertEqual(segmenter.process(rms: loud().rms, samples: loud().samples), [.speechStart])
        // More loud chunks, no end yet.
        XCTAssertTrue(segmenter.process(rms: loud().rms, samples: loud().samples).isEmpty)
        XCTAssertTrue(segmenter.process(rms: loud().rms, samples: loud().samples).isEmpty)

        var events: [UtteranceSegmenter.Event] = []
        // 0.7s of silence finalizes: 7 quiet chunks.
        var captured: [Float] = []
        for _ in 0..<7 {
            events = segmenter.process(rms: quiet.rms, samples: quiet.samples)
            if case .utteranceEnd(let audio) = events.last { captured = audio }
        }
        XCTAssertEqual(events.count, 1)
        // Utterance = 0.2s preroll + 3 loud chunks + the 7 quiet chunks
        // (silence is part of the capture until finalization).
        XCTAssertEqual(captured.count, 3200 + 2 * chunk + 7 * chunk)
    }

    func testShortUtteranceDropped() {
        var segmenter = UtteranceSegmenter()
        _ = segmenter.process(rms: loud().rms, samples: loud().samples)  // 0.1s only
        var gotEnd = false
        for _ in 0..<10 {
            let events = segmenter.process(rms: quiet.rms, samples: quiet.samples)
            if events.contains(where: { if case .utteranceEnd = $0 { true } else { false } }) {
                gotEnd = true
            }
        }
        XCTAssertFalse(gotEnd, "0.1s blip is below minimumSpeechDuration")
    }

    func testPrerollIncluded() {
        var segmenter = UtteranceSegmenter()
        for _ in 0..<5 {
            _ = segmenter.process(rms: quiet.rms, samples: quiet.samples)
        }
        _ = segmenter.process(rms: loud().rms, samples: loud().samples)
        _ = segmenter.process(rms: loud().rms, samples: loud().samples)
        _ = segmenter.process(rms: loud().rms, samples: loud().samples)

        var captured: [Float] = []
        for _ in 0..<7 {
            if case .utteranceEnd(let audio) = segmenter.process(rms: quiet.rms, samples: quiet.samples).last {
                captured = audio
            }
        }
        // 0.2s preroll (3200 samples) precedes the loud audio.
        XCTAssertEqual(captured.count, 3200 + 2 * chunk + 7 * chunk)
    }

    func testBriefQuietDoesNotTerminate() {
        var segmenter = UtteranceSegmenter()
        _ = segmenter.process(rms: loud().rms, samples: loud().samples)
        _ = segmenter.process(rms: loud().rms, samples: loud().samples)
        _ = segmenter.process(rms: quiet.rms, samples: quiet.samples)    // 0.1s pause
        _ = segmenter.process(rms: quiet.rms, samples: quiet.samples)    // 0.2s pause
        XCTAssertTrue(segmenter.process(rms: loud().rms, samples: loud().samples).isEmpty)

        var endCount = 0
        for _ in 0..<7 {
            if case .utteranceEnd = segmenter.process(rms: quiet.rms, samples: quiet.samples).last {
                endCount += 1
            }
        }
        XCTAssertEqual(endCount, 1, "one segmented utterance spanning the brief pause")
    }

    func testMaximumDurationCap() {
        var segmenter = UtteranceSegmenter()
        var capturedLength = 0
        var ended = false
        // Two priming quiet chunks → preroll = 3200.
        _ = segmenter.process(rms: quiet.rms, samples: quiet.samples)
        _ = segmenter.process(rms: quiet.rms, samples: quiet.samples)
        for index in 0..<320 {
            let events = segmenter.process(rms: loud().rms, samples: loud().samples)
            if case .utteranceEnd(let audio) = events.last {
                capturedLength = audio.count
                ended = true
                XCTAssertEqual(index, 298, "should cap at 30s of continuous speech")
                break
            }
        }
        XCTAssertTrue(ended)
        XCTAssertEqual(capturedLength, 480_000)
    }

    func testResetClearsState() {
        var segmenter = UtteranceSegmenter()
        _ = segmenter.process(rms: loud().rms, samples: loud().samples)
        segmenter.reset()
        // A reset segmenter treats new speech as a fresh start (with preroll).
        let events = segmenter.process(rms: loud().rms, samples: loud().samples)
        XCTAssertEqual(events, [.speechStart])
    }
}
