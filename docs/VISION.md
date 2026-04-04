<!-- Version: 0.2 | Last updated: 2026-04-02 -->

# Yapper — Vision

## What

A fast, Apple Silicon-native TTS toolkit. CLI-first, embeddable as a Swift library, built on Kokoro-82M via MLX.

## Why

[tigger04/make-audiobook](https://github.com/tigger04/make-audiobook) works but relies on Python-based TTS engines (Piper, kokoro-tts) that are slow and don't exploit M-series hardware. Yapper replaces that stack with native Metal-accelerated inference, targeting real-time-or-faster synthesis.

## Foundation

| Component | Source | Licence | Usage |
|---|---|---|---|
| Model weights | [hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) | Apache 2.0 | Copied into project |
| MLX quantised variants | [mlx-community/Kokoro-82M-*](https://huggingface.co/mlx-community) | Apache 2.0 | Copied into project |
| Voice embeddings | Bundled with Kokoro-82M | Apache 2.0 | Copied into project |
| Grapheme-to-phoneme | [mlalma/MisakiSwift](https://github.com/mlalma/MisakiSwift) | Apache 2.0 | SPM dependency |
| MLX framework | [ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift) | MIT | SPM dependency |
| Reference impl | [mlalma/kokoro-ios](https://github.com/mlalma/kokoro-ios) (KokoroSwift) | MIT | Reference only, not a dependency |

### Approach: own inference layer (Option C)

YapperKit implements its own Kokoro inference pipeline on top of MLX Swift, using MisakiSwift for grapheme-to-phoneme conversion. KokoroSwift serves as a reference implementation for understanding the model architecture but is not a runtime dependency.

**Why not depend on KokoroSwift directly?**
- Its `generateAudio` is synchronous with no streaming support — we need sentence-level chunked output for live playback
- Owning the inference layer lets us control chunking, audio pipeline, and future optimisations without maintaining a fork
- The model architecture (StyleTTS2-based, 82M params, non-autoregressive) is well-understood and bounded to implement with KokoroSwift as a reference

**Why use MisakiSwift?**
- Grapheme-to-phoneme conversion is the most complex component (lexicon dictionaries, BART fallback network, NLP tagging)
- MisakiSwift is well-maintained, cleanly isolated, and Apache 2.0 licensed
- No benefit to reimplementing it

No runtime dependency on upstream model repos — weights are standalone files.

## Architecture

Yapper is structured as two layers:

1. **YapperKit** — Swift library/package. Handles model loading, inference, streaming audio output, voice management. Embeddable in other Swift projects.
2. **yapper** — CLI tool built on YapperKit. Handles document conversion, chapter detection, file I/O, and audiobook assembly.

```
┌─────────────────────────────────────┐
│           CLI (yapper)              │
│  epub/pdf/docx/odt → chapters →    │
│  TTS → mp3/m4b output              │
├─────────────────────────────────────┤
│          YapperKit                  │
│  Model loading · Inference ·        │
│  Streaming audio · Voice mgmt      │
├─────────────────────────────────────┤
│     MLX Swift + Kokoro-82M          │
│     Metal-accelerated inference     │
└─────────────────────────────────────┘
```

## Use Cases

### Phase 1 — MVP (CLI)

#### UC1: Document to audiobook

Convert a document to an audiobook file.

- **Input formats:** `.epub`, `.mobi`, `.pdf`, `.docx`, `.odt`, `.txt`, `.md`, `.html`
- **Output formats:** `.mp3`, `.m4b` (with chapter markers)
- **Conversion pipeline:** epub/mobi via native parsing or Calibre; pdf via `pdftotext` (or ocr as fallback TODO identify fallback OCR tool); docx/odt via `pandoc`; txt/md/html direct or via pandoc
- **Chapter detection:** Extract chapter structure from epub TOC; infer from headings for other formats
- **Voice per chapter:** Randomise voice assignment per chapter by default; allow explicit voice selection via flag
- **Metadata:** Embed title, author, chapter markers (m4b), cover art where available
- **ID3 tags:** Artist, album, track number

#### UC2: Text file to MP3

Quick single-file conversion: `yapper convert notes.txt -o notes.mp3`

#### UC3: Live TTS playback

Synthesise and play text directly without writing an intermediate file: `yapper speak "Hello world"` or `echo "some text" | yapper speak`

This streams audio to the system output device in real time via YapperKit's streaming inference — no temp files.

#### UC4: Stdin streaming

Pipe arbitrary text for either playback or file output:

```bash
cat document.txt | yapper speak
cat document.txt | yapper convert -o output.mp3
```

### Phase 2 — Extended CLI

#### UC5: Clipboard reader

Read aloud the current clipboard contents: `yapper speak --clipboard`

#### UC6: Screen selection reader

Read aloud a selection of text from the screen (via macOS Accessibility APIs or similar): `yapper speak --selection`

### Phase 3 — Embeddable library

#### UC7: Epub reader integration

YapperKit is embeddable as a Swift Package dependency. A separate epub reader project can import YapperKit to provide read-aloud functionality — synthesising speech on the fly as the user reads, chapter by chapter or paragraph by paragraph, without pre-generating an entire audiobook.

Key requirements for this use case:
- Low-latency first-audio (sub-second target)
- Streaming paragraph-level synthesis
- Pause/resume/skip controls at the API level
- Voice selection API
- Playback position tracking (for highlighting text as it's read)

### Future considerations

- iOS support — YapperKit is portable to iOS 18+ (all dependencies support it). The CLI is macOS-only but the library layer has no macOS-specific APIs.
- GUI wrapper (macOS native, and potentially iOS/iPadOS)
- Voice cloning / custom voice training
- Pronunciation customisation (lexicon overrides)
- Multiple language support (Kokoro supports EN, JA, ZH, DE, FR, and others)
- Batch/queue processing
- Opus output format
- Voice preview / audition
- Playback speed control (without pitch shift)
- SSML support

## CLI Interface (draft)

```
yapper convert <input> [-o output] [--format m4a|m4b|mp3] [--voice NAME] [--random-voice[=FILTER]] [--speed FLOAT] [--author NAME] [--title NAME] [--dry-run]
yapper speak [TEXT] [--voice NAME] [--speed FLOAT] [--clipboard] [--selection]
yapper voices [--list] [--preview NAME]
yapper version
```

Default output format: M4A for single-file conversion, M4B for multi-chapter audiobooks. MP3 available via `--format mp3`.

## Voices

Kokoro-82M ships with ~26 built-in voices:

- American female: `af_alloy`, `af_aoede`, `af_bella`, `af_heart`, `af_jessica`, `af_kore`, `af_nicole`, `af_nova`, `af_river`, `af_sarah`, `af_sky`
- American male: `am_adam`, `am_echo`, `am_eric`, `am_liam`, `am_michael`, `am_onyx`, `am_puck`, `am_santa`
- British female: `bf_alice`, `bf_emma`, `bf_isabella`, `bf_lily`
- British male: `bm_daniel`, `bm_fable`, `bm_george`, `bm_lewis`

Default voice: `af_heart`. Random voice assignment picks from the full set (or a filtered subset) per chapter.

## Dependencies

### Build-time
- Swift 5.9+ / Xcode 15+
- MLX Swift framework
- MisakiSwift (G2P)

### Runtime (CLI)
- macOS 14+ (Sonoma) with Apple Silicon
- `pandoc` — document format conversion (docx, odt, md, html)
- `pdftotext` (poppler) — PDF text extraction
- `calibre` (`ebook-convert`) — mobi conversion (optional, only for .mobi input)
- `ffmpeg` — audio encoding and m4b assembly

### No runtime dependency on
- Python
- espeak-ng
- piper-tts / kokoro-tts (Python)

## Licence

Apache 2.0 — Copyright Taḋg Paul

---

## Changelog

- 0.1 (2026-04-02): Initial vision document
- 0.2 (2026-04-02): Option C decision (own inference + MisakiSwift), updated foundation table
