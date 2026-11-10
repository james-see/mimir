import AVFAudio
import Foundation

/// Zero-dependency emergency voice: macOS `say` renders speech to an AIFF
/// file, which we read back as PCM. Keeps the whole pipeline alive when the
/// Kokoro model can't be used (download failed, low disk, CI).
///
/// Why not `AVSpeechSynthesizer.write(_:toBufferCallback:)`? In practice it
/// silently delivers zero buffers without a runloop dance, so the file-based
/// `say` path is the reliable no-app-context fallback.
public struct SystemSynthesizer: SpeechSynthesizer {
    public enum SynthesisError: Error, Equatable {
        case renderingFailed
    }

    public init() {}

    public func synthesize(_ text: String, voice: String?) async throws -> SynthesizedSpeech {
        try await Task.detached(priority: .userInitiated) { () throws -> SynthesizedSpeech in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent("mimir-say-\(UUID().uuidString).aiff")
            defer { try? FileManager.default.removeItem(at: output) }

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/say")
            var arguments: [String] = []
            if let voice { arguments += ["-v", voice] }
            arguments += ["-o", output.path, text]
            process.arguments = arguments

            do {
                try process.run()
            } catch {
                throw SynthesisError.renderingFailed
            }
            process.waitUntilExit()
            guard process.terminationStatus == 0,
                  let file = try? AVAudioFile(forReading: output) else {
                throw SynthesisError.renderingFailed
            }

            let format = AVAudioFormat(
                standardFormatWithSampleRate: file.processingFormat.sampleRate,
                channels: 1
            )!
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(max(file.length, 1))
            ) else {
                throw SynthesisError.renderingFailed
            }
            do {
                try file.read(into: buffer)
            } catch {
                throw SynthesisError.renderingFailed
            }
            return SynthesizedSpeech(audio: buffer, sampleRate: format.sampleRate, phonemeTimings: nil)
        }.value
    }
}
