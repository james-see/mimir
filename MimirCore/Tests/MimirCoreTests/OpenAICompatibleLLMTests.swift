import XCTest
@testable import MimirCore

/// Mock transport for the OpenAI-compatible client.
private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))!
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// URLProtocol often delivers the request body via httpBodyStream instead
    /// of httpBody — read whichever is present.
    private static func bodyData(from request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }

    override func startLoading() {
        MockURLProtocol.lastRequest = request
        MockURLProtocol.lastBody = Self.bodyData(from: request)
        do {
            let (response, data) = try MockURLProtocol.handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}

private func respond(status: Int, body: String) -> (HTTPURLResponse, Data) {
    let response = HTTPURLResponse(
        url: URL(string: "http://localhost:11434/v1/chat/completions")!,
        statusCode: status, httpVersion: nil, headerFields: nil
    )!
    return (response, Data(body.utf8))
}

final class OpenAICompatibleLLMTests: XCTestCase {

    func testStreamsTokensUntilDone() async throws {
        MockURLProtocol.handler = { _ in
            respond(status: 200, body: """
            data: {"choices":[{"delta":{"content":"Hello"}}]}

            data: {"choices":[{"delta":{"content":" world"}}]}

            data: [DONE]

            """)
        }
        let llm = OpenAICompatibleLLM(session: MockURLProtocol.session())
        var tokens: [String] = []
        for try await token in llm.stream(messages: [ChatMessage(role: .user, content: "hi")],
                                          config: LLMConfig()) {
            tokens.append(token)
        }
        XCTAssertEqual(tokens, ["Hello", " world"])
    }

    func testHTTPErrorThrows() async {
        MockURLProtocol.handler = { _ in respond(status: 401, body: "") }
        let llm = OpenAICompatibleLLM(session: MockURLProtocol.session())
        do {
            for try await _ in llm.stream(messages: [ChatMessage(role: .user, content: "hi")],
                                          config: LLMConfig()) {}
            XCTFail("expected throw on 401")
        } catch let error as LLMError {
            XCTAssertEqual(error, .http(401))
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testMalformedLineSkippedNotFatal() async throws {
        MockURLProtocol.handler = { _ in
            respond(status: 200, body: """
            data: {"choices":[{"delta":{"content":"a"}}]}
            data: {not json at all}
            data: {"choices":[{"delta":{"content":"b"}}]}

            data: [DONE]

            """)
        }
        let llm = OpenAICompatibleLLM(session: MockURLProtocol.session())
        var tokens: [String] = []
        for try await token in llm.stream(messages: [ChatMessage(role: .user, content: "hi")],
                                          config: LLMConfig()) {
            tokens.append(token)
        }
        XCTAssertEqual(tokens, ["a", "b"])
    }

    func testRequestShapeAndAuthHeader() async throws {
        MockURLProtocol.handler = { _ in
            respond(status: 200, body: "data: [DONE]\n\n")
        }
        let config = LLMConfig(
            baseURL: URL(string: "https://example.test/v1")!,
            model: "test-model",
            apiKey: "sekrit",
            temperature: 0.3
        )
        let llm = OpenAICompatibleLLM(session: MockURLProtocol.session())
        for try await _ in llm.stream(messages: [ChatMessage(role: .user, content: "hey")],
                                      config: config) {}

        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertEqual(request.url?.absoluteString, "https://example.test/v1/chat/completions")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sekrit")

        let body = try XCTUnwrap(MockURLProtocol.lastBody)
        let decoded = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(decoded["model"] as? String, "test-model")
        XCTAssertEqual(decoded["stream"] as? Bool, true)
        XCTAssertEqual(decoded["temperature"] as? Double, 0.3)
        let messages = try XCTUnwrap(decoded["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["role"], "user")
        XCTAssertEqual(messages.first?["content"], "hey")
    }

    func testNoAuthHeaderWhenNoKey() async throws {
        MockURLProtocol.handler = { _ in
            respond(status: 200, body: "data: [DONE]\n\n")
        }
        let llm = OpenAICompatibleLLM(session: MockURLProtocol.session())
        for try await _ in llm.stream(messages: [ChatMessage(role: .user, content: "hey")],
                                      config: LLMConfig(apiKey: nil)) {}
        let request = try XCTUnwrap(MockURLProtocol.lastRequest)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}
