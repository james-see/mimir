import XCTest
@testable import MimirCore

final class RecognitionGateTests: XCTestCase {
    func testInputAcceptedOnlyWhileListening() {
        var gate = RecognitionGate()
        XCTAssertTrue(gate.accepts(gate.generation))
        gate.setSuspended(true)
        XCTAssertFalse(gate.accepts(gate.generation))
        gate.setSuspended(false)
        XCTAssertTrue(gate.accepts(gate.generation))
    }

    func testPendingDecodeCannotLeakAcrossReplyAndResume() {
        var gate = RecognitionGate()
        let pending = gate.generation
        gate.setSuspended(true)
        XCTAssertFalse(gate.accepts(pending))
        gate.setSuspended(false)
        XCTAssertFalse(gate.accepts(pending))
        XCTAssertTrue(gate.accepts(gate.generation))
    }

    func testRepeatedSpeakingStateDoesNotInvalidateNewGeneration() {
        var gate = RecognitionGate()
        gate.setSuspended(true)
        let token = gate.generation
        gate.setSuspended(true)
        XCTAssertEqual(gate.generation, token)
    }
}
