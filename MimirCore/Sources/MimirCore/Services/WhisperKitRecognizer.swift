import AVFAudio
import Foundation
import Synchronization
import WhisperKit

/// On-device speech recognition: utterances segmented by `UtteranceSegmenter`
/// (energy VAD), each segment decoded by Whisper (Core ML, via WhisperKit).
///
/// Design notes:
/// - Mic tap converts hardware audio to 16 kHz mono Float32 for Whisper.
/// - All WhisperKit state lives inside `EngineBox` (an actor) — `WhisperKit`
///   is a non-Sendable class, so every touch funnels through there.
/// - Shared mutable state uses `Mutex` (NSLock is banned in async contexts).
/// - Verified manually per plan (mic-dependent); the segmenter is the
///   unit-tested part.
public final class WhisperKitRecognizer: SpeechRecognizer, @unchecked Sendable {
    public enum RecognizerError: Error, Equatable, CustomStringConvertible {
        case converterUnavailable
        case permissionDenied

        public var description: String {
            switch self {
            case .converterUnavailable: "Could not build the 16 kHz mic converter"
            case .permissionDenied: "Microphone permission denied"
            }
        }
    }

    private struct MutableState {
        var engine: AVAudioEngine?
        var segmenter: UtteranceSegmenter
    }

    private let model: String
    private let state: Mutex<MutableState>
    private let engineBox = EngineBox()
    private let continuation: AsyncThrowingStream<Transcription, Error>.Continuation
    private let stream: AsyncThrowingStream<Transcription, Error>

    public init(model: String = "openai_whisper-base", segmenter: UtteranceSegmenter = UtteranceSegmenter()) {
        self.model = model
        self.state = Mutex(MutableState(engine: nil, segmenter: segmenter))
        var stored: AsyncThrowingStream<Transcription, Error>.Continuation!
        self.stream = AsyncThrowingStream { stored = $0 }
        self.continuation = stored
    }

    public func transcriptionStream() -> AsyncThrowingStream<Transcription, Error> {
        stream
    }

    public func start() async throws {
        let alreadyRunning = state.withLock { $0.engine != nil }
        guard !alreadyRunning else { return }

        guard await AVAudioApplication.requestRecordPermission() else {
            throw RecognizerError.permissionDenied
        }
        // Load the model before touching the mic so first-run downloads are
        // surfaced as errors rather than eaten silence.
        try await engineBox.prepare(model: model)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let hardwareFormat = input.inputFormat(forBus: 0)
        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        )!
        guard let converter = AVAudioConverter(from: hardwareFormat, to: targetFormat) else {
            throw RecognizerError.converterUnavailable
        }

        input.installTap(onBus: 0, bufferSize: 4096, format: hardwareFormat) { [weak self] buffer, _ in
            self?.handleTap(buffer: buffer, converter: converter, targetFormat: targetFormat)
        }
        try engine.start()
        state.withLock { $0.engine = engine }
    }

    public func stop() {
        let engine = state.withLock { state -> AVAudioEngine? in
            defer {
                state.engine = nil
                state.segmenter.reset()
            }
            return state.engine
        }
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
    }

    // MARK: - Internals

    /// Runs on the realtime audio thread — keep it cheap: convert, measure,
    /// segment; heavy Whisper work is dispatched to a task.
    private func handleTap(
        buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let capacity = AVAudioFrameCount(
            ceil(Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate) + 64
        )
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0,
              let channel = converted.floatChannelData?[0] else { return }

        let count = Int(converted.frameLength)
        let samples = Array(UnsafeBufferPointer(start: channel, count: count))
        var sum: Float = 0
        for sample in samples { sum += sample * sample }
        let rms = (sum / Float(count)).squareRoot()

        let events = state.withLock { $0.segmenter.process(rms: rms, samples: samples) }

        for event in events {
            switch event {
            case .speechStart:
                // Live-mic signal for barge-in (UI interrupt when mid-answer).
                continuation.yield(Transcription(text: "", isFinal: false))
            case .utteranceEnd(let audio):
                Task { [engineBox, continuation] in
                    do {
                        let text = try await engineBox.transcribe(audio)
                        if !text.isEmpty {
                            continuation.yield(Transcription(text: text, isFinal: true))
                        }
                    } catch {
                        // Transcription hiccups are non-fatal; skip the turn.
                    }
                }
            }
        }
    }

    /// WhisperKit holder — the only place the non-Sendable class is touched.
    private actor EngineBox {
        private var kit: WhisperKit?

        func prepare(model: String) async throws {
            if kit == nil {
                kit = try await WhisperKit(WhisperKitConfig(model: model))
            }
        }

        func transcribe(_ audio: [Float]) async throws -> String {
            guard let kit else {
                enum Unprepared: Error { case missing }
                throw Unprepared.missing
            }
            let results = try await kit.transcribe(audioArray: audio)
            return results.map(\.text).joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
