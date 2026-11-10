import Foundation
import MimirCore
import QuartzCore
import SceneKit

/// Renders the placeholder head offscreen so you can review it without the UI.
/// Run: `swift run --package-path MimirCore MimirHeadshot`
/// Writes /tmp/mimir-head-idle.png and /tmp/mimir-head-speaking.png.

guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("no Metal device")
}

func shot(avatar: SceneKitAvatar, time: CFTimeInterval, path: String) {
    let renderer = SCNRenderer(device: device, options: nil)
    renderer.scene = avatar.scene
    let image = renderer.snapshot(atTime: time, with: CGSize(width: 720, height: 720), antialiasingMode: .multisampling4X)
    guard let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("could not encode snapshot")
    }
    try! png.write(to: URL(fileURLWithPath: path))
    print("wrote \(path)")
}

// Idle pose.
let avatar = SceneKitAvatar()
for frame in 0..<10 { avatar.tick(at: Double(frame) * 0.016) }

// Debug isolate: MIMIR_DEBUG_ONLY=<r>,<g>,<b> hides everything except
// geometries whose material diffuse matches (±0.05 per channel).
if let only = ProcessInfo.processInfo.environment["MIMIR_DEBUG_ONLY"] {
    let parts: [CGFloat] = only.split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
    if parts.count == 3 {
        for node in avatar.scene.rootNode.descendants {
            guard node.geometry != nil else { continue }  // never hide group nodes
            let keep = node.geometry!.materials.contains { material in
                guard let c = (material.diffuse.contents as? NSColor)?.usingColorSpace(.deviceRGB) else { return false }
                return abs(c.redComponent - parts[0]) < 0.05
                    && abs(c.greenComponent - parts[1]) < 0.05
                    && abs(c.blueComponent - parts[2]) < 0.05
            } ?? false
            node.isHidden = !keep
        }
        print("isolated to material \(parts)")
    }
}

// Debug list: MIMIR_DEBUG_LIST=1 prints each unique material's diffuse color
// and how many geometries use it — no painting, no risk.
if ProcessInfo.processInfo.environment["MIMIR_DEBUG_LIST"] == "1" {
    var seen: [ObjectIdentifier: (rgb: (CGFloat, CGFloat, CGFloat), uses: Int)] = [:]
    for node in avatar.scene.rootNode.descendants {
        guard let geometry = node.geometry else { continue }
        for material in geometry.materials {
            let id = ObjectIdentifier(material)
            if seen[id] != nil {
                seen[id]!.uses += 1
                continue
            }
            if let color = (material.diffuse.contents as? NSColor)?.usingColorSpace(.deviceRGB) {
                seen[id] = ((color.redComponent, color.greenComponent, color.blueComponent), 1)
            } else {
                seen[id] = ((-1, -1, -1), 1)
            }
        }
    }
    for (id, info) in seen {
        print(String(format: "material %@ rgb=(%.3f, %.3f, %.3f) uses=%d",
                     String(describing: id), info.rgb.0, info.rgb.1, info.rgb.2, info.uses))
    }
}

// Debug skin: MIMIR_DEBUG_SKIN=1 paints geometry classes in saturated colors
// (skull red, hair+beard green, eyes blue) to identify what's where.
if ProcessInfo.processInfo.environment["MIMIR_DEBUG_SKIN"] == "1" {
    // Materials are SHARED between nodes (one `skin` serves skull, nose,
    // ears...), so paint must key off the material's own color, not the node.
    var painted: [ObjectIdentifier: NSColor] = [:]
    for node in avatar.scene.rootNode.descendants {
        guard let geometry = node.geometry else { continue }
        for material in geometry.materials {
            let id = ObjectIdentifier(material)
            if let color = painted[id] {
                material.diffuse.contents = color
                continue
            }
            let base = material.diffuse.contents as? NSColor
            let target: NSColor
            switch (base?.redComponent ?? 0, base?.greenComponent ?? 0, base?.blueComponent ?? 0) {
            case let (r, g, b) where r > 0.8 && g > 0.5 && g < 0.75 && b < 0.65: target = .red      // skin
            case let (r, g, b) where r > 0.9 && g > 0.55 && g < 0.75 && b > 0.45 && b < 0.65: target = .orange // blush
            case let (r, g, b) where abs(r - g) < 0.05 && abs(g - b) < 0.05 && r > 0.5 && r < 0.7: target = .green // grayHair
            case let (r, g, b) where r > 0.95 && g > 0.95 && b > 0.95: target = .blue               // eye white
            case let (r, g, _) where r < 0.2 && g < 0.15: target = .black                            // dark
            case let (r, _, b) where b > 0.28 && r < 0.25: target = .cyan                            // cloth
            case let (r, g, b) where r < 0.25 && g < 0.25 && b < 0.25: target = .yellow              // lensMetal
            default: target = .magenta
            }
            painted[id] = target
            material.diffuse.contents = target
        }
    }
    print("debug skin applied")
}

shot(avatar: avatar, time: 0.16, path: "/tmp/mimir-head-idle.png")

// Speaking pose: an open 'aa' viseme already active.
let speaking = SceneKitAvatar()
speaking.applyState(.speaking)
speaking.setVisemes([VisemeCue(time: 0, id: .aa, weight: 1)], startingAt: Date().addingTimeInterval(-1))
for frame in 0..<40 { speaking.tick(at: Double(frame) * 0.016) }
shot(avatar: speaking, time: 0.64, path: "/tmp/mimir-head-speaking.png")

// Mouth shape contact sheet inputs: same camera, distinct articulation.
if let directory = ProcessInfo.processInfo.environment["MIMIR_MOUTH_POSES"] {
    try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    for viseme in [Viseme.rest, .aa, .oo, .ee, .mbp] {
        let pose = SceneKitAvatar()
        pose.setVisemes([VisemeCue(time: 0, id: viseme, weight: 1)], startingAt: Date().addingTimeInterval(-1))
        for frame in 0..<40 { pose.tick(at: Double(frame) * 0.016) }
        shot(avatar: pose, time: 0.64, path: directory + "/" + viseme.rawValue + ".png")
    }
}
