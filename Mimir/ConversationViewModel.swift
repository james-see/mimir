import Combine
import Foundation
import MimirCore
import SwiftUI

/// Glues the ConversationEngine to the window: mic in, avatar out, transcript
/// up the side. All callbacks hop to MainActor here; SceneKitAvatar guards
/// its own state, so viseme scheduling is forwarded inline.
@MainActor
final class ConversationViewModel: ObservableObject {
    struct Turn: Identifiable, Equatable {
        let id = UUID()
        let role: ChatMessage.Role
        let text: String
    }

    @Published private(set) var ready = false
    @Published private(set) var state: AvatarState = .idle
    @Published private(set) var turns: [Turn] = []
    @Published private(set) var streamingAssistant = ""
    @Published var draftInput = ""
    @Published private(set) var micEnabled = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var voiceNote: String?

    let avatar = SceneKitAvatar()

    private let player = AudioPlayer()
    private var engine: ConversationEngine?
    private var recognizer: WhisperKitRecognizer?
    private var listenTask: Task<Void, Never>?
    private var resumeMicTask: Task<Void, Never>?
    private var micSuspended = false
    private var lastStreamedLength = 0

    init(config: LLMConfig = LLMConfig(), autoDownloadVoice: Bool = false) {
        player.onScheduled = { [avatar] _, cues, start in
            avatar.setVisemes(cues, startingAt: start)
        }
        Task { await bootstrap(config: config, autoDownloadVoice: autoDownloadVoice) }
    }

    // MARK: - Bootstrap

    private func bootstrap(config: LLMConfig, autoDownloadVoice: Bool) async {
        let synthesizer: any SpeechSynthesizer
        var assets = ModelBootstrap().existingAssets()
        if assets == nil, autoDownloadVoice {
            assets = try? await ModelBootstrap().ensureAssets()
        }
        if let assets,
           let kokoro = try? KokoroSynthesizer(modelURL: assets.modelURL, voicesURL: assets.voicesURL) {
            await kokoro.warmUp()
            synthesizer = kokoro
        } else {
            synthesizer = SystemSynthesizer()
            if assets == nil {
                voiceNote = "System voice — Kokoro model not downloaded (Settings → Voice)"
            }
        }

        let engine = ConversationEngine(
            llm: OpenAICompatibleLLM(),
            synthesizer: synthesizer,
            visemes: DefaultVisemeEngine(),
            player: player,
            config: config
        )
        self.engine = engine

        await engine.setHandlers(
            state: { [weak self, avatar] newState in
                avatar.applyState(newState)
                Task { @MainActor [weak self] in self?.stateDidChange(newState) }
            },
            text: { [weak self] text in
                Task { @MainActor [weak self] in self?.assistantTextChanged(text) }
            },
            error: { [weak self] error in
                Task { @MainActor [weak self] in
                    self?.errorMessage = (error as? LLMError)?.description ?? error.localizedDescription
                }
            }
        )
        ready = true
    }

    // MARK: - Engine callbacks (MainActor)

    private func stateDidChange(_ newState: AvatarState) {
        state = newState
        resumeMicTask?.cancel()
        if newState == .thinking || newState == .speaking {
            suspendMic()
        } else {
            // Let the last speaker sound decay before accepting a new turn.
            resumeMicTask = Task { [weak self] in
                do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
                guard let self, self.micEnabled,
                      self.state != .thinking, self.state != .speaking else { return }
                self.micSuspended = false
                self.recognizer?.setSuspended(false)
            }
        }
        guard newState == .listening, let engine else { return }
        Task {
            let history = await engine.history
            turns = history.map { Turn(role: $0.role, text: $0.content) }
            streamingAssistant = ""
            lastStreamedLength = 0
        }
    }

    private func assistantTextChanged(_ text: String) {
        guard text.count > lastStreamedLength else { return }  // idempotent full-text updates
        lastStreamedLength = text.count
        streamingAssistant = text
    }

    // MARK: - User actions

    func send() {
        let text = draftInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draftInput = ""
        errorMessage = nil
        suspendMic()
        Task { await engine?.ask(text) }
    }

    func interrupt() {
        Task { await engine?.interrupt() }
        avatar.clearVisemes()
        streamingAssistant = ""
    }

    func toggleMic() {
        micEnabled ? stopMic() : startMic()
    }

    private func startMic() {
        let mic = WhisperKitRecognizer()
        recognizer = mic
        micEnabled = true
        micSuspended = state == .thinking || state == .speaking
        mic.setSuspended(micSuspended)
        listenTask = Task { [weak self, engine] in
            guard let self else { return }
            do {
                try await mic.start()
                for try await transcription in mic.transcriptionStream() {
                    guard !Task.isCancelled else { break }
                    guard !self.micSuspended else { continue }
                    if transcription.isFinal {
                        guard !transcription.text.isEmpty else { continue }
                        self.errorMessage = nil
                        self.suspendMic()
                        await engine?.ask(transcription.text)
                    }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.micEnabled = false
                }
            }
        }
    }

    private func suspendMic() {
        resumeMicTask?.cancel()
        micSuspended = true
        recognizer?.setSuspended(true)
    }

    private func stopMic() {
        resumeMicTask?.cancel()
        micSuspended = false
        listenTask?.cancel()
        listenTask = nil
        recognizer?.stop()
        recognizer = nil
        micEnabled = false
    }
}
