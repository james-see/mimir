import Foundation

/// Non-secret preferences only. API keys belong in the app's Keychain item.
public struct TeacherSettings: Codable, Equatable, Sendable {
    public var endpoint = "http://localhost:11434/v1"
    public var model = LLMConfig().model
    public var temperature = 0.7
    public var voice = KokoroSynthesizer.defaultVoice
    public var persona = ConversationEngine.defaultPersona
    public var saveConversations = true
    public init() {}

    public func validate() throws {
        guard let url = URL(string: endpoint),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else {
            throw Validation.invalidEndpoint
        }
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw Validation.emptyModel }
        guard temperature.isFinite, (0...2).contains(temperature) else { throw Validation.invalidTemperature }
    }

    public enum Validation: LocalizedError {
        case invalidEndpoint, emptyModel, invalidTemperature
        public var errorDescription: String? {
            switch self {
            case .invalidEndpoint: "Enter an HTTP(S) API base URL without credentials, query or fragment (for example http://localhost:11434/v1)."
            case .emptyModel: "Choose or enter a model name."
            case .invalidTemperature: "Temperature must be between 0 and 2."
            }
        }
    }

    public func config(apiKey: String?) throws -> LLMConfig {
        try validate()
        return LLMConfig(baseURL: URL(string: endpoint)!, model: model, apiKey: apiKey?.isEmpty == false ? apiKey : nil, temperature: temperature)
    }

    public static func load(from defaults: UserDefaults = .standard) -> TeacherSettings {
        guard let data = defaults.data(forKey: "teacherSettings"),
              let settings = try? JSONDecoder().decode(Self.self, from: data),
              (try? settings.validate()) != nil else { return Self() }
        return settings
    }

    public func save(to defaults: UserDefaults = .standard) throws {
        try validate()
        defaults.set(try JSONEncoder().encode(self), forKey: "teacherSettings")
    }
}
