import Foundation

/// The conversation's current posture — drives the head's idle/expression
/// layer and the UI state pill.
public enum AvatarState: String, Sendable, Equatable {
    case idle
    case listening
    case thinking
    case speaking
}
