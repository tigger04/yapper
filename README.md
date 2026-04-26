# Yapper

Fast, Apple Silicon-native text-to-speech. CLI tool and embeddable Swift library, powered by [Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) via [MLX](https://github.com/ml-explore/mlx-swift).

## What it does

Yapper synthesizes natural-sounding speech from text, running entirely on-device via Metal GPU acceleration. No Python, no cloud APIs, no internet connection required.

```bash
# Speak text aloud - picks a random voice each time by default
yap "Hello, this is yapper."

# `yap` is shorthand for `yapper speak`. The two are exactly equivalent;
# every flag below also works with the full `yapper speak` form.

# Pin a specific voice for one invocation
yap --voice bf_emma "Hello, this is yapper."

# Or pin it for the whole shell session
export YAPPER_VOICE=bm_daniel
yap "Now I sound like Daniel every time."

# Check which voice would be used, without synthesizing anything
yap --dry-run "Hello, this is yapper."

# Custom pronunciation for names the G2P gets wrong
yap "Hello [Taḋg](/taɪɡ/), how are you today?"

# List available voices
yapper voices

# Preview all British female voices
yapper voices --preview bf

# Convert a text file to audio
yapper convert notes.txt -o notes.m4a

# Convert an epub to an audiobook with chapter markers
yapper convert book.epub -o book.m4b

# Convert multiple files into one audiobook
yapper convert *.md -o collection.m4b

# Convert a play/screenplay to a multi-voice audiobook
# (place a script.yaml alongside the script file — see docs/script-reading.md)
yapper convert play.org

# Preview script conversion without synthesising
yapper convert play.fountain --dry-run
```

### Voice selection

`yapper speak` resolves the voice to use from three sources, in order of priority:

1. **`--voice <name>`** - the CLI flag wins unconditionally
2. **`$YAPPER_VOICE`** - an environment variable for persistent per-shell preferences
3. **Random** - a different voice on every invocation, drawn from all installed voices

To set a persistent default in your shell init:

```bash
# ~/.zshrc or ~/.bashrc
export YAPPER_VOICE=bm_daniel
```

If `$YAPPER_VOICE` is set to a name that doesn't exist, `yapper speak` exits with a clear error rather than silently falling back - typos don't get hidden. The same applies to `--voice`.

`yapper speak --dry-run` reports the resolved voice (plus speed and text) without performing synthesis or playing audio. Useful for confirming which voice would be selected, and fast because it skips the 327 MB model load entirely.

### Configuration

Yapper loads YAML config files in a cascade: global (`~/.config/yapper/yapper.yaml`), project (`./yapper.yaml` or `./script.yaml`), and CLI (`--script-config`). Higher-precedence files override individual keys while inheriting the rest.

Use the global config for pronunciation overrides that apply everywhere:

```yaml
# ~/.config/yapper/yapper.yaml
speech-substitution:
  Taḋg: "/taɪɡ/"
  Cáit: Kawch
```

Use a project config for script-specific settings (voices, pacing, metadata). See [docs/config.md](docs/config.md) for the full reference.

## Why

High-quality text-to-speech is an accessibility technology that gives real, meaningful benefit to people with disability. It should be open source, fast, and free from commercial paywalls. Yapper exists to make that a reality on Apple Silicon.

Existing Kokoro TTS tools rely on Python runtimes (ONNX, PyTorch) that don't fully exploit M-series hardware. Yapper replaces that stack with native Swift + Metal inference, running entirely on-device with no cloud dependencies.

## What makes yapper different

Most Kokoro TTS implementations are Python-based (ONNX, PyTorch) and designed for single-file, single-voice synthesis. Yapper is built from the ground up for Apple Silicon and goes further:

- **Native Metal inference** - no Python runtime, no ONNX, no cloud. The full Kokoro-82M pipeline runs in Swift via MLX, exploiting unified memory and GPU cores directly.
- **Multi-voice script reading** - convert plays and screenplays to audiobooks with distinct voices per character, narrator-read stage directions, and configurable pacing. No other Kokoro tool does this.
- **Concurrent synthesis** - multi-process GPU parallelism (3 workers by default) for 1.65x faster script conversion. Each worker gets its own Metal context.
- **Audiobook-first** - M4B output with chapter markers, metadata, and cover art. Convert epubs, markdown, org-mode scripts, or plain text to audiobooks in one command.
- **Production pacing controls** - configurable gaps between dialogue, stage directions, and scenes. Per-type speech speed. Adjust pacing without re-synthesis.
- **Script intelligence** - automatic Title Case conversion for ALL-CAPS character names in stage directions (prevents letter-by-letter spelling). Footnote rendering as narrator asides. Preamble synthesis with cast introduction.
- **Pronunciation overrides** - both inline IPA (`[Taḋg](/taɪɡ/)`) for prose and bulk `speech-substitution` mappings in script config for regional names.

## Features

- Full Kokoro-82M inference pipeline in Swift - BERT encoder, duration/prosody prediction, HiFi-GAN decoder, iSTFT
- 28 built-in English voices (American and British, male and female)
- CLI commands: `speak`, `voices`, `convert` + `yap` shorthand
- Voice selection: `--voice` flag, `$YAPPER_VOICE` env var, or random per invocation
- Voice preview with filter shorthands: `yapper voices --preview bf` previews all British female voices
- `--dry-run` on both `speak` and `convert`
- Document conversion: epub, PDF, docx, odt, markdown, HTML, mobi, plain text
- Audiobook generation with M4B chapter markers and per-chapter voice assignment
- M4A/MP3 output with ID3 metadata (artist, album, track number, track title)
- Text cleanup: strips residual markup from pandoc-extracted documents before synthesis
- Sentence-level text chunking for arbitrarily long input
- Speed control (0.5x-2.0x)
- Word-level timestamps
- Custom pronunciation via inline IPA: `[Name](/phonemes/)`
- Script reading: multi-voice plays/screenplays from markdown or org-mode (see [docs/script-reading.md](docs/script-reading.md))
- Concurrent multi-process synthesis for script mode (configurable thread count)
- Configurable inter-line gaps and per-type speech speed
- Preamble rendering: title, author, character introductions, outline
- Footnote rendering as narrator asides (org-mode `[fn:name]`)
- Speech substitution for pronunciation overrides (`speech-substitution` in config)
- Stage direction character names automatically Title Cased
- Per-line audio trimming (Whisper-based or heuristic) for precise gap control
- Numerically identical output to [KokoroSwift](https://github.com/mlalma/kokoro-ios) (verified at every pipeline stage)
- Homebrew distribution: Developer ID signed, Apple notarised
- `--non-interactive` flag for scripted/CI usage

**Planned:**
- [Fountain](https://fountain.io) screenplay format support (`.fountain`)
- iOS support (YapperKit is portable - no macOS-specific APIs)
- GUI wrapper
- Multiple language support
- Clipboard and screen selection reading

## Requirements

- macOS 15+ (Sequoia) on Apple Silicon
- [Kokoro-82M model weights](#from-source) (~327 MB, downloaded automatically by Homebrew)

### Runtime tools (for file conversion only)

- `ffmpeg` - audio encoding (`brew install ffmpeg`)
- `pandoc` - document conversion (`brew install pandoc`)
- `pdftotext` - PDF extraction (`brew install poppler`)
- `ebook-convert` - mobi support (install [Calibre](https://calibre-ebook.com))

## Quickstart

```bash
brew install tigger04/tap/yapper
```

Model weights and 28 English voices are downloaded automatically. The binary is Developer ID signed and Apple notarised.

### From source

For development or if Homebrew is not available. Requires Xcode 26+ with the Metal Toolchain.

```bash
git clone https://github.com/tigger04/yapper.git
cd yapper
make build
make install    # installs yapper and yap to ~/.local/bin
```

Source builds require manual download of the model weights and voices:

```bash
mkdir -p ~/.local/share/yapper/models ~/.local/share/yapper/voices

# Model weights (~327 MB)
curl -L -o ~/.local/share/yapper/models/kokoro-v1_0.safetensors \
  "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/kokoro-v1_0.safetensors"

# Voices (download as many as you like, ~522 KB each)
for voice in af_heart af_bella am_adam bf_emma bm_daniel; do
  curl -L -o ~/.local/share/yapper/voices/${voice}.safetensors \
    "https://huggingface.co/mlx-community/Kokoro-82M-bf16/resolve/main/voices/${voice}.safetensors"
done
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
│   ├── Audio/          # AudiobookAssembler, MelSpectrogram
│   ├── Voice/          # VoiceRegistry, Voice types
│   └── Timestamps/     # WordTimestamp
└── yapper/             # CLI tool
    └── Commands/       # speak, voices, convert + yap (argv[0] dispatch)

Tests/
├── regression/
│   ├── YapperKitTests/ # Swift framework tests (88 tests)
│   └── cli/            # Bash CLI tests (247 tests)
└── one_off/            # Per-issue verification tests

Formula/                # Homebrew formula (regenerated by make release)
scripts/                # release.sh, release-models.sh, verify-signature.sh
docs/                   # VISION, architecture, script formats, research notes
```

## Makefile targets

| Target | Description |
|---|---|
| `make build` | Build the project via xcodebuild |
| `make test` | Run all regression tests (framework + CLI) |
| `make test-framework` | Run Swift framework tests only |
| `make test-cli` | Run bash CLI tests only |
| `make lint` | Run swiftlint |
| `make install` | Install yapper and yap to ~/.local/bin |
| `make uninstall` | Remove yapper and yap from ~/.local/bin |
| `make clean` | Remove build artefacts |
| `make sync` | Git sync: add, commit, pull, push (submodules first) |
| `make release` | Run tests, bump version, sign, notarise, tag, push, update Homebrew formula |
| `make release SKIP_TESTS=1` | Same as above but skip the regression pack |
| `make release-models` | Package and upload model weights + voices to models-v1 release |

## Documentation

- [Vision](docs/VISION.md) - goals, use cases, and future plans
- [Architecture](docs/architecture.md) - system design, inference pipeline, build system
- [Implementation plan](docs/implementation_plan.md) - phased delivery, issue tracking
- [Configuration](docs/config.md) - YAML config cascade, all keys, examples
- [Script reading](docs/script-reading.md) - multi-voice script conversion and pacing
- [Org-mode format](docs/format-org-mode.md) - org-mode script format specification
- [Markdown format](docs/format-markdown.md) - markdown script format specification
- [Fountain format](docs/format-fountain.md) - Fountain screenplay format specification
- [Research notes](docs/research_notes.md) - synthesis performance findings and optimization research

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
