# Yapper

Fast, Apple Silicon-native text-to-speech. CLI tool and embeddable Swift library, powered by [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) via [MLX](https://github.com/ml-explore/mlx-swift).

> **Status: Work in progress.** The core inference engine is complete and producing high-quality speech. CLI commands and audiobook generation are under active development.

## What it does

Yapper synthesizes natural-sounding speech from text, running entirely on-device via Metal GPU acceleration. No Python, no cloud APIs, no internet connection required.

```bash
# Speak text aloud
yapper speak "Hello, this is yapper."

# Custom pronunciation for names the G2P gets wrong
yapper speak "Hello [Taḋg](/taɪɡ/), how are you today?"

# List available voices
yapper voices

# Convert a text file to audio
yapper convert notes.txt -o notes.m4a

# Convert an epub to an audiobook with chapter markers
yapper convert book.epub -o book.m4b
```

## Why

High-quality text-to-speech is an accessibility technology that gives real, meaningful benefit to people with disability. It should be open source, fast, and free from commercial paywalls. Yapper exists to make that a reality on Apple Silicon.

Existing Kokoro TTS tools rely on Python runtimes (ONNX, PyTorch) that don't fully exploit M-series hardware. Yapper replaces that stack with native Swift + Metal inference, running entirely on-device with no cloud dependencies.

## Features

**Working now (v0.3.0):**

- Full Kokoro-82M inference pipeline in Swift - BERT encoder, duration/prosody prediction, HiFi-GAN decoder, iSTFT
- 28 built-in voices (American/British, male/female)
- Sentence-level text chunking for arbitrarily long input
- Speed control (0.5x-2.0x)
- Word-level timestamps
- Live audio playback via AVAudioEngine
- Numerically identical output to [KokoroSwift](https://github.com/mlalma/kokoro-ios) (verified at every pipeline stage)

**In progress:**

- CLI commands (`speak`, `voices`, `convert`)
- Document conversion (epub, PDF, docx, odt, markdown, HTML, mobi)
- Audiobook generation with chapter markers (M4B) and per-chapter voice assignment
- Pronunciation customization (user dictionary, Irish names!, per-project overrides)
- Clipboard and screen selection reading

**Planned:**
- iOS support (YapperKit is portable - no macOS-specific APIs)
- Homebrew formula
- GUI wrapper
- Multiple language support

## Requirements

- macOS 15+ (Sequoia) on Apple Silicon
- Xcode 16+ with Metal Toolchain (`xcodebuild -downloadComponent MetalToolchain`)
- [Kokoro-82M model weights](#model-setup) (~327MB)

### Runtime tools (for file conversion only)

- `ffmpeg` - audio encoding (`brew install ffmpeg`)
- `pandoc` - document conversion (`brew install pandoc`)
- `pdftotext` - PDF extraction (`brew install poppler`)
- `ebook-convert` - mobi support (install [Calibre](https://calibre-ebook.com))

## Quickstart

### Build

```bash
git clone https://github.com/tigger04/yapper.git
cd yapper
make build
make install    # symlinks to ~/.local/bin/yapper
```

### Model setup

Download the Kokoro-82M model weights and at least one voice:

```bash
mkdir -p ~/.local/share/yapper/models ~/.local/share/yapper/voices

# Model weights (~327MB)
curl -L -o ~/.local/share/yapper/models/kokoro-v1_0.safetensors \
  "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/kokoro-v1_0.safetensors"

# Config
curl -L -o ~/.local/share/yapper/models/config.json \
  "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/config.json"

# Voices (download as many as you like, ~522KB each)
for voice in af_heart af_bella am_adam bf_emma bm_daniel; do
  curl -L -o ~/.local/share/yapper/voices/${voice}.safetensors \
    "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/voices/${voice}.safetensors"
done
```

### Test

```bash
make test    # runs 39 regression tests
```

## Architecture

Yapper is structured as two layers:

- **YapperKit** - Swift library. Handles model loading, inference, streaming audio, and voice management. Embeddable in other Swift projects via Swift Package Manager.
- **yapper** - CLI tool built on YapperKit. Handles document conversion, chapter detection, and audiobook assembly.

The inference pipeline implements the full Kokoro-82M architecture (StyleTTS2-based, 82M parameters, non-autoregressive) using [MLX Swift](https://github.com/ml-explore/mlx-swift) for Metal-accelerated computation. Grapheme-to-phoneme conversion uses [MisakiSwift](https://github.com/mlalma/MisakiSwift). The pipeline was developed using [KokoroSwift](https://github.com/mlalma/kokoro-ios) as a reference implementation.

For details, see [docs/architecture.md](docs/architecture.md) and [docs/VISION.md](docs/VISION.md).

## Project structure

```
Sources/
├── YapperKit/          # Embeddable TTS library
│   ├── Engine/         # YapperEngine, TextChunker
│   ├── Inference/      # Kokoro-82M pipeline (17 files)
│   ├── Audio/          # AudioPlayer, MelSpectrogram
│   ├── Voice/          # VoiceRegistry, Voice types
│   └── Timestamps/     # WordTimestamp
└── yapper/             # CLI tool
    └── Commands/       # speak, voices, convert

Tests/regression/       # 39 regression tests
docs/                   # VISION, architecture, implementation plan
```

## Documentation

- [Vision](docs/VISION.md) - goals, use cases, and future plans
- [Architecture](docs/architecture.md) - system design, inference pipeline, build system
- [Implementation plan](docs/implementation_plan.md) - phased delivery, issue tracking

## Acknowledgements

- [hexgrad/Kokoro](https://github.com/hexgrad/kokoro) - the [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) model ([Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0))
- [mlalma/kokoro-ios](https://github.com/mlalma/kokoro-ios) - KokoroSwift, the reference implementation ([MIT](https://opensource.org/licenses/MIT))
- [mlalma/MisakiSwift](https://github.com/mlalma/MisakiSwift) - grapheme-to-phoneme library ([Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0))
- [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) - [Apple](https://github.com/ml-explore)'s MLX framework for Swift ([MIT](https://opensource.org/licenses/MIT))
- [apple/swift-argument-parser](https://github.com/apple/swift-argument-parser) - CLI argument parsing ([Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0))
- Kokoro-82M training data: [Koniwa](https://github.com/koniwa/koniwa) ([CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)), [SIWIS](https://datashare.ed.ac.uk/handle/10283/2353) ([CC BY 4.0](https://creativecommons.org/licenses/by/4.0/))

See [NOTICE](NOTICE) for full attribution details.

## Licence

Apache 2.0 - Copyright Taḋg Paul. See [LICENSE](LICENSE).
