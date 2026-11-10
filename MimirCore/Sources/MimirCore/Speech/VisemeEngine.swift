import Foundation

/// The twelve-shape viseme set (Oculus/Papagayo style) the avatar driver
/// animates from. Mapped to ARKit morph names downstream in
/// `VisemeMorphMap` (SceneKit layer).
public enum Viseme: String, Sendable, CaseIterable {
    case rest
    case aa, ee, ih, oh, oo      // vowels
    case mbp                     // bilabials: m, b, p — lips closed
    case fv                      // labiodentals: f, v
    case th                      // dentals: th
    case l                       // lateral l
    case sz                      // sibilants: s, z
    case kg                      // velars: k, g
    case r                       // rhotics
}

/// A mouth shape at a point in time, scheduled relative to the start of the
/// audio buffer it was derived from.
public struct VisemeCue: Sendable, Equatable {
    public let time: TimeInterval
    public let id: Viseme
    public let weight: Float

    public init(time: TimeInterval, id: Viseme, weight: Float) {
        self.time = time
        self.id = id
        self.weight = min(max(weight, 0), 1)
    }
}

/// Audio in, timed mouth shapes out. Implementations: envelope DSP
/// (works with any audio) or phoneme-aligned (when the TTS exposes timings).
public protocol VisemeEngine: Sendable {
    func cues(for speech: SynthesizedSpeech) -> [VisemeCue]
}
