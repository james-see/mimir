import XCTest
@testable import MimirCore

final class TeacherSettingsTests: XCTestCase {
    func testRoundTripAndNoSecrets() throws {
        let name = "MimirSettingsTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        var settings = TeacherSettings()
        settings.voice = "bm_fable"
        settings.model = "custom-model"
        settings.persona = "Teach mathematics."
        try settings.save(to: defaults)
        XCTAssertEqual(TeacherSettings.load(from: defaults), settings)
        let json = String(data: try JSONEncoder().encode(settings), encoding: .utf8)!
        XCTAssertFalse(json.contains("apiKey"))
        let config = try settings.config(apiKey: "test-only")
        XCTAssertEqual(config.apiKey, "test-only")
        XCTAssertEqual(config.model, "custom-model")
    }
    func testInvalidEndpointRejected() {
        for endpoint in ["file:///tmp", "https://user:password@example.com/v1", "nonsense", "https://example.com?api_key=x"] {
            var settings = TeacherSettings()
            settings.endpoint = endpoint
            XCTAssertThrowsError(try settings.validate())
        }
    }
    func testInvalidModelAndTemperatureRejected() {
        var settings = TeacherSettings()
        settings.model = " "
        XCTAssertThrowsError(try settings.validate())
        settings.model = "model"
        settings.temperature = .nan
        XCTAssertThrowsError(try settings.validate())
    }
    func testCorruptStoredSettingsRecoverDefaults() {
        let name = "MimirSettingsTests-\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(Data("bad-json".utf8), forKey: "teacherSettings")
        XCTAssertEqual(TeacherSettings.load(from: defaults), TeacherSettings())
    }
}
