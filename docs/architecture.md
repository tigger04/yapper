<!-- Version: 0.2 | Last updated: 2026-04-02 -->

# Yapper — Architecture

## Overview

Yapper is a two-layer Swift system: **YapperKit** (library) and **yapper** (CLI). YapperKit owns TTS inference and audio output. The CLI handles document ingestion, chapter detection, and audiobook assembly.

```
┌──────────────────────────────────────────────────┐
│                  yapper (CLI)                     │
│                                                   │
│  Document Ingestion    Chapter Detection           │
│  (pandoc, pdftotext,   (epub TOC, heading          │
│   calibre)             heuristics)                 │
│                                                   │
│  Audiobook Assembly    Voice Assignment            │
│  (ffmpeg: mp3/m4b,     (random, explicit,          │
│   chapter markers,      per-chapter)               │
│   metadata)                                        │
├──────────────────────────────────────────────────┤
│                 YapperKit                         │
│                                                   │
│  Text Chunker     Inference Engine   Audio Output  │
│  (sentence-level   (own Kokoro impl   (AVAudioEngine│
│   splitting,        on MLX Swift)      for playback,│
│   510-token cap)                       PCM buffer   │
│                                        for files)   │
│                                                   │
│  Timestamps        Voice Registry                  │
│  (word-level,       (enumerate,                    │
│   from inference)    load, filter)                 │
├──────────────────────────────────────────────────┤
│  MisakiSwift (G2P) + MLX Swift (Metal inference)  │
└──────────────────────────────────────────────────┘
```

## Design decision: own inference layer (Option C)

We evaluated three approaches:

- **Option A:** Depend on KokoroSwift as a runtime SPM dependency
- **Option B:** Write everything from scratch, including G2P
- **Option C (chosen):** Own inference layer on MLX Swift, use MisakiSwift for G2P

### Why Option C

**MisakiSwift for G2P:** Grapheme-to-phoneme is the most complex component — lexicon dictionaries, a BART fallback neural network for out-of-vocabulary words, NLP POS tagging via Apple's NaturalLanguage framework. MisakiSwift is well-maintained, cleanly isolated, and Apache 2.0. No reason to reimplement.

**Own inference layer:** KokoroSwift's `generateAudio` is synchronous — it runs the full pipeline (G2P → BERT → duration prediction → prosody → decoder → iSTFT) and returns all PCM samples at once. There is no callback, no async/await, and no way to get partial results. Adding sentence-level chunked playback (our core streaming requirement) would mean forking KokoroSwift and maintaining the fork indefinitely. Writing our own inference code on MLX Swift, using KokoroSwift as a reference, gives us full control from the start.

**What we're not gaining:** There is no meaningful performance difference between using KokoroSwift and our own inference — both hit the same MLX Swift → Metal backend. The motivation is architectural control, not speed.

## Model constraints

These are properties of the Kokoro-82M model itself, not implementation choices. They apply regardless of which inference code runs the model.

### 510-token limit

The model uses a BERT text encoder with a fixed positional embedding table of 512 positions (2 reserved for special tokens → 510 usable). Input beyond 510 phoneme tokens has no positional encoding and produces garbage. All Kokoro implementations (Python, Rust, Swift) enforce this limit.

In practice, 510 phoneme tokens ≈ 2–4 sentences of English. Any text longer than this must be chunked externally.

### Non-autoregressive generation

Kokoro predicts all audio frames in a single forward pass — it is not autoregressive. The pipeline is:

```
text → G2P → phonemes → BERT encoding → duration prediction →
prosody prediction → decoder → full spectrogram → iSTFT → all PCM samples
```

There is no natural streaming point mid-inference. Each inference call produces the complete waveform for its input. This is what makes Kokoro fast (single pass, no sequential token dependency) but means true token-level streaming is not possible.

### Pseudo-streaming strategy

To achieve perceived real-time playback despite non-autoregressive generation:

1. Split input text at sentence boundaries (using `NLTokenizer` with `.sentence` unit)
2. Greedily batch consecutive sentences into chunks that fit within the 510-token budget
3. For live playback: generate each chunk, push PCM to `AVAudioEngine` immediately, start generating the next chunk while the current one plays
4. For file output: generate all chunks sequentially, concatenate PCM buffers

On M3/M4 hardware, inference for a single sentence-length chunk is expected to be well under 1 second. The user hears the first sentence while subsequent sentences are still being synthesised.

## YapperKit

### Responsibilities

- Load Kokoro-82M model weights (`.safetensors`) via MLX Swift
- Load voice embeddings (`.npz`) via MLX utilities
- Run inference: text → MisakiSwift G2P → BERT encoding → duration/prosody prediction → decoder → iSTFT → PCM
- Chunk long text into ≤510-token segments at sentence boundaries
- Manage voice selection (enumerate, load, filter by accent/gender)
- Provide word-level timestamps for each utterance
- Output raw PCM audio (`[Float]`, 24kHz, mono)
- Stream audio to system output via AVAudioEngine (for live playback)

### Inference pipeline (internal)

```
Input text
    │
    ▼
MisakiSwift G2P ──→ phoneme string + word tokens
    │
    ▼
BERT text encoder ──→ hidden states (from model weights)
    │
    ▼
Duration predictor ──→ per-phoneme durations
    │
    ▼
Prosody predictor ──→ pitch/energy contours
    │
    ▼
Decoder ──→ mel spectrogram
    │
    ▼
iSTFT ──→ raw PCM waveform ([Float], 24kHz)
    │
    ▼
Word timestamps (derived from predicted durations)
```

Each stage is implemented using MLX Swift array operations and MLXNN layers, with weights loaded from the Kokoro-82M safetensors file. KokoroSwift's source code serves as the authoritative reference for how to wire these layers together.

### Key types (draft)

```swift
// Core engine
public class YapperEngine {
    public init(modelPath: URL, voicesPath: URL) throws
    public func synthesize(text: String, voice: Voice, speed: Float) throws -> AudioResult
    public func stream(text: String, voice: Voice, speed: Float, onChunk: (AudioChunk) -> Void) throws
}

// Audio output
public struct AudioResult {
    public let samples: [Float]       // PCM, 24kHz mono
    public let sampleRate: Int        // 24000
    public let timestamps: [WordTimestamp]
}

public struct AudioChunk {
    public let samples: [Float]
    public let timestamps: [WordTimestamp]
    public let isLast: Bool
}

public struct WordTimestamp {
    public let word: String
    public let startTime: Double      // seconds
    public let endTime: Double        // seconds
}

// Voice management
public struct Voice {
    public let name: String           // e.g. "af_heart"
    public let accent: Accent         // .american, .british
    public let gender: Gender         // .female, .male
}

public class VoiceRegistry {
    public func list(filter: VoiceFilter?) -> [Voice]
    public func random(filter: VoiceFilter?) -> Voice
    public func load(name: String) throws -> MLXArray  // voice embedding
}

// Live playback
public class AudioPlayer {
    public func play(engine: YapperEngine, text: String, voice: Voice, speed: Float) throws
    public func pause()
    public func resume()
    public func stop()
}
```

### Model and voice file locations

```
~/.local/share/yapper/
├── models/
│   └── kokoro-v1.0.safetensors     # MLX-format model weights
└── voices/
    └── voices-v1.0.npz             # all voice embeddings
```

On first run, the CLI checks for these files and provides instructions if missing. Weights are not auto-downloaded — the user copies them from HuggingFace (or we provide a `yapper setup` command).

## CLI (yapper)

### Responsibilities

- Parse CLI arguments (via swift-argument-parser)
- Convert input documents to plain text (calling external tools)
- Detect chapter structure
- Assign voices to chapters
- Call YapperKit for synthesis
- Encode output audio (mp3/m4b via ffmpeg)
- Embed metadata (title, author, chapter markers, cover art)

### Document conversion pipeline

```
Input file
    │
    ├── .epub ──→ native epub parser (extract chapters + metadata)
    ├── .mobi ──→ ebook-convert (Calibre) → .epub → native parser
    ├── .pdf  ──→ pdftotext (poppler) → plain text (OCR fallback: TODO)
    ├── .docx ──→ pandoc → plain text
    ├── .odt  ──→ pandoc → plain text
    ├── .html ──→ pandoc → plain text
    ├── .md   ──→ pandoc → plain text
    └── .txt  ──→ direct read
         │
         ▼
    Chapter list: [(title: String, text: String)]
         │
         ▼
    Voice assignment (random/explicit per chapter)
         │
         ▼
    YapperKit synthesis (per chapter)
         │
         ▼
    Audio encoding (ffmpeg)
         │
         ├── .mp3 → ffmpeg encodes each chapter, applies ID3 tags
         └── .m4b → ffmpeg encodes AAC, concatenates, applies chapter metadata
```

### Chapter detection

| Format | Strategy |
|---|---|
| `.epub` | Parse OPF spine + TOC (NCX or nav). Each spine item with a TOC entry = chapter. |
| `.pdf` | Heading heuristics: lines in ALL CAPS, or lines matching `Chapter \d+`, or short lines followed by blank lines. Fallback: treat entire document as one chapter. |
| `.docx`/`.odt` | Pandoc outputs markdown with `#` headings. Split on `# ` lines. |
| `.md`/`.html` | Split on `# ` (h1) headings. |
| `.txt` | Heading heuristics similar to PDF. Fallback: single chapter. |

### Voice assignment

- **Default:** random voice per chapter from the full voice set
- **`--voice NAME`:** same voice for all chapters
- **`--random-voice`:** random from full set (explicit, same as default)
- **`--random-voice=FILTER`:** random from filtered set (e.g. `bf` for British female)
- Seed is derived from the input filename for reproducibility — same file always gets the same voice assignment unless `--voice` overrides

### Live playback path (`yapper speak`)

```
Text input (arg, stdin, --clipboard, --selection)
    │
    ▼
YapperKit.stream() with AVAudioEngine callback
    │
    ▼
System audio output (no intermediate files)
```

### External tool dependencies

| Tool | Used for | Required? |
|---|---|---|
| `ffmpeg` | Audio encoding (PCM→MP3, AAC, M4B assembly) | Yes (for file output) |
| `pandoc` | docx/odt/md/html → plain text | Yes (for those formats) |
| `pdftotext` | PDF → plain text | Yes (for PDF) |
| `ebook-convert` | mobi → epub | Only for .mobi input |

For live playback (`yapper speak`), no external tools are needed — audio goes directly to AVAudioEngine.

## Swift Package structure

```
yapper/
├── Package.swift
├── Sources/
│   ├── YapperKit/
│   │   ├── Engine/
│   │   │   ├── YapperEngine.swift
│   │   │   └── TextChunker.swift
│   │   ├── Inference/
│   │   │   ├── BERTEncoder.swift
│   │   │   ├── DurationPredictor.swift
│   │   │   ├── ProsodyPredictor.swift
│   │   │   ├── Decoder.swift
│   │   │   └── STFT.swift
│   │   ├── Voice/
│   │   │   ├── Voice.swift
│   │   │   └── VoiceRegistry.swift
│   │   ├── Audio/
│   │   │   ├── AudioResult.swift
│   │   │   └── AudioPlayer.swift
│   │   └── Timestamps/
│   │       └── WordTimestamp.swift
│   └── yapper/
│       ├── main.swift
│       ├── Commands/
│       │   ├── ConvertCommand.swift
│       │   ├── SpeakCommand.swift
│       │   └── VoicesCommand.swift
│       ├── Document/
│       │   ├── DocumentConverter.swift
│       │   ├── ChapterDetector.swift
│       │   └── EpubParser.swift
│       └── Output/
│           ├── MP3Encoder.swift
│           └── M4BAssembler.swift
├── Tests/
│   ├── regression/
│   │   └── YapperKitTests/
│   └── one_off/
│       └── .gitkeep
├── Makefile
└── docs/
    ├── VISION.md
    ├── architecture.md
    └── implementation_plan.md
```

## Platform constraints

- **macOS 15+ (Sequoia)** — required by MisakiSwift (uses NaturalLanguage APIs from macOS 15)
- **Apple Silicon only** — MLX does not run on Intel
- **Swift 5.9+** — swift-tools-version 6.2 used by MisakiSwift

## Performance considerations

- Kokoro-82M at 4-bit quantisation: ~50MB model, minimal memory footprint
- KokoroSwift reports ~3.3x realtime on iPhone 13 Pro; M3/M4 should be significantly faster
- Chunking at sentence boundaries keeps per-inference latency low (<1s per sentence)
- For audiobook generation, chapters can be synthesised in parallel (one Metal context per chapter) if memory allows — but sequential is simpler for MVP

---

## Changelog

- 0.1 (2026-04-02): Initial architecture document
- 0.2 (2026-04-02): Option C decision — own inference layer + MisakiSwift for G2P. Added model constraints section. Removed KokoroSwift as runtime dependency. Added Inference/ directory to package structure.
