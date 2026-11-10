import SceneKit
import XCTest
@testable import MimirCore

/// Gates the bundled head asset: when `Assets/Head.usdz` exists, every morph
/// name the viseme map drives must exist in the asset, or the mouth just
/// won't move. Asset absent → test skips (placeholder head covers dev).
final class HeadAssetValidationTests: XCTestCase {

    private var headURL: URL? {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // MimirCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // MimirCore
            .deletingLastPathComponent()  // repo root
        let url = packageRoot.appendingPathComponent("Assets/Head.usdz")
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func testBundledHeadHasAllRequiredMorphs() throws {
        try XCTSkipUnless(headURL != nil, "Assets/Head.usdz not present — placeholder in use")
        let url = headURL!
        let scene = try SCNScene(url: url, options: nil)
        let morphNode = scene.rootNode.descendants
            .first { $0.morpher != nil }
        let morpher = try XCTUnwrap(morphNode?.morpher, "head asset has no morpher")

        var available = Set<String>()
        for target in morpher.targets where target.name != nil {
            available.insert(target.name!)
        }
        for name in VisemeMorphMap.referencedMorphNames {
            XCTAssertTrue(available.contains(name), "head asset is missing morph target '\(name)'")
        }
    }

    func testPlaceholderInvariants() {
        for viseme in Viseme.allCases {
            _ = VisemeMorphMap.jawWeight(for: viseme)
            for name in VisemeMorphMap.targets(for: viseme).keys {
                XCTAssertFalse(name.isEmpty)
            }
        }
    }
}
