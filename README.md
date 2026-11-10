# Mimir

**An open-source AI teacher for macOS.** A realistic 3D head sits on your screen — ask it a question out loud, and it answers you in a spoken voice with lip-synced mouth movement. Named after Mímir, the Norse god whose severed head Odin carried for counsel.

## How it works

```
 mic ──▶ WhisperKit (on-device STT)
          │
          ▼
   LLM via OpenAI-compatible API (default: local Ollama, streamed)
          │  tokens
          ▼
   Sentence chunker (first clause out fast)
          │
          ▼
   Kokoro TTS (on-device, MLX Swift) ──▶ audio out
          │
          ▼ (same PCM)
   Viseme engine ──▶ SceneKit 3D head (ARKit morph targets, idle life)
```

Every stage is a Swift protocol (`LanguageModel`, `SpeechRecognizer`, `SpeechSynthesizer`, `VisemeEngine`, `AvatarRenderer`) so backends — including future photoreal renderers — slot in without touching the pipeline.

## Requirements

- macOS 15+, Apple Silicon recommended
- Xcode 26+ and [XcodeGen](https://github.com/yonsm/XcodeGen) (`brew install xcodegen`)
- [Ollama](https://ollama.com) running locally for the default brain (`ollama pull qwen2.5:7b`)

## Build & run

```sh
make gen      # generate Mimir.xcodeproj
make build    # build Debug
make test     # MimirCore unit tests (SPM)
make run      # build and open Mimir.app
```

## Status

Early development — v1 targets a fully on-device voice loop with a rigged 3D head. See the roadmap in the implementation plan for what's deliberately out of scope.

## License

MIT. Head asset provenance is documented in `tools/head-pipeline.md`.
