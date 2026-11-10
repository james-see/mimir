import Foundation

/// The pipeline orchestrator: user question → LLM stream → sentence chunks →
/// TTS → queued playback + visemes, with a driving state machine.
///
/// Turn ownership: every generation task captures a monotonically increasing
/// turn id. Writes to `history`/`state` at the end of a turn are discarded if
/// the turn was superseded (barge-in), so a cancelled slow turn can never
/// clobber a newer turn's state.
public actor ConversationEngine {
    public static let defaultPersona = """
    You are Mimir, a patient and brilliant teacher. Answer clearly and concisely in \
    spoken language — short sentences, no markdown, no bullet lists, no emoji. When \
    a topic is deep, give the essential idea first, then offer to go further.
    """

    public private(set) var state: AvatarState = .idle
    public private(set) var history: [ChatMessage] = []

    public var persona: String
    public var voice: String?
    public var onStateChange: (@Sendable (AvatarState) -> Void)?
    public var onAssistantToken: (@Sendable (String) -> Void)?
    /// Ordering-safe streaming display: each call carries the full text so
    /// far, so UI can just replace. (A dropped/out-of-order callback never
    /// corrupts the transcript.)
    public var onAssistantText: (@Sendable (String) -> Void)?
    public var onError: (@Sendable (Error) -> Void)?

    private let llm: any LanguageModel
    private let synthesizer: any SpeechSynthesizer
    private let visemes: any VisemeEngine
    private let player: any SpeechPlayback
    private var llmConfig: LLMConfig

    private var currentTask: Task<Void, Never>?
    private var turnCounter = 0

    public init(
        llm: any LanguageModel,
        synthesizer: any SpeechSynthesizer,
        visemes: any VisemeEngine,
        player: any SpeechPlayback,
        config: LLMConfig,
        persona: String = ConversationEngine.defaultPersona,
        voice: String? = nil
    ) {
        self.llm = llm
        self.synthesizer = synthesizer
        self.visemes = visemes
        self.player = player
        self.llmConfig = config
        self.persona = persona
        self.voice = voice
    }

    public func configure(_ config: LLMConfig, persona: String, voice: String?) {
        llmConfig = config
        self.persona = persona
        self.voice = voice
    }

    public func restoreHistory(_ messages: [ChatMessage]) {
        guard state != .thinking && state != .speaking else { return }
        history = messages.filter { $0.role != .system }
    }

    public func setLLMConfig(_ config: LLMConfig) {
        llmConfig = config
    }

    /// Convenience for wiring UI/test observers from outside the actor.
    public func setHandlers(
        state: (@Sendable (AvatarState) -> Void)? = nil,
        token: (@Sendable (String) -> Void)? = nil,
        text: (@Sendable (String) -> Void)? = nil,
        error: (@Sendable (Error) -> Void)? = nil
    ) {
        if let state { onStateChange = state }
        if let token { onAssistantToken = token }
        if let text { onAssistantText = text }
        if let error { onError = error }
    }

    /// Ask a question. If a turn is in flight it is interrupted first.
    public func ask(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if currentTask != nil {
            interruptLocked()
        }
        history.append(ChatMessage(role: .user, content: trimmed))
        setState(.thinking)
        turnCounter += 1
        let id = turnCounter
        currentTask = Task { [weak self] in
            await self?.runTurn(id: id)
        }
    }

    /// Barge-in: cancel generation and stop audio immediately.
    public func interrupt() {
        interruptLocked()
    }

    /// Await the current turn's completion (tests; UI scripting).
    public func waitForCurrentTurn() async {
        await currentTask?.value
    }

    // MARK: - Internals

    private func interruptLocked() {
        currentTask?.cancel()
        currentTask = nil
        player.stopAll()
        if state == .thinking || state == .speaking {
            setState(.listening)
        }
    }

    private func runTurn(id: Int) async {
        var chunker = SentenceChunker()
        var answer = ""
        let messages = [ChatMessage(role: .system, content: persona)] + history
        do {
            for try await token in llm.stream(messages: messages, config: llmConfig) {
                try Task.checkCancellation()
                answer += token
                onAssistantToken?(token)
                onAssistantText?(answer)
                if let chunk = chunker.consume(token) {
                    try await speak(chunk)
                }
            }
            if let tail = chunker.flush() {
                try await speak(tail)
            }
            guard id == turnCounter else { return }
            if !answer.isEmpty {
                history.append(ChatMessage(role: .assistant, content: answer))
            }
            await player.waitUntilDrained()
            guard id == turnCounter else { return }
            setState(.listening)
        } catch {
            guard id == turnCounter else { return }
            if !answer.isEmpty {
                history.append(ChatMessage(role: .assistant, content: answer))
            }
            if !(error is CancellationError) {
                onError?(error)
                setState(.listening)
            }
        }
    }

    private func speak(_ sentence: String) async throws {
        let speech = try await synthesizer.synthesize(sentence, voice: voice)
        try Task.checkCancellation()
        let track = visemes.cues(for: speech)
        player.enqueue(speech, visemes: track)
        if state != .speaking {
            setState(.speaking)
        }
    }

    private func setState(_ newValue: AvatarState) {
        guard newValue != state else { return }
        state = newValue
        onStateChange?(newValue)
    }
}
