import Foundation

/// Maps the 12-viseme set onto ARKit-style blend shape (morph target) names.
///
/// Only morphs in this table are driven by the viseme layer; blinks/gaze live
/// in IdleDriver so they never fight over the same targets. Every entry must
/// exist in the bundled head asset — enforced by HeadAssetValidationTests.
public enum VisemeMorphMap {
    /// Morph name → target weight for the base set we drive.
    public static func targets(for viseme: Viseme) -> [String: Float] {
        switch viseme {
        case .rest:
            [:]
        case .aa:
            ["jawOpen": 0.85, "mouthFunnel": 0.1]
        case .ee:
            ["jawOpen": 0.3, "mouthSmileLeft": 0.6, "mouthSmileRight": 0.6]
        case .ih:
            ["jawOpen": 0.35]
        case .oh:
            ["jawOpen": 0.5, "mouthFunnel": 0.55]
        case .oo:
            ["jawOpen": 0.18, "mouthFunnel": 0.75]
        case .mbp:
            ["mouthClose": 1.0]
        case .fv:
            // Lower lip to upper teeth — closest we have without a lip-curl morph.
            ["jawOpen": 0.1, "mouthClose": 0.35]
        case .th:
            ["jawOpen": 0.22, "tongueOut": 0.25]
        case .l:
            ["jawOpen": 0.3, "mouthSmileLeft": 0.2, "mouthSmileRight": 0.2]
        case .sz:
            ["jawOpen": 0.08, "mouthSmileLeft": 0.35, "mouthSmileRight": 0.35]
        case .kg:
            ["jawOpen": 0.38]
        case .r:
            ["jawOpen": 0.28, "mouthFunnel": 0.3]
        }
    }

    /// Jaw-open amount for the primitive placeholder head (no morph targets).
    public static func jawWeight(for viseme: Viseme) -> Float {
        switch viseme {
        case .rest, .mbp: 0
        case .aa: 1.0
        case .oh: 0.6
        case .ih, .kg: 0.45
        case .ee, .l, .r: 0.3
        case .oo: 0.25
        case .th: 0.2
        case .fv: 0.12
        case .sz: 0.05
        }
    }

    /// Every morph target name referenced above.
    public static var referencedMorphNames: Set<String> {
        var names = Set<String>()
        for viseme in Viseme.allCases {
            for name in targets(for: viseme).keys {
                names.insert(name)
            }
        }
        return names
    }
}
