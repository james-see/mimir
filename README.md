# Mimir

**An open-source AI teacher for macOS.** A realistic 3D head sits on your screen — ask it a question out loud, and it answers you in a spoken voice with lip-synced mouth movement. Named after Mímir, the Norse god whose severed head Odin carried for counsel.

> Live site: https://james-see.github.io/mimir/  
> Releases: https://github.com/james-see/mimir/releases

## Features

* On-device voice loop: mic → WhisperKit STT → LLM → Kokoro TTS → audio out
* Real-time SceneKit avatar with viseme-driven lip sync and idle life
* Fully on-device by default — Ollama + MLX Swift models, no cloud required
* Settings UI for model selection, voice, microphone, and privacy controls
* Persistent conversations and transcripts stored locally
* Modular Swift protocol architecture — swap STT/TTS/LLM/Renderer without touching pipeline

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

* macOS 15+ , Apple Silicon recommended
* Xcode 26+ and [XcodeGen](https://github.com/yonsm/XcodeGen) — `brew install xcodegen`
* [Ollama](https://ollama.com) running locally for the default brain
  ```sh
  ollama pull huihui_ai/qwen3-abliterated:4b-instruct-2507-q4_K_M
  ```
* ~8 GB free for models on first run

## Quick start

```sh
git clone https://github.com/james-see/mimir.git
cd mimir
make gen      # generate Mimir.xcodeproj
make build    # build Debug
make test     # MimirCore unit tests
make run      # build and open Mimir.app
```

### Release build / notarize

```sh
make release
make signed-release   # Developer ID sign
make notarize         # sign + notarize + staple
```

The release script is `tools/release.py`. It signs nested Mach-O binaries with Developer ID, staples a notarization ticket and outputs `build/dist/Mimir-macOS-arm64.zip`.

## Configuration

### Settings

Open Mimir → Settings to configure:

* **Model provider** — Ollama URL, model name, context length
* **Voice** — Kokoro voice preset, speech rate, pitch
* **Microphone** — input device selection, VAD threshold
* **Privacy** — local-only mode, disable transcript saving, clear history

Settings are persisted via `MimirCore/Services/TeacherSettings.swift` and stored in the app container.

### API key

If you use a remote OpenAI-compatible endpoint, set the key in Settings → API Key. The key is stored in the keychain via `Mimir/APIKeyStore.swift`.

## Privacy

* All audio processing is on-device by default
* Transcripts are saved locally under `~/Library/Application Support/Mimir/transcripts/`
* No telemetry is sent. The app requests microphone access only while listening.

## Usage

1. Launch Mimir.app
2. Grant microphone permission on first launch
3. Speak — the avatar listens, the head animates, and answers with spoken voice
4. Use the transcript pane to review conversation history
5. Settings → Export to export transcripts as Markdown

### Known limitations

* First audio latency is ~3.5s on a 4B model; target is <2s
* Real-time photoreal neural avatars are out of scope for v1
* macOS 15+ only

## Development

### Project layout

```
Mimir/                # App UI, SwiftUI
MimirCore/            # Core services, protocols, models
tools/                # release.py, head-pipeline
docs/                 # GitHub Pages
```

### Tests

```sh
make test
```

Unit tests live in `MimirCore/Tests`.

### Roadmap

* Hold-space push-to-talk
* Rigged 3D head improvements and idle life tuning
* Latency tuning: Kokoro warm-up, clause-level chunking
* Optional realistic head renderer

See the implementation plan for details.

## License

MIT. Head asset provenance is documented in `tools/head-pipeline.md`.

## Credits

* WhisperKit, Kokoro TTS, MLX Swift
* SceneKit avatar pipeline
