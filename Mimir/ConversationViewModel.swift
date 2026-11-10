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
    @Published private(set) var availableVoices: [String] = []
    private let transcriptStore = TranscriptStore()
    private var conversationID = UUID()
    private var lastSavedMessages: [ChatMessage] = []
    private var preferences = TeacherSettings.load()
    var isResponding: Bool { state == .thinking || state == .speaking }

    func applySettings(_ settings: TeacherSettings, apiKey: String) async throws {
        let config = try settings.config(apiKey: apiKey)
        try APIKeyStore.save(apiKey)
        try settings.save()
        preferences = settings
        await engine?.configure(config, persona: settings.persona, voice: availableVoices.isEmpty ? nil : settings.voice)
    }

    func showSavedFiles() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Mimir")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(directory)
    }

    func newConversation() {
        guard !isResponding else { return }
        Task {
            await engine?.restoreHistory([])
            conversationID = UUID()
            lastSavedMessages = []
            if preferences.saveConversations {
                do { try await transcriptStore.append(.init(id: conversationID, messages: [])) }
                catch { errorMessage = "Could not save new conversation: \(error.localizedDescription)" }
            }
            turns = []
            streamingAssistant = ""
            lastStreamedLength = 0
        }
    }

    let avatar = SceneKitAvatar()

    private let player = AudioPlayer()
    private var engine: ConversationEngine?
    private var recognizer: WhisperKitRecognizer?
    private var listenTask: Task<Void, Never>?
    private var resumeMicTask: Task<Void, Never>?
    private var micSuspended = false
    private var lastStreamedLength = 0

    init(config: LLMConfig? = nil, autoDownloadVoice: Bool = true) {
        let resolved = config ?? (try? preferences.config(apiKey: APIKeyStore.read())) ?? LLMConfig()
        player.onScheduled = { [avatar] _, cues, start in
            avatar.setVisemes(cues, startingAt: start)
        }
        Task { await bootstrap(config: resolved, autoDownloadVoice: autoDownloadVoice) }
    }

    // MARK: - Bootstrap

    private func bootstrap(config: LLMConfig, autoDownloadVoice: Bool) async {
        let synthesizer: any SpeechSynthesizer
        var assets = ModelBootstrap().existingAssets()
        if assets == nil, autoDownloadVoice {
            voiceNote = "Preparing Kokoro voice model (first download is about 326 MiB)…"
            do { assets = try await ModelBootstrap().ensureAssets() }
            catch { errorMessage = "Voice download failed: \(error.localizedDescription). Using the system voice." }
        }
        if let assets,
           let kokoro = try? KokoroSynthesizer(modelURL: assets.modelURL, voicesURL: assets.voicesURL) {
            voiceNote = "Warming up voice…"
            availableVoices = await kokoro.availableVoices
            await kokoro.warmUp()
            voiceNote = nil
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
            config: config,
            persona: preferences.persona,
            voice: availableVoices.isEmpty ? nil : preferences.voice
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
        if preferences.saveConversations {
            do {
                if let saved = try await transcriptStore.load().last {
                    conversationID = saved.id
                    lastSavedMessages = saved.messages
                    await engine.restoreHistory(saved.messages)
                    turns = saved.messages.map { Turn(role: $0.role, text: $0.content) }
                }
            } catch { errorMessage = "Could not restore conversation: \(error.localizedDescription)" }
        }
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
            if preferences.saveConversations, history != lastSavedMessages {
                do {
                    try await transcriptStore.append(.init(id: conversationID, messages: history))
                    lastSavedMessages = history
                } catch { errorMessage = "Could not save conversation: \(error.localizedDescription)" }
            }
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
