import Foundation

public struct ChatMessage: Sendable, Equatable, Codable {
    public enum Role: String, Codable, Sendable {
        case system, user, assistant
    }

    public let role: Role
    public let content: String

    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

public struct LLMConfig: Sendable, Equatable {
    public var baseURL: URL
    public var model: String
    public var apiKey: String?
    public var temperature: Double

    public init(
        baseURL: URL = URL(string: "http://localhost:11434/v1")!,
        model: String = "qwen3:4b-instruct",
        apiKey: String? = nil,
        temperature: Double = 0.7
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.temperature = temperature
    }
}

public enum LLMError: Error, Equatable, CustomStringConvertible {
    case http(Int)
    case transport(String)

    public var description: String {
        switch self {
        case .http(let code): "LLM endpoint returned HTTP \(code)"
        case .transport(let detail): "LLM transport error: \(detail)"
        }
    }
}

/// A chat-completions brain. Streams answer tokens as they arrive.
public protocol LanguageModel: Sendable {
    func stream(messages: [ChatMessage], config: LLMConfig) -> AsyncThrowingStream<String, Error>
}
