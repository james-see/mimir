import XCTest
@testable import MimirCore

final class ArticulatedMouthTests: XCTestCase {
    func testRestIsClosedNotPermanentHole() {
        let mouth = ArticulatedMouth()
        XCTAssertEqual(mouth.opening, 0)
        XCTAssertTrue(mouth.cavity.isHidden)
        XCTAssertTrue(mouth.teeth.isHidden)
        XCTAssertTrue(mouth.tongue.isHidden)
        XCTAssertNotNil(mouth.lips.geometry)
    }

    func testVowelOpensAndConsonantCloses() {
        let mouth = ArticulatedMouth()
        mouth.update(viseme: .aa, weight: 1, ease: 1)
        XCTAssertGreaterThan(mouth.opening, 0.01)
        XCTAssertFalse(mouth.cavity.isHidden)
        XCTAssertFalse(mouth.teeth.isHidden)
        mouth.update(viseme: .mbp, weight: 1, ease: 1)
        XCTAssertEqual(mouth.opening, 0)
        XCTAssertTrue(mouth.cavity.isHidden)
        XCTAssertTrue(mouth.teeth.isHidden)
    }

    func testRoundedAndWideVowelsDifferInWidthAndOpening() {
        let mouth = ArticulatedMouth()
        mouth.update(viseme: .oo, weight: 1, ease: 1)
        let roundedWidth = mouth.width
        XCTAssertTrue(mouth.teeth.isHidden)
        mouth.update(viseme: .ee, weight: 1, ease: 1)
        XCTAssertGreaterThan(mouth.width, roundedWidth * 2)
        XCTAssertFalse(mouth.teeth.isHidden)
    }

    func testInterpolationAndZeroWeightSettleToClosed() {
        let mouth = ArticulatedMouth()
        mouth.update(viseme: .aa, weight: 1, ease: 0.5)
        XCTAssertEqual(mouth.opening, ArticulatedMouth.pose(for: .aa).opening / 2, accuracy: 0.00001)
        for _ in 0..<30 { mouth.update(viseme: .aa, weight: 0, ease: 0.5) }
        XCTAssertTrue(mouth.cavity.isHidden)
    }
}
