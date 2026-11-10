import AVFAudio
import Foundation
import MimirCore
import Synchronization

/// End-to-end smoke: real Ollama → real Kokoro → real audio out, with the
/// latency budget measured. Run: `swift run --package-path MimirCore MimirE2E`
print("Mimir E2E — real brain, real voice, real speakers")
print(String(repeating: "—", count: 48))

struct Metrics {
    var chunksScheduled = 0
    var firstToken: TimeInterval?
    var firstChunkDelay: TimeInterval?
}

let metrics = Mutex(Metrics())
let t0 = Date()

guard let assets = ModelBootstrap().existingAssets() else {
    fatalError("Kokoro assets missing — run the app once (or ModelBootstrap.ensureAssets) first")
}

let player = AudioPlayer()
let askStamp = Mutex(Date.distantPast)
player.onScheduled = { _, cues, start in
    let scheduled = Date()
    metrics.withLock { m in
        m.chunksScheduled += 1
        if m.firstChunkDelay == nil {
            m.firstChunkDelay = askStamp.withLock { scheduled.timeIntervalSince($0) }
        }
    }
    print(String(format: "  [player] chunk enqueued, audible in %.2fs, %2d viseme cues",
                 start.timeIntervalSinceNow, cues.count))
}

let synthesizer = try KokoroSynthesizer(modelURL: assets.modelURL, voicesURL: assets.voicesURL)
print(String(format: "[boot] Kokoro loaded in %.2fs", Date().timeIntervalSince(t0)))
await synthesizer.warmUp()
print(String(format: "[boot] warm-up synth done at %.2fs", Date().timeIntervalSince(t0)))

let engine = ConversationEngine(
    llm: OpenAICompatibleLLM(),
    synthesizer: synthesizer,
    visemes: DefaultVisemeEngine(),
    player: player,
    config: LLMConfig()
)

let stateStamp = t0
await engine.setHandlers(
    state: { newState in
        print(String(format: "[state] %@  (+%.2fs)", newState.rawValue, Date().timeIntervalSince(stateStamp)))
    },
    token: { _ in
        metrics.withLock { m in
            if m.firstToken == nil {
                m.firstToken = Date().timeIntervalSince(stateStamp)
                print(String(format: "[llm] first token (+%.2fs)", m.firstToken!))
            }
        }
    },
    error: { print("[error] \($0.localizedDescription)") }
)

let question = "Why is the sky blue? Answer in exactly one sentence."
print("Q: \(question)")
askStamp.withLock { $0 = Date() }
await engine.ask(question)
await engine.waitForCurrentTurn()

let history = await engine.history
let answer = history.last(where: { $0.role == .assistant })?.content ?? "(none)"
let m = metrics.withLock { $0 }
print(String(repeating: "—", count: 48))
print("A: \(answer)")
print(String(format: "first token: %.2fs | end-of-speech → first audio: %.2fs | total: %.2fs | chunks: %d",
             m.firstToken ?? -1, m.firstChunkDelay ?? -1, Date().timeIntervalSince(t0), m.chunksScheduled))
print(String(format: "BUDGET end-of-speech → first audio: %.2fs (target < 2.0s)", m.firstChunkDelay ?? -1))
