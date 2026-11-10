import Foundation

/// Streaming client for any OpenAI-compatible `/chat/completions` endpoint
/// (Ollama, LM Studio, vLLM, OpenAI, ...). Parses SSE `data:` lines and
/// yields delta content strings. `[DONE]` terminates the stream. Malformed
/// lines are skipped — one bad frame must not kill an answer.
public struct OpenAICompatibleLLM: LanguageModel {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    private struct StreamChunk: Decodable {
        struct Choice: Decodable {
            struct Delta: Decodable {
                let content: String?
            }
            let delta: Delta
        }
        let choices: [Choice]
    }

    private struct RequestBody: Encodable {
        struct OutgoingMessage: Encodable {
            let role: String
            let content: String
        }
        let model: String
        let messages: [OutgoingMessage]
        let temperature: Double
        let stream: Bool
    }

    public func stream(messages: [ChatMessage], config: LLMConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    if let apiKey = config.apiKey {
                        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    }
                    request.httpBody = try JSONEncoder().encode(RequestBody(
                        model: config.model,
                        messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
                        temperature: config.temperature,
                        stream: true
                    ))

                    let (bytes, response) = try await session.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMError.transport("response was not HTTP")
                    }
                    guard (200..<300).contains(http.statusCode) else {
                        throw LLMError.http(http.statusCode)
                    }

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)
                        if payload.trimmingCharacters(in: .whitespaces) == "[DONE]" { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(StreamChunk.self, from: data) else {
                            continue
                        }
                        for choice in chunk.choices {
                            if let content = choice.delta.content, !content.isEmpty {
                                continuation.yield(content)
                            }
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
