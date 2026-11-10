import Foundation

/// Invalidates in-flight decoding whenever microphone input is suspended.
/// Generation checks also reject results that finish after input resumes.
struct RecognitionGate {
    private(set) var suspended = false
    private(set) var generation: UInt64 = 0

    mutating func setSuspended(_ value: Bool) {
        guard value != suspended else { return }
        suspended = value
        generation &+= 1
    }

    func accepts(_ token: UInt64) -> Bool {
        !suspended && token == generation
    }
}
