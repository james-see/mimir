import AVFAudio
import Synchronization
import XCTest
@testable import MimirCore

final class AudioPlayerTests: XCTestCase {

    private func sineBuffer(seconds: Double, amplitude: Float = 0.02) -> SynthesizedSpeech {
        let sampleRate: Double = 24000  // deliberately not the player format — exercises conversion
        let frames = Int(sampleRate * seconds)
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let data = buffer.floatChannelData![0]
        for i in 0..<frames {
            data[i] = amplitude * sin(2 * .pi * 440 * Float(i) / Float(sampleRate))
        }
        return SynthesizedSpeech(audio: buffer, sampleRate: sampleRate)
    }

    func testQueueDrainsInOrderWithPlausibleDuration() async throws {
        let player = AudioPlayer()
        let starts = Mutex<[Date]>([])
        player.onScheduled = { _, _, start in starts.withLock { $0.append(start) } }

        player.enqueue(sineBuffer(seconds: 0.2), visemes: [])
        player.enqueue(sineBuffer(seconds: 0.2), visemes: [])
        player.enqueue(sineBuffer(seconds: 0.2), visemes: [])

        let scheduledStarts = starts.withLock { $0 }
        XCTAssertEqual(scheduledStarts.count, 3)
        // Back-to-back scheduling: each start should be ~0.2s after the last.
        let gap1 = scheduledStarts[1].timeIntervalSince(scheduledStarts[0])
        let gap2 = scheduledStarts[2].timeIntervalSince(scheduledStarts[1])
        XCTAssertEqual(gap1, 0.2, accuracy: 0.02)
        XCTAssertEqual(gap2, 0.2, accuracy: 0.02)

        let began = Date()
        await player.waitUntilDrained()
        let elapsed = Date().timeIntervalSince(began)
        XCTAssertGreaterThan(elapsed, 0.4, "queue should take real time to play")
        XCTAssertLessThan(elapsed, 1.5)
    }

    func testStopAllUnblocksDrainWaitersImmediately() async throws {
        let player = AudioPlayer()
        player.enqueue(sineBuffer(seconds: 5.0), visemes: [])

        let began = Date()
        player.stopAll()
        await player.waitUntilDrained()
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.5)
    }

    func testDrainWithEmptyQueueReturnsImmediately() async {
        let player = AudioPlayer()
        let began = Date()
        await player.waitUntilDrained()
        XCTAssertLessThan(Date().timeIntervalSince(began), 0.1)
    }
}
