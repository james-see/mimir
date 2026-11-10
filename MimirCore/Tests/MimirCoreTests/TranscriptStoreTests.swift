import XCTest
@testable import MimirCore

final class TranscriptStoreTests: XCTestCase {
    func testRoundTripAndLatestSnapshot() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = TranscriptStore(url: dir.appendingPathComponent("test.jsonl"))
        let id = UUID()
        try await store.append(.init(id: id, messages: [.init(role: .user, content: "Hello")]))
        let messages: [ChatMessage] = [.init(role: .user, content: "Hello"), .init(role: .assistant, content: "Hi")]
        try await store.append(.init(id: id, messages: messages))
        let records = try await store.load()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].messages, messages)
        try await store.append(.init(messages: []))
        let sessions = try await store.load()
        XCTAssertEqual(sessions.count, 2)
    }
    func testMalformedLineSkippedAndDeleteIsIdempotent() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("test.jsonl")
        try Data("{truncated".utf8).write(to: url)
        let store = TranscriptStore(url: url)
        try await store.append(.init(messages: [.init(role: .user, content: "Saved")]))
        let records = try await store.load()
        XCTAssertEqual(records.count, 1)
        try await store.deleteAll()
        try await store.deleteAll()
        let cleared = try await store.load()
        XCTAssertTrue(cleared.isEmpty)
    }
    func testSystemInstructionsExcluded() {
        let record = TranscriptStore.Record(messages: [.init(role: .system, content: "private"), .init(role: .user, content: "question")])
        XCTAssertEqual(record.messages.map(\.role), [.user])
    }
}
