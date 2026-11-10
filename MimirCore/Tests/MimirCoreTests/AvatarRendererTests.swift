import SceneKit
import XCTest
@testable import MimirCore

final class IdleDriverTests: XCTestCase {

    func testBlinksOccurWithinExpectedWindow() {
        var driver = IdleDriver(now: 0)
        var sawBlink = false
        var time = 0.0
        while time < 7.0 {
            driver.advance(to: time)
            if driver.blinkWeight > 0.05 { sawBlink = true }
            time += 0.016
        }
        XCTAssertTrue(sawBlink, "no blink within 7 s (worst-case initial wait is 2.5 s)")
    }

    func testBlinkIsSmoothPulseReturningToOpen() {
        var driver = IdleDriver(now: 0)
        var peak: Float = 0
        var blinkDuration = 0.0
        var time = 0.0
        var blinkStart: Double?
        while time < 8.0 {
            driver.advance(to: time)
            if driver.blinkWeight > 0.01 {
                peak = max(peak, driver.blinkWeight)
                if blinkStart == nil { blinkStart = time }
            } else if let start = blinkStart {
                blinkDuration = time - start
                break
            }
            time += 0.008
        }
        XCTAssertGreaterThan(peak, 0.9, "blink should nearly close the eye")
        XCTAssertEqual(blinkDuration, 0.12, accuracy: 0.03)
        XCTAssertEqual(driver.blinkWeight, 0, "blink finishes fully open")
    }

    func testSwayAndGazeAreBounded() {
        var driver = IdleDriver(now: 0)
        var time = 0.0
        while time < 30.0 {
            driver.advance(to: time)
            XCTAssertLessThanOrEqual(abs(driver.sway.x), 0.02)
            XCTAssertLessThanOrEqual(abs(driver.sway.y), 0.02)
            XCTAssertLessThanOrEqual(abs(driver.gaze.x), 0.08)
            XCTAssertLessThanOrEqual(abs(driver.gaze.y), 0.08)
            time += 0.05
        }
    }
}

final class SceneKitAvatarTests: XCTestCase {

    func testPlaceholderHeadBuildsWithJawAndEyes() {
        let avatar = SceneKitAvatar()
        let jaw = avatar.scene.rootNode.descendants
            .first { $0.name == SceneKitAvatar.placeholderJawNodeName }
        XCTAssertNotNil(jaw)
        let eyes = avatar.scene.rootNode.descendants
            .filter { $0.name?.hasPrefix(SceneKitAvatar.placeholderEyePrefix) == true }
        XCTAssertEqual(eyes.count, 2)
    }

    func testVisemeCueOpensJawDuringPlayback() {
        let avatar = SceneKitAvatar()
        avatar.setVisemes(
            [VisemeCue(time: 0, id: .aa, weight: 1)],
            startingAt: Date().addingTimeInterval(-1)  // already active
        )
        var jawAngle: CGFloat = 0
        for frame in 0..<30 {
            avatar.tick(at: Double(frame) * 0.016)
            let jaw = avatar.scene.rootNode.descendants
                .first { $0.name == SceneKitAvatar.placeholderJawNodeName }!
            jawAngle = jaw.eulerAngles.x
        }
        XCTAssertGreaterThan(jawAngle, 0.25, "active .aa cue should swing the jaw open")
    }

    func testClearVisemesSettlesJawBackToClosed() {
        let avatar = SceneKitAvatar()
        avatar.setVisemes(
            [VisemeCue(time: 0, id: .aa, weight: 1)],
            startingAt: Date().addingTimeInterval(-1)
        )
        for frame in 0..<30 { avatar.tick(at: Double(frame) * 0.016) }
        avatar.clearVisemes()
        var jawAngle: CGFloat = 1
        for frame in 30..<90 {
            avatar.tick(at: Double(frame) * 0.016)
            let jaw = avatar.scene.rootNode.descendants
                .first { $0.name == SceneKitAvatar.placeholderJawNodeName }!
            jawAngle = jaw.eulerAngles.x
        }
        XCTAssertLessThan(jawAngle, 0.1)
    }

    func testMorphMapCoversEveryViseme() {
        // The switch is exhaustive (compile-time); this guards the contract
        // that only known ARKit-style target names are referenced.
        XCTAssertEqual(VisemeMorphMap.referencedMorphNames.count,
                       Set(Viseme.allCases.flatMap { VisemeMorphMap.targets(for: $0).keys }).count)
        XCTAssertTrue(VisemeMorphMap.referencedMorphNames.contains("jawOpen"))
        XCTAssertTrue(VisemeMorphMap.referencedMorphNames.contains("mouthClose"))
    }
}
