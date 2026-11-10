import Foundation

/// The face on screen. Two conformance paths exist: the placeholder jaw
/// driver (primitive head) and the real morph-target driver (USDZ head) —
/// the concrete class is `SceneKitAvatar`, which picks based on the loaded
/// asset. Scene graph mutation happens on the render thread inside
/// `renderer(_:updateAtTime:)`; state arrives from any thread under a lock.
public protocol AvatarRenderer: AnyObject {
    /// Schedule a viseme track whose times are relative to `start`.
    func setVisemes(_ cues: [VisemeCue], startingAt start: Date)
    /// Drop all pending mouth shapes immediately (barge-in).
    func clearVisemes()
    /// Reflect conversation posture (idle/listening/thinking/speaking).
    func applyState(_ state: AvatarState)
}
