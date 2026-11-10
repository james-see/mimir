import AVFAudio
import XCTest
@testable import MimirCore

// MARK: - Fakes

private final class FakeLLM: LanguageModel, @unchecked Sendable {
    struct Step {
        var tokens: [String]
        var error: Error?
        var delay: Duration?
    }

    var script: [Step]
    private(set) var receivedMessages: [[ChatMessage]] = []

    init(script: [Step] = []) {
        self.script = script
    }

    func stream(messages: [ChatMessage], config: LLMConfig) -> AsyncThrowingStream<String, Error> {
        receivedMessages.append(messages)
        let step = script.isEmpty ? Step(tokens: [], error: nil, delay: nil) : script.removeFirst()
        return AsyncThrowingStream { continuation in
            Task {
                if let delay = step.delay {
                    do {
                        try await Task.sleep(for: delay)
                    } catch {
                        continuation.finish()
                        return
                    }
                }
                for token in step.tokens {
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    continuation.yield(token)
                }
                continuation.finish(throwing: step.error)
            }
        }
    }
}

/// Never yields, never finishes — used to exercise interrupt().
private struct HangingLLM: LanguageModel {
    func stream(messages: [ChatMessage], config: LLMConfig) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { _ in }
    }
}

private final class FakeSynthesizer: SpeechSynthesizer, @unchecked Sendable {
    private(set) var calls: [String] = []

    func synthesize(_ text: String, voice: String?) async throws -> SynthesizedSpeech {
        calls.append(text)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4410)!
        buffer.frameLength = 4410
        return SynthesizedSpeech(audio: buffer, sampleRate: 44100, phonemeTimings: nil)
    }
}

private final class FakeVisemes: VisemeEngine, @unchecked Sendable {
    private(set) var speechCount = 0

    func cues(for speech: SynthesizedSpeech) -> [VisemeCue] {
        speechCount += 1
        return [VisemeCue(time: 0, id: .aa, weight: 1)]
    }
}

private final class FakePlayer: SpeechPlayback, @unchecked Sendable {
    private(set) var enqueued: [UUID] = []
    private(set) var stopAllCalls = 0

    func enqueue(_ speech: SynthesizedSpeech, visemes: [VisemeCue]) -> UUID {
        let id = UUID()
        enqueued.append(id)
        return id
    }

    func stopAll() { stopAllCalls += 1 }

    /// Instant-drain fake: playback is over the moment you ask.
    func waitUntilDrained() async {}
}

private final class StateRecorder: @unchecked Sendable {
    private(set) var states: [AvatarState] = []
    func record(_ state: AvatarState) { states.append(state) }
}

private final class ErrorRecorder: @unchecked Sendable {
    private(set) var errors: [Error] = []
    func record(_ error: Error) { errors.append(error) }
}

// MARK: - Tests

final class ConversationEngineTests: XCTestCase {

    private func makeEngine(
        llm: any LanguageModel,
        synth: FakeSynthesizer = FakeSynthesizer(),
        visemes: FakeVisemes = FakeVisemes(),
        player: FakePlayer = FakePlayer(),
        recorder: StateRecorder? = nil,
        errors: ErrorRecorder? = nil
    ) async -> ConversationEngine {
        let engine = ConversationEngine(
            llm: llm,
            synthesizer: synth,
            visemes: visemes,
            player: player,
            config: LLMConfig()
        )
        if let recorder {
            await engine.setHandlers(state: { recorder.record($0) })
        }
        if let errors {
            await engine.setHandlers(error: { errors.record($0) })
        }
        return engine
    }

    func testFullConversationPipeline() async {
        let llm = FakeLLM(script: [
            .init(tokens: ["The sky", " is blue.", " Water is", " wet."])
        ])
        let synth = FakeSynthesizer()
        let player = FakePlayer()
        let recorder = StateRecorder()
        let engine = await makeEngine(llm: llm, synth: synth, player: player, recorder: recorder)

        await engine.ask("why is the sky blue?")
        await engine.waitForCurrentTurn()

        let history = await engine.history
        XCTAssertEqual(history.map(\.role), [.user, .assistant])
        XCTAssertEqual(history.last?.content, "The sky is blue. Water is wet.")
        XCTAssertEqual(synth.calls, ["The sky is blue.", "Water is wet."])
        XCTAssertEqual(player.enqueued.count, 2)
        XCTAssertEqual(recorder.states, [.thinking, .speaking, .listening])
    }

    func testPersonaAndHistorySentToLLM() async {
        let llm = FakeLLM(script: [
            .init(tokens: ["First answer."]),
            .init(tokens: ["Second answer."]),
        ])
        let engine = await makeEngine(llm: llm)

        await engine.ask("question one")
        await engine.waitForCurrentTurn()
        await engine.ask("question two")
        await engine.waitForCurrentTurn()

        XCTAssertEqual(llm.receivedMessages.count, 2)
        let first = llm.receivedMessages[0]
        XCTAssertEqual(first.first?.role, .system)
        XCTAssertTrue(first.first?.content.contains("Mimir") ?? false)
        XCTAssertEqual(first.last?.content, "question one")
        // Second turn carries the assistant's earlier answer.
        XCTAssertEqual(llm.receivedMessages[1].map(\.role), [.system, .user, .assistant, .user])
    }

    func testInterruptStopsPlaybackAndPartialKept() async {
        let llm = HangingLLM()
        let player = FakePlayer()
        let engine = await makeEngine(llm: llm, player: player)

        await engine.ask("this will hang")
        try? await Task.sleep(for: .milliseconds(50))
        await engine.interrupt()

        XCTAssertEqual(player.stopAllCalls, 1)
        let state = await engine.state
        XCTAssertEqual(state, .listening)
        // Only the user's question is in history — nothing was generated.
        let roles = await engine.history.map(\.role)
        XCTAssertEqual(roles, [.user])
    }

    func testLLMErrorSurfacesAndResetsState() async {
        let llm = FakeLLM(script: [
            .init(tokens: [], error: LLMError.http(500))
        ])
        let errors = ErrorRecorder()
        let engine = await makeEngine(llm: llm, errors: errors)

        await engine.ask("boom")
        await engine.waitForCurrentTurn()

        XCTAssertEqual(errors.errors.count, 1)
        XCTAssertEqual(errors.errors.first as? LLMError, .http(500))
        let state = await engine.state
        XCTAssertEqual(state, .listening)
        let roles = await engine.history.map(\.role)
        XCTAssertEqual(roles, [.user])
    }

    func testPartialAnswerKeptOnMidStreamError() async {
        let llm = FakeLLM(script: [
            .init(tokens: ["The sky", " is blue."], error: LLMError.transport("dropped"))
        ])
        let synth = FakeSynthesizer()
        let engine = await makeEngine(llm: llm, synth: synth)

        await engine.ask("color?")
        await engine.waitForCurrentTurn()

        let history = await engine.history
        XCTAssertEqual(history.map(\.role), [.user, .assistant])
        XCTAssertEqual(history.last?.content, "The sky is blue.")
        // The completed sentence still made it to speech before the error.
        XCTAssertEqual(synth.calls, ["The sky is blue."])
    }

    func testEmptyAskIgnored() async {
        let llm = FakeLLM(script: [.init(tokens: ["unused"])])
        let engine = await makeEngine(llm: llm)

        await engine.ask("   ")
        await engine.waitForCurrentTurn()

        let historyEmpty = await engine.history.isEmpty
        XCTAssertTrue(historyEmpty)
        let state = await engine.state
        XCTAssertEqual(state, .idle)
        XCTAssertTrue(llm.receivedMessages.isEmpty)
    }

    func testBargeInAskCancelsPreviousTurn() async {
        let llm = FakeLLM(script: [
            .init(tokens: ["Slow answer."], delay: .milliseconds(300)),
            .init(tokens: ["Second answer."]),
        ])
        let player = FakePlayer()
        let recorder = StateRecorder()
        let engine = await makeEngine(llm: llm, player: player, recorder: recorder)

        await engine.ask("one")
        try? await Task.sleep(for: .milliseconds(30))
        await engine.ask("two")  // interrupts turn one before it generates
        await engine.waitForCurrentTurn()

        XCTAssertGreaterThanOrEqual(player.stopAllCalls, 1)
        let history = await engine.history
        // The cancelled first turn contributed no assistant message.
        XCTAssertEqual(history.map(\.role), [.user, .user, .assistant])
        XCTAssertEqual(history.last?.content, "Second answer.")
        // States walked: thinking(1) -> listening(interrupt) -> thinking(2)
        // -> speaking(2) -> listening(2 done).
        XCTAssertEqual(recorder.states, [.thinking, .listening, .thinking, .speaking, .listening])
    }
}
