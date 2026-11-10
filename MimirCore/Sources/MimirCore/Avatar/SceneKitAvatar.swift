import SceneKit

extension SCNNode {
    /// All nodes below this one, recursively (SceneKit has no built-in
    /// flat list; `enumerateChildNodes` walks the subtree).
    var descendants: [SCNNode] {
        var all: [SCNNode] = []
        enumerateChildNodes { node, _ in all.append(node) }
        return all
    }
}

/// The 3D head: a SceneKit scene containing a (placeholder or asset-backed)
/// head, driven by viseme cues on the real output clock, with idle life and
/// a conversational state posture.
///
/// Threading contract: scene graph mutation happens only at init (main
/// thread) or in `renderer(_:updateAtTime:)` (SceneKit render thread, where
/// scene-graph edits are sanctioned). Everything callable from other threads
/// (`setVisemes`, `clearVisemes`, `applyState`) parks values under `lock`
/// and the render tick applies them.
public final class SceneKitAvatar: NSObject, AvatarRenderer, SCNSceneRendererDelegate, @unchecked Sendable {
    public let scene = SCNScene()

    /// Node name lookup keys used by tests and the asset validator.
    public static let placeholderJawNodeName = "placeholder_jaw"
    public static let placeholderEyePrefix = "placeholder_eye"

    private let headRoot = SCNNode()
    private var morphNode: SCNNode?
    private var jawNode: SCNNode?
    private var eyeNodes: [SCNNode] = []

    private let lock = NSLock()
    private var idle = IdleDriver()
    private var lastTick: TimeInterval = 0

    private var cueQueue: [(time: Date, viseme: Viseme, weight: Float)] = []
    private var displayedMorphs: [String: Float] = [:]
    private var displayedJaw: Float = 0
    private var posture: (pitch: Float, yaw: Float, roll: Float) = (0, 0, 0)
    private var posturePerk: Float = 0

    /// Placeholder head until Assets/Head.usdz exists (Task 9).
    public override init() {
        super.init()
        setupCameraAndLights()
        loadPlaceholderHead()
    }

    public init(headURL: URL) throws {
        super.init()
        setupCameraAndLights()
        try loadHead(from: headURL)
    }

    // MARK: - AvatarRenderer (any-thread entry points)

    public func setVisemes(_ cues: [VisemeCue], startingAt start: Date) {
        let absolute = cues.map { (time: start.addingTimeInterval($0.time), viseme: $0.id, weight: $0.weight) }
        lock.lock()
        cueQueue.append(contentsOf: absolute)
        cueQueue.sort { $0.time < $1.time }
        lock.unlock()
    }

    public func clearVisemes() {
        lock.lock()
        cueQueue.removeAll()
        lock.unlock()
    }

    public func applyState(_ state: AvatarState) {
        lock.lock()
        switch state {
        case .idle: posture = (0, 0, 0); posturePerk = 0
        case .listening: posture = (0.05, 0, 0.0); posturePerk = 0.12
        case .thinking: posture = (-0.08, 0.0, 0.05); posturePerk = 0.3
        case .speaking: posture = (0.02, 0, 0.0); posturePerk = 0.18
        }
        lock.unlock()
    }

    // MARK: - Render tick

    public func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        tick(at: time)
    }

    /// Visible for testing. Applies one frame of animation.
    func tick(at time: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }

        let dt = lastTick == 0 ? 0.016 : min(time - lastTick, 0.1)
        lastTick = time
        idle.advance(to: time)

        // --- Viseme: find the cue active *now* (Date-based, real output clock)
        let now = Date()
        while cueQueue.count > 1 && cueQueue[1].time <= now {
            cueQueue.removeFirst()
        }
        var desiredViseme: Viseme = .rest
        var desiredWeight: Float = 0
        if let first = cueQueue.first {
            if first.time <= now {
                desiredViseme = first.viseme
                desiredWeight = first.weight
            }
        }

        // --- Smooth mouth toward desired shape (≈60 ms constant)
        let ease = Float(1 - exp(-dt / 0.06))
        var desiredMorphs = VisemeMorphMap.targets(for: desiredViseme)
        for key in desiredMorphs.keys { desiredMorphs[key]! *= desiredWeight }
        if idle.blinkWeight > 0 {
            // Blink rides on top of any viseme state.
            desiredMorphs["eyeBlinkLeft"] = max(idle.blinkWeight, desiredMorphs["eyeBlinkLeft"] ?? 0)
            desiredMorphs["eyeBlinkRight"] = max(idle.blinkWeight, desiredMorphs["eyeBlinkRight"] ?? 0)
        }
        desiredMorphs["browInnerUp"] = max(posturePerk, desiredMorphs["browInnerUp"] ?? 0)

        let allKeys = Set(displayedMorphs.keys).union(desiredMorphs.keys)
        for key in allKeys {
            let from = displayedMorphs[key] ?? 0
            let to = desiredMorphs[key] ?? 0
            let value = from + (to - from) * ease
            displayedMorphs[key] = value
            morphNode?.morpher?.setWeight(CGFloat(value), forTargetNamed: key)
        }

        // --- Placeholder jaw drive
        let desiredJaw = VisemeMorphMap.jawWeight(for: desiredViseme) * desiredWeight * 0.5
        displayedJaw += (desiredJaw - displayedJaw) * ease
        jawNode?.eulerAngles.x = CGFloat(displayedJaw)
        for eye in eyeNodes {
            eye.scale.y = CGFloat(1 - 0.85 * idle.blinkWeight)
        }

        // --- Posture + idle motion on the whole head
        let easePosture: Float = 0.08
        let targetPitch = posture.pitch + idle.sway.x + idle.gaze.y
        let targetYaw = posture.yaw + idle.sway.y + idle.gaze.x
        let targetRoll = posture.roll
        let x = headRoot.eulerAngles.x
        let y = headRoot.eulerAngles.y
        let z = headRoot.eulerAngles.z
        headRoot.eulerAngles.x = x + CGFloat((targetPitch - Float(x)) * easePosture)
        headRoot.eulerAngles.y = y + CGFloat((targetYaw - Float(y)) * easePosture)
        headRoot.eulerAngles.z = z + CGFloat((targetRoll - Float(z)) * easePosture)
    }

    // MARK: - Scene setup

    private func setupCameraAndLights() {
        let camera = SCNCamera()
        camera.zNear = 0.01
        camera.zFar = 10
        let cameraNode = SCNNode()
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0.1, 1.05)
        cameraNode.look(at: SCNVector3(0, 0.05, 0))
        scene.rootNode.addChildNode(cameraNode)

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 350
        ambient.color = NSColor(white: 0.9, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        let key = SCNLight()
        key.type = .omni
        key.intensity = 900
        key.color = NSColor(red: 1, green: 0.96, blue: 0.9, alpha: 1)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = SCNVector3(0.8, 1.4, 1.6)
        scene.rootNode.addChildNode(keyNode)

        let fill = SCNLight()
        fill.type = .omni
        fill.intensity = 350
        fill.color = NSColor(red: 0.75, green: 0.82, blue: 1, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        fillNode.position = SCNVector3(-1.2, 0.4, 1.2)
        scene.rootNode.addChildNode(fillNode)
    }

    // MARK: - Asset loading

    private func loadHead(from url: URL) throws {
        let loaded = try SCNScene(url: url, options: nil)
        for child in loaded.rootNode.childNodes {
            headRoot.addChildNode(child)
        }
        morphNode = headRoot.descendants.first { $0.morpher != nil }
        scene.rootNode.addChildNode(headRoot)
    }

    /// The build-today head: stylized primitives with a hinged jaw and
    /// squishable eyes. Keeps every upstream system (visemes, states, idle)
    /// fully exercisable until the realistic asset lands.
    private func loadPlaceholderHead() {
        func material(_ color: NSColor, roughness: CGFloat = 0.85) -> SCNMaterial {
            let material = SCNMaterial()
            material.diffuse.contents = color
            material.roughness.contents = roughness
            material.lightingModel = .physicallyBased
            return material
        }

        let skin = material(NSColor(red: 0.85, green: 0.66, blue: 0.55, alpha: 1))
        let hair = material(NSColor(red: 0.22, green: 0.16, blue: 0.12, alpha: 1))
        let white = material(NSColor.white, roughness: 0.3)
        let dark = material(NSColor(red: 0.08, green: 0.06, blue: 0.05, alpha: 1))
        let cloth = material(NSColor(red: 0.16, green: 0.2, blue: 0.32, alpha: 1))

        // Shoulders + neck.
        let shoulders = SCNCapsule(capRadius: 0.16, height: 0.1)
        shoulders.materials = [cloth]
        let shouldersNode = SCNNode(geometry: shoulders)
        shouldersNode.position = SCNVector3(0, -0.18, 0)
        shouldersNode.scale = SCNVector3(1.6, 0.6, 0.8)
        scene.rootNode.addChildNode(shouldersNode)

        let neck = SCNCylinder(radius: 0.045, height: 0.09)
        neck.materials = [skin]
        let neckNode = SCNNode(geometry: neck)
        neckNode.position = SCNVector3(0, -0.075, 0)
        headRoot.addChildNode(neckNode)
        scene.rootNode.addChildNode(headRoot)

        // Cranium.
        let skull = SCNSphere(radius: 0.16)
        skull.segmentCount = 48
        skull.materials = [skin]
        let skullNode = SCNNode(geometry: skull)
        skullNode.name = "placeholder_head"
        skullNode.position = SCNVector3(0, 0.1, 0)
        skullNode.scale = SCNVector3(1, 1.12, 0.98)
        headRoot.addChildNode(skullNode)

        // Hair mass behind/above the face line.
        let hairCap = SCNSphere(radius: 0.155)
        hairCap.segmentCount = 48
        hairCap.materials = [hair]
        let hairNode = SCNNode(geometry: hairCap)
        hairNode.position = SCNVector3(0, 0.155, -0.025)
        hairNode.scale = SCNVector3(1.02, 1.05, 0.99)
        headRoot.addChildNode(hairNode)

        // Ears.
        for side: Float in [-1, 1] {
            let ear = SCNSphere(radius: 0.028)
            ear.materials = [skin]
            let earNode = SCNNode(geometry: ear)
            earNode.position = SCNVector3(CGFloat(side) * 0.158, 0.1, 0)
            earNode.scale = SCNVector3(0.4, 1, 0.7)
            headRoot.addChildNode(earNode)
        }

        // Eyes (white + pupil), brows.
        for side: Float in [-1, 1] {
            let eye = SCNSphere(radius: 0.024)
            eye.materials = [white]
            let eyeNode = SCNNode(geometry: eye)
            eyeNode.name = "\(Self.placeholderEyePrefix)\(side < 0 ? "_l" : "_r")"
            eyeNode.position = SCNVector3(CGFloat(side) * 0.055, 0.125, 0.142)
            headRoot.addChildNode(eyeNode)
            eyeNodes.append(eyeNode)

            let pupil = SCNSphere(radius: 0.0105)
            pupil.materials = [dark]
            let pupilNode = SCNNode(geometry: pupil)
            pupilNode.position = SCNVector3(0, 0, 0.0165)
            eyeNode.addChildNode(pupilNode)

            let brow = SCNCapsule(capRadius: 0.006, height: 0.045)
            brow.materials = [hair]
            let browNode = SCNNode(geometry: brow)
            browNode.position = SCNVector3(CGFloat(side) * 0.058, 0.168, 0.148)
            browNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
            headRoot.addChildNode(browNode)
        }

        // Nose.
        let nose = SCNSphere(radius: 0.02)
        nose.materials = [skin]
        let noseNode = SCNNode(geometry: nose)
        noseNode.position = SCNVector3(0, 0.085, 0.16)
        noseNode.scale = SCNVector3(0.7, 2, 0.8)
        headRoot.addChildNode(noseNode)

        // Jaw: hinged at the hinges of the mandible — pivot near the temples,
        // geometry hanging below-forward so rotating opens the mouth.
        let jawPivot = SCNNode()
        jawPivot.name = Self.placeholderJawNodeName
        jawPivot.position = SCNVector3(0, 0.02, 0.02)
        headRoot.addChildNode(jawPivot)

        let chin = SCNSphere(radius: 0.09)
        chin.segmentCount = 32
        chin.materials = [skin]
        let chinNode = SCNNode(geometry: chin)
        chinNode.position = SCNVector3(0, -0.015, 0.055)
        chinNode.scale = SCNVector3(0.85, 0.75, 0.8)
        jawPivot.addChildNode(chinNode)

        let mouth = SCNCapsule(capRadius: 0.009, height: 0.06)
        mouth.materials = [dark]
        let mouthNode = SCNNode(geometry: mouth)
        mouthNode.position = SCNVector3(0, 0.008, 0.125)
        mouthNode.eulerAngles = SCNVector3(0, 0, CGFloat.pi / 2)
        jawPivot.addChildNode(mouthNode)

        jawNode = jawPivot
    }
}
