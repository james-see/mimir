import Foundation

/// Idle life for the avatar: blinks, gaze wander, and breathing-sway.
///
/// Pure struct, driven by scene time — fully testable. The renderer samples
/// the outputs every frame and applies them where the asset allows (blink
/// morphs on a rigged head, eye-squish on the placeholder).
public struct IdleDriver: Sendable {
    /// 0…1, 1 = eyes fully closed.
    public private(set) var blinkWeight: Float = 0
    /// Small head wander in radians.
    public private(set) var sway: (x: Float, y: Float) = (0, 0)
    /// Small gaze/head-intent offset in radians.
    public private(set) var gaze: (x: Float, y: Float) = (0, 0)

    private let blinkDuration: TimeInterval = 0.12
    private let blinkInterval: ClosedRange<TimeInterval> = 2.8...6.5
    private let gazeInterval: ClosedRange<TimeInterval> = 1.5...4.0
    private let gazeMagnitude: Float = 0.05

    private var nextBlinkAt: TimeInterval
    private var blinkStart: TimeInterval?
    private var nextGazeAt: TimeInterval
    private var gazeTarget: (x: Float, y: Float) = (0, 0)

    public init(now: TimeInterval = 0) {
        nextBlinkAt = now + 2.5
        nextGazeAt = now + 1.0
    }

    public mutating func advance(to time: TimeInterval) {
        // Blink: single sine pulse over blinkDuration.
        if blinkStart == nil, time >= nextBlinkAt {
            blinkStart = time
        }
        if let start = blinkStart {
            let phase = (time - start) / blinkDuration
            if phase >= 1 {
                blinkStart = nil
                blinkWeight = 0
                nextBlinkAt = time + .random(in: blinkInterval)
            } else {
                blinkWeight = Float(sin(.pi * phase))
            }
        }

        // Gaze wander: retarget on a schedule, ease toward it.
        if time >= nextGazeAt {
            nextGazeAt = time + .random(in: gazeInterval)
            gazeTarget = (
                x: .random(in: -gazeMagnitude...gazeMagnitude),
                y: .random(in: -gazeMagnitude...gazeMagnitude)
            )
        }
        gaze.x += (gazeTarget.x - gaze.x) * 0.08
        gaze.y += (gazeTarget.y - gaze.y) * 0.08

        // Breathing sway: two slow detuned sinusoids.
        sway = (
            x: Float(0.012 * Foundation.sin(time * 0.31)),
            y: Float(0.009 * Foundation.sin(time * 0.43 + 1.7))
        )
    }
}
