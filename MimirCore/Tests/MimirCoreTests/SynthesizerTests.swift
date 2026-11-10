import AVFAudio
import XCTest
@testable import MimirCore

/// Kokoro tests require the real model + voice packs on disk (downloaded by
/// ModelBootstrap / pre-seeded during development). When the assets are
/// absent, the Kokoro cases skip; the SystemSynthesizer case always runs.
final class SynthesizerTests: XCTestCase {

    private var assets: ModelBootstrap.Assets?

    override func setUp() async throws {
        assets = ModelBootstrap().existingAssets()
    }

    private func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let data = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        var sum: Float = 0
        for i in 0..<Int(buffer.frameLength) {
            let s = data[i]
            sum += s * s
        }
        return (sum / Float(buffer.frameLength)).squareRoot()
    }

    // MARK: - System fallback (always runs)

    func testSystemSynthesizerProducesAudio() async throws {
        let synth = SystemSynthesizer()
        let speech = try await synth.synthesize("Hello.", voice: nil)
        XCTAssertNil(speech.phonemeTimings)
        XCTAssertGreaterThan(speech.duration, 0.2, "expected at least 0.2s of audio")
        XCTAssertGreaterThan(rms(speech.audio), 0.0001, "audio should not be silent")
    }

    // MARK: - Kokoro (gated on model assets)

    func testKokoroSynthesizesNonSilentAudio() async throws {
        let assets = try XCTUnwrap(assets, "Kokoro assets not downloaded — skipping")
        let synth = try KokoroSynthesizer(modelURL: assets.modelURL, voicesURL: assets.voicesURL)

        let speech = try await synth.synthesize("Hello.", voice: nil)

        XCTAssertEqual(speech.sampleRate, 24000)
        XCTAssertGreaterThan(speech.duration, 0.3)
        XCTAssertLessThan(speech.duration, 10)
        XCTAssertGreaterThan(rms(speech.audio), 0.0001)
    }

    func testKokoroEmitsWordTimings() async throws {
        let assets = try XCTUnwrap(assets, "Kokoro assets not downloaded — skipping")
        let synth = try KokoroSynthesizer(modelURL: assets.modelURL, voicesURL: assets.voicesURL)

        let speech = try await synth.synthesize("The sky is blue.", voice: nil)

        let timings = try XCTUnwrap(speech.phonemeTimings, "expected word timings")
        XCTAssertGreaterThanOrEqual(timings.count, 3)
        XCTAssertGreaterThanOrEqual(timings.first!.time, 0)
        XCTAssertLessThanOrEqual(timings.first!.time, 0.5, "first word should start near zero")
        // Timestamps sorted and within the audio duration.
        for (a, b) in zip(timings, timings.dropFirst()) {
            XCTAssertLessThanOrEqual(a.time, b.time)
        }
        XCTAssertLessThanOrEqual(timings.last!.time, speech.duration + 0.1)
    }

    func testKokoroUnknownVoiceThrows() async throws {
        let assets = try XCTUnwrap(assets, "Kokoro assets not downloaded — skipping")
        let synth = try KokoroSynthesizer(modelURL: assets.modelURL, voicesURL: assets.voicesURL)
        do {
            _ = try await synth.synthesize("Hello.", voice: "definitely_not_a_voice")
            XCTFail("expected voiceNotFound")
        } catch let error as KokoroSynthesizer.SynthesisError {
            XCTAssertEqual(error, .voiceNotFound("definitely_not_a_voice"))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testKokoroVoiceListIncludesDefault() async throws {
        let assets = try XCTUnwrap(assets, "Kokoro assets not downloaded — skipping")
        let synth = try KokoroSynthesizer(modelURL: assets.modelURL, voicesURL: assets.voicesURL)
        let voices = await synth.availableVoices
        XCTAssertTrue(voices.contains(KokoroSynthesizer.defaultVoice))
    }
}
