import Foundation

/// Append-only snapshots. The latest snapshot for each id is the saved session.
/// No API keys, audio, or system prompt are written here.
public actor TranscriptStore {
    public struct Record: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var date: Date
        public var messages: [ChatMessage]
        public init(id: UUID = UUID(), date: Date = Date(), messages: [ChatMessage]) {
            self.id = id
            self.date = date
            self.messages = messages.filter { $0.role != .system }
        }
    }
    public let url: URL
    public init(url: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mimir/conversations.jsonl")) {
        self.url = url
    }
    public func append(_ record: Record) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var data = try JSONEncoder().encode(record)
        data.append(0x0a)
        if !FileManager.default.fileExists(atPath: url.path) {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } else {
            let file = try FileHandle(forWritingTo: url)
            defer { try? file.close() }
            try file.seekToEnd()
            // Recover from a truncated final line left by an interrupted write.
            try file.write(contentsOf: Data([0x0a]))
            try file.write(contentsOf: data)
        }
    }
    public func load() throws -> [Record] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let text = try String(contentsOf: url, encoding: .utf8)
        var latest: [UUID: Record] = [:]
        for line in text.split(separator: "\n") {
            guard let record = try? JSONDecoder().decode(Record.self, from: Data(line.utf8)) else { continue }
            latest[record.id] = record
        }
        return latest.values.sorted { $0.date < $1.date }
    }
    public func deleteAll() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
