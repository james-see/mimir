import Foundation

/// Turns an LLM token stream into spoken-sized chunks at sentence boundaries,
/// so TTS can start on the first clause instead of waiting for the full answer.
///
/// Rules, in priority order:
/// 1. A blank line (`\n\n`) always forces a boundary.
/// 2. Sentence terminators (`.` `!` `?` `…`) end a chunk when followed by
///    whitespace or the end of the buffer, with closers like quotes and
///    parens pulled into the chunk.
/// 3. Never split inside abbreviations (`Dr.`, `etc.`, `e.g.`), single-letter
///    initials (`J. R. Tolkien`), or decimals (`3.14`). A digit immediately
///    before a terminator defers the split entirely — the fractional part may
///    arrive in the next token.
/// 4. Mid-word periods ("file.txt") are not boundaries.
/// 5. `minChunkLength` merges runt sentences into their successor, so the
///    synthesizer isn't fed one-word chunks. `flush()` ignores it.
public struct SentenceChunker: Sendable {
    public var minChunkLength: Int

    private var buffer = ""

    private static let terminators: Set<Character> = [".", "!", "?", "…"]
    private static let closers: Set<Character> = [
        "\"", "'", "\u{201D}", "\u{2019}", ")", "]", "\u{00BB}",
    ]
    private static let abbreviations: Set<String> = [
        "dr", "mr", "mrs", "ms", "st", "jr", "sr", "prof", "vs", "etc",
        "e.g", "i.e", "fig", "inc", "ltd", "u.s", "u.k", "approx",
    ]

    public init(minChunkLength: Int = 1) {
        self.minChunkLength = minChunkLength
    }

    /// Feed one stream token. Returns a completed chunk, or nil to keep waiting.
    public mutating func consume(_ token: String) -> String? {
        buffer.append(token)
        return extract()
    }

    /// Drain whatever is left at end of stream. Returns nil when empty.
    public mutating func flush() -> String? {
        let remainder = buffer.trimmingCharacters(in: .whitespacesAndNewlines)
        buffer.removeAll()
        return remainder.isEmpty ? nil : remainder
    }

    // MARK: - Internals

    private mutating func extract() -> String? {
        while let boundaryEnd = findBoundary(from: buffer.startIndex) {
            let chunk = buffer[..<boundaryEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            buffer = String(buffer[boundaryEnd...].drop(while: { $0.isWhitespace }))
            if !chunk.isEmpty { return chunk }
        }
        return nil
    }

    /// Returns the end index of the chunk (one past terminator run + closers)
    /// for the first confirmed boundary whose prefix is at least
    /// `minChunkLength` characters long, or nil if there isn't one yet.
    private func findBoundary(from start: String.Index) -> String.Index? {
        var i = start
        while i < buffer.endIndex {
            let c0 = buffer[i]

            if c0 == "\n" {
                let next = buffer.index(after: i)
                if next < buffer.endIndex, buffer[next] == "\n" {
                    if buffer.distance(from: start, to: i) >= minChunkLength {
                        return buffer.index(after: next)
                    }
                }
                i = next
                continue
            }

            guard Self.terminators.contains(c0) else {
                i = buffer.index(after: i)
                continue
            }

            // Collapse a terminator run ("...", "?!") into one boundary.
            var j = i
            while j < buffer.endIndex, Self.terminators.contains(buffer[j]) {
                j = buffer.index(after: j)
            }

            if isRealSentenceEnd(atTerminator: i, from: start) {
                // Pull any closing punctuation into the chunk: .")
                var k = j
                while k < buffer.endIndex, Self.closers.contains(buffer[k]) {
                    k = buffer.index(after: k)
                }
                // Confirmed when followed by whitespace or end of buffer;
                // a non-space means mid-word ("file.txt") — not a boundary.
                if k == buffer.endIndex || buffer[k].isWhitespace {
                    if buffer.distance(from: start, to: i) >= minChunkLength {
                        return k
                    }
                }
            }
            i = j
        }
        return nil
    }

    private func isRealSentenceEnd(atTerminator i: String.Index, from start: String.Index) -> Bool {
        if i > start {
            let before = buffer.index(before: i)
            let previous = buffer[before]
            // Decimal or trailing number: never split after a digit.
            if previous.isNumber { return false }
        }
        let word = precedingWord(before: i, from: start)
        if !word.isEmpty {
            if Self.abbreviations.contains(word.lowercased()) { return false }
            if word.count == 1, word.first?.isUppercase == true { return false }
        }
        return true
    }

    /// Letters and internal dots immediately before the terminator, back to
    /// the first non-word character ("e.g" and "U.S" stay whole).
    private func precedingWord(before i: String.Index, from start: String.Index) -> String {
        var j = i
        var result = ""
        while j > start {
            let before = buffer.index(before: j)
            let c0 = buffer[before]
            guard c0.isLetter || c0 == "." else { break }
            result.insert(c0, at: result.startIndex)
            j = before
        }
        return result
    }
}
