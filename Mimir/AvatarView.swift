import MimirCore
import SceneKit
import SwiftUI

/// The SceneKit pane hosting the avatar. The view renders continuously so
/// idle animation (blinks, sway) stays alive between utterances.
struct AvatarView: NSViewRepresentable {
    let avatar: SceneKitAvatar

    func makeNSView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = avatar.scene
        view.delegate = avatar
        view.rendersContinuously = true
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        return view
    }

    func updateNSView(_ nsView: SCNView, context: Context) {}
}
