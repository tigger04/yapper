<!-- Version: 0.2 | Last updated: 2026-04-02 -->

# Yapper — Implementation Plan

## Phasing

Work is divided into issues. Each issue is self-contained with its own ACs and tests. Issues are ordered by dependency — later issues build on earlier ones.

## Phase 1: Foundation

### Issue 1 — Project scaffolding

Set up the Swift package structure, Makefile, dependencies, and verify everything builds.

- Swift Package with two targets: `YapperKit` (library) and `yapper` (executable)
- Dependencies: MisakiSwift, MLX Swift (MLX, MLXNN, MLXRandom, MLXFFT), swift-argument-parser
- KokoroSwift is **not** a dependency — reference only
- Makefile targets: `build`, `test`, `install`, `uninstall`
- `make install` symlinks `yapper` to `~/.local/bin`
- Test directory structure: `Tests/regression/`, `Tests/one_off/`
- Verify it builds and runs `yapper --version`

### Issue 2 — Model and voice loading

YapperKit can load Kokoro-82M weights and voice embeddings from disk.

- Load model weights from `.safetensors` via `MLX.loadArrays(url:)`
- Load voice embeddings from `.npz` file
- `VoiceRegistry` enumerates available voices from the `.npz` entries
- `VoiceRegistry.load(name:)` returns the MLXArray for a voice embedding
- `VoiceRegistry.list(filter:)` filters by accent/gender
- `VoiceRegistry.random(filter:)` returns a random voice
- Default paths: `~/.local/share/yapper/models/` and `~/.local/share/yapper/voices/`
- Clear error messages when model files are missing

### Issue 3 — Inference pipeline

YapperKit can run the Kokoro inference pipeline: phonemes → BERT → duration → prosody → decoder → audio.

- Implement model architecture layers using MLXNN (referencing KokoroSwift's implementation):
  - BERT text encoder
  - Duration predictor
  - Prosody predictor
  - Decoder
  - iSTFT (inverse Short-Time Fourier Transform)
- Wire layers together with weights loaded from issue 2
- G2P via MisakiSwift: text → phonemes → token IDs
- `YapperEngine.synthesize(text:voice:speed:)` returns `AudioResult` with PCM at 24kHz
- Word-level timestamps derived from predicted phoneme durations
- Works for text within the 510-token limit
- Speed parameter controls speech rate

This is the largest single issue — it implements the core inference engine. KokoroSwift's source is the primary reference for layer wiring and weight mapping.

### Issue 4 — Text chunking

YapperKit handles text longer than 510 tokens by chunking at sentence boundaries.

- `TextChunker` splits text using `NLTokenizer(.sentence)`
- Greedy batching: pack consecutive sentences up to 510-token budget
- `synthesize()` transparently handles long text by chunking + concatenating
- Seamless audio across chunk boundaries (no clicks/gaps)
- Timestamps adjusted for cumulative offset across chunks

### Issue 5 — Live audio playback

YapperKit can play synthesised audio through the system speakers with pseudo-streaming.

- `AudioPlayer` wraps AVAudioEngine
- `stream()` method: synthesise chunk → push to audio engine → synthesise next chunk while playing
- First audio output within ~1 second of calling `stream()`
- Pause/resume/stop controls
- No intermediate files

## Phase 2: CLI — Core Commands

### Issue 6 — `yapper speak` command

CLI command for live TTS playback.

- `yapper speak "text"` — speak the argument
- `echo "text" | yapper speak` — speak from stdin
- `yapper speak < file.txt` — speak from file redirect
- `--voice NAME` and `--speed FLOAT` flags
- Uses AudioPlayer from issue 5

### Issue 7 — `yapper voices` command

CLI command to list and preview available voices.

- `yapper voices` — list all voices with name, accent, gender
- `yapper voices --preview NAME` — speak a sample sentence with the named voice

### Issue 8 — Plain text to MP3

CLI can convert a text file to MP3.

- `yapper convert input.txt -o output.mp3`
- Calls YapperKit for synthesis, ffmpeg for MP3 encoding
- ID3 tags: `--author`, `--title` flags
- Default output filename: same base name, `.mp3` extension

### Issue 9 — Epub parsing and chapter detection

CLI can extract chapters and metadata from epub files.

- Native epub parser: read OPF manifest, spine, and TOC (NCX/nav)
- Extract chapter titles and text content
- Extract metadata: title, author, cover image
- Strip HTML tags from chapter content
- Returns `[(title: String, text: String)]`

### Issue 10 — Document conversion pipeline

CLI can convert non-epub formats to chapter lists.

- PDF → pdftotext → heading-based chapter splitting
- docx/odt → pandoc → heading-based splitting
- md/html → pandoc or direct parse → heading-based splitting
- mobi → ebook-convert → epub → native parser (issue 9)
- Unified `DocumentConverter` dispatches by file extension
- Graceful errors when external tools are missing

### Issue 11 — Audiobook generation

CLI can produce a complete audiobook from a document.

- `yapper convert book.epub -o book.m4b`
- Per-chapter synthesis with voice assignment
- MP3 output: one file per chapter, or single concatenated file
- M4B output: AAC encoding, chapter markers via ffmpeg metadata, single file
- `--random-voice` (default), `--voice NAME`, `--random-voice=FILTER`
- Progress reporting to stderr
- Metadata embedding: title, author, cover art (m4b)

## Phase 3: Extended CLI

### Issue 12 — Clipboard reader

- `yapper speak --clipboard` reads `NSPasteboard.general` and speaks it

### Issue 13 — Screen selection reader

- `yapper speak --selection` reads selected text via macOS Accessibility APIs
- May require Accessibility permission prompt

## Phase 4: Library polish

### Issue 14 — YapperKit public API stabilisation

- Review and finalise public API surface
- Documentation comments on all public types and methods
- Package README with usage examples
- Versioned release (1.0)

### Issue 15 — Epub reader integration support

- Paragraph-level streaming API (synthesise one paragraph, callback, next)
- Playback position tracking (which paragraph/word is being spoken)
- Low-latency mode: pre-buffer next paragraph while current one plays
- API for external playback controls (pause/resume/skip/seek)

## Dependency graph

```
1 ─→ 2 ─→ 3 ─→ 4 ─→ 5 ─→ 6
                          ─→ 7
                     4 ─→ 8
                          9 ─→ 10 ─→ 11
                                     12
                                     13
                          14
                          15
```

- Issues 6, 7, 8 can proceed in parallel after issue 5
- Issues 9–10 can proceed in parallel with issues 5–8 (chapter detection is independent of synthesis)
- Issue 11 depends on both the synthesis pipeline (4) and document pipeline (10)
- Issues 12, 13, 14, 15 are independent of each other

## Risk: Issue 3 (inference pipeline)

Issue 3 is the highest-risk item. It requires porting the Kokoro model architecture to our own code using MLX Swift, referencing KokoroSwift's implementation. The model layers are:

| Layer | KokoroSwift reference file | Complexity |
|---|---|---|
| BERT encoder | `TTSEngine/KokoroTTS.swift` | Medium — standard transformer encoder |
| Duration predictor | `TTSEngine/DurationPredictor.swift` | Low — small feedforward network |
| Prosody predictor | `TTSEngine/ProsodyPredictor.swift` | Low — similar to duration predictor |
| Decoder | `Decoder/KokoroDecoder.swift` | Medium — StyleTTS2 decoder |
| iSTFT | `Decoder/MLXSTFT.swift` | Medium — signal processing, well-defined |

If this proves harder than expected, we can fall back to depending on KokoroSwift temporarily and fork later. But the architecture is well-documented at 82M parameters and KokoroSwift provides a complete reference — this is implementation work, not research.

## External dependencies to verify early

Before starting issue 1, confirm:

- [ ] MisakiSwift builds on macOS 15 / Apple Silicon with current Xcode
- [ ] MLX Swift version compatible with MisakiSwift's pin (currently 0.30.2)
- [ ] swift-argument-parser is compatible with swift-tools-version 6.2
- [ ] Kokoro-82M safetensors + voices.npz can be downloaded from HuggingFace
- [ ] KokoroSwift source is accessible as reference (clone locally)

These are validation tasks for issue 1, not prerequisites — if any fail, the issue captures the fix.

## Scope summary

| Phase | Issues | What you get |
|---|---|---|
| Phase 1 (Foundation) | 1–5 | YapperKit can synthesise any text to audio and play it live |
| Phase 2 (CLI Core) | 6–11 | Full audiobook generation CLI, feature parity with make-audiobook |
| Phase 3 (Extended) | 12–13 | Clipboard and screen selection reading |
| Phase 4 (Library) | 14–15 | Stable embeddable library for epub reader integration |

---

## Changelog

- 0.1 (2026-04-02): Initial implementation plan
- 0.2 (2026-04-02): Updated for Option C — own inference layer, KokoroSwift as reference only. Issue 3 expanded to cover inference pipeline implementation. Added risk section. Updated dependency checklist.
