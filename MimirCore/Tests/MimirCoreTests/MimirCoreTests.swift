import XCTest
@testable import MimirCore

final class MimirCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(MimirCoreVersion.current, "0.1.0")
    }
}
