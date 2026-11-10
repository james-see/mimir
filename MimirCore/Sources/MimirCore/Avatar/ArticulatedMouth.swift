import SceneKit

/// A small procedural lip rig, not a dark primitive attached to a hinge.
/// Aperture, width and protrusion interpolate independently per viseme.
/// Upper and lower vermilion surfaces share their inner edge with the cavity.
final class ArticulatedMouth {
    let root = SCNNode()
    let lips = SCNNode()
    let cavity = SCNNode()
    let teeth = SCNNode()
    let tongue = SCNNode()
    private(set) var opening: Float = 0
    private(set) var width: Float = 0.037
    private var protrusion: Float = 0

    init() {
        root.name = "articulated_mouth"
        lips.name = "mouth_lips"
        cavity.name = "mouth_cavity"
        teeth.name = "mouth_teeth"
        tongue.name = "mouth_tongue"
        func material(_ color: NSColor) -> SCNMaterial {
            let m = SCNMaterial()
            m.diffuse.contents = color
            m.lightingModel = .blinn
            m.specular.contents = NSColor(white: 0.12, alpha: 1)
            m.shininess = 0.3
            m.isDoubleSided = true
            return m
        }
        lips.geometry = SCNGeometry()
        lips.geometry?.materials = [material(NSColor(red: 0.57, green: 0.27, blue: 0.23, alpha: 1))]
        cavity.geometry = SCNGeometry()
        let inside = material(NSColor(red: 0.10, green: 0.025, blue: 0.035, alpha: 1))
        inside.lightingModel = .constant
        cavity.geometry?.materials = [inside]
        let tooth = SCNBox(width: 0.05, height: 0.007, length: 0.003, chamferRadius: 0.002)
        tooth.materials = [material(NSColor(red: 0.94, green: 0.90, blue: 0.79, alpha: 1))]
        teeth.geometry = tooth
        let tip = SCNSphere(radius: 1)
        tip.materials = [material(NSColor(red: 0.68, green: 0.27, blue: 0.31, alpha: 1))]
        tongue.geometry = tip
        for node in [cavity, teeth, tongue, lips] { root.addChildNode(node) }
        update(viseme: .rest, weight: 0, ease: 1)
    }

    static func pose(for viseme: Viseme) -> (opening: Float, width: Float, protrusion: Float) {
        switch viseme {
        case .rest, .mbp: return (0, 0.037, 0)
        case .aa: return (0.017, 0.039, 0)
        case .oh: return (0.014, 0.027, 0.008)
        case .oo: return (0.008, 0.019, 0.012)
        case .ee: return (0.006, 0.047, 0)
        case .ih: return (0.010, 0.040, 0)
        case .fv: return (0.003, 0.039, 0)
        case .th: return (0.007, 0.039, 0.002)
        case .l: return (0.011, 0.040, 0)
        case .sz: return (0.004, 0.044, 0)
        case .kg: return (0.012, 0.037, 0)
        case .r: return (0.008, 0.030, 0.006)
        }
    }

    func update(viseme: Viseme, weight: Float, ease: Float) {
        let target = Self.pose(for: viseme)
        let w = max(0, min(1, weight))
        opening += (target.opening * w - opening) * ease
        width += ((0.037 + (target.width - 0.037) * w) - width) * ease
        protrusion += (target.protrusion * w - protrusion) * ease
        // A fixed upper attachment and moving lower lip, not a floating hole.
        let centerY = -opening * 0.35
        let radiusY = max(0.00025, opening)
        let segments = 48
        var ring: [SCNVector3] = []
        var fill: [SCNVector3] = [SCNVector3(0, CGFloat(centerY), CGFloat(protrusion - 0.001))]
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * Float.pi
            let x = cos(a)
            let y = sin(a)
            let taper = pow(max(0, 1 - x * x), 0.65)
            let cupid = y > 0 ? -0.0015 * exp(-x * x * 35) : 0
            let innerY = centerY + y * radiusY + cupid * min(1, opening / 0.006)
            // Lip thickness tapers at the corners. Outer edge is skinward,
            // middle crest protrudes toward the viewer, inner edge rolls in.
            let thickness: Float = (y > 0 ? 0.004 : 0.0055) * taper + 0.0008
            for band in 0..<3 {
                let t = Float(band) / 2
                let py = innerY + (y >= 0 ? 1 : -1) * thickness * t
                let px = x * (width + 0.002 * t)
                let pz = protrusion + sin(t * Float.pi) * 0.0035
                ring.append(SCNVector3(CGFloat(px), CGFloat(py), CGFloat(pz)))
            }
            fill.append(SCNVector3(CGFloat(x * width), CGFloat(innerY), CGFloat(protrusion - 0.001)))
        }
        var indices: [Int32] = []
        var fan: [Int32] = []
        for i in 0..<segments {
            for band in 0..<2 {
                let a = Int32(i * 3 + band), b = a + 3
                indices += [a, b, a + 1, a + 1, b, b + 1]
            }
            fan += [0, Int32(i + 1), Int32(i + 2)]
        }
        func replace(_ node: SCNNode, vertices: [SCNVector3], indices: [Int32]) {
            let materials = node.geometry?.materials ?? []
            let normals = Array(repeating: SCNVector3(0, 0, 1), count: vertices.count)
            node.geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
            node.geometry?.materials = materials
        }
        replace(lips, vertices: ring, indices: indices)
        replace(cavity, vertices: fill, indices: fan)
        cavity.isHidden = opening < 0.001
        teeth.isHidden = opening < 0.004 || viseme == .oo || viseme == .oh
        teeth.scale.x = CGFloat(min(1, width / 0.037))
        teeth.position = SCNVector3(0, CGFloat(centerY + radiusY * 0.55), CGFloat(protrusion + 0.0005))
        tongue.isHidden = opening < 0.008 && viseme != .th
        tongue.scale = SCNVector3(CGFloat(width * 0.45), CGFloat(min(0.004, radiusY * 0.3)), 0.0015)
        tongue.position = SCNVector3(0, CGFloat(centerY - radiusY * 0.52), CGFloat(protrusion + 0.001))
    }
}
