import XCTest
@testable import MimirCore

final class SentenceChunkerTests: XCTestCase {

    func testSplitsAcrossTokenStreams() {
        var chunker = SentenceChunker()
        XCTAssertNil(chunker.consume("The cat"))
        XCTAssertEqual(chunker.consume(" sat."), "The cat sat.")
        XCTAssertNil(chunker.consume(" Then it"))
        XCTAssertEqual(chunker.consume(" left."), "Then it left.")
        XCTAssertNil(chunker.flush())
    }

    func testAbbreviationNotSplit() {
        var chunker = SentenceChunker()
        XCTAssertNil(chunker.consume("Dr"))
        XCTAssertNil(chunker.consume(". Smith"))
        XCTAssertEqual(chunker.consume(" arrived."), "Dr. Smith arrived.")
        XCTAssertNil(chunker.flush())
    }

    func testDecimalNotSplit() {
        // A digit before the terminator defers the split — the fractional part
        // may arrive in the very next token.
        var chunker = SentenceChunker()
        XCTAssertNil(chunker.consume("Pi is 3."))
        XCTAssertNil(chunker.consume("14."))
        XCTAssertEqual(chunker.flush(), "Pi is 3.14.")
    }

    func testInitialsNotSplit() {
        var chunker = SentenceChunker()
        XCTAssertNil(chunker.consume("J. R. Tolkien"))
        XCTAssertEqual(chunker.consume(" wrote."), "J. R. Tolkien wrote.")
    }

    func testBlankLineForcesBoundary() {
        var chunker = SentenceChunker()
        XCTAssertEqual(chunker.consume("Alpha\n\nBeta"), "Alpha")
        XCTAssertEqual(chunker.consume(" continues."), "Beta continues.")
    }

    func testFlushReturnsRemainder() {
        var chunker = SentenceChunker()
        XCTAssertNil(chunker.consume("Hello there"))
        XCTAssertEqual(chunker.flush(), "Hello there")
    }

    func testFlushEmptyReturnsNil() {
        var chunker = SentenceChunker()
        XCTAssertNil(chunker.flush())
    }

    func testMinChunkLengthMergesShortSentences() {
        var chunker = SentenceChunker(minChunkLength: 20)
        XCTAssertNil(chunker.consume("OK. That makes"))
        XCTAssertEqual(chunker.consume(" sense."), "OK. That makes sense.")
    }

    func testMinChunkLengthBypassedAtFlush() {
        var chunker = SentenceChunker(minChunkLength: 20)
        XCTAssertNil(chunker.consume("Yes."))
        XCTAssertEqual(chunker.flush(), "Yes.")
    }

    func testEllipsisCollapsesAndQuestionMarkSplits() {
        var chunker = SentenceChunker()
        XCTAssertEqual(chunker.consume("Wait..."), "Wait...")
        XCTAssertEqual(chunker.consume(" what? Really."), "what?")
        XCTAssertEqual(chunker.flush(), "Really.")
    }

    func testMidWordDotNotBoundary() {
        var chunker = SentenceChunker()
        XCTAssertNil(chunker.consume("Open file.txt"))
        XCTAssertEqual(chunker.consume(" please."), "Open file.txt please.")
    }

    func testNoBoundaryWaitsForMoreTokens() {
        var chunker = SentenceChunker()
        XCTAssertNil(chunker.consume("The answer is"))
        XCTAssertNil(chunker.consume(" forty-two"))
        XCTAssertEqual(chunker.consume("."), "The answer is forty-two.")
    }

    func testClauseFallbackSplitsLongRunningSentence() {
        var chunker = SentenceChunker()
        let prefix = String(repeating: "lorem ipsum ", count: 7) + "dolor sit, "
        XCTAssertTrue(prefix.count > 80)
        XCTAssertEqual(chunker.consume(prefix + "and it goes on."), "lorem ipsum lorem ipsum lorem ipsum lorem ipsum lorem ipsum lorem ipsum lorem ipsum dolor sit,")
        XCTAssertEqual(chunker.flush(), "and it goes on.")
    }

    func testClauseFallbackIgnoredForShortBuffers() {
        var chunker = SentenceChunker()
        XCTAssertNil(chunker.consume("Sure, I can"))
        XCTAssertEqual(chunker.consume(" explain."), "Sure, I can explain.")
    }

    func testDigitGroupingCommaNotClauseBoundary() {
        var chunker = SentenceChunker()
        let long = String(repeating: "value ", count: 16) // > 80 chars
        XCTAssertNil(chunker.consume(long + "costs 1,000 dollars and counting"))
        XCTAssertEqual(chunker.consume(" forever."), long + "costs 1,000 dollars and counting forever.")
    }
}
