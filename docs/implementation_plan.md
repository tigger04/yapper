<!-- Version: 0.3 | Last updated: 2026-04-03 -->

# Yapper — Implementation Plan

## Phasing

Work is divided into issues. Each issue is self-contained with its own ACs and tests. Issues are ordered by dependency — later issues build on earlier ones.

## Phase 1: Foundation ✅ (v0.1.0–v0.3.0)

All Phase 1 work is complete. Issues #1–#3 closed.

### Issue #1 — Project scaffolding + model/voice loading ✅

- Swift Package with `YapperKit` (library) and `yapper` (executable) targets
- Dependencies: MisakiSwift 1.0.6, MLX Swift 0.30.2, swift-argument-parser 1.7.1
- `xcodebuild` required for Metal shader compilation (not `swift build`)
- VoiceRegistry loads individual `.safetensors` voice files (v1.0 format, not `.npz`)
- Makefile with build, test, install, uninstall targets
- 13 regression tests

### Issue #2 — Inference engine + text chunking + live playback ✅

- Full Kokoro-82M inference pipeline: BERT → duration → prosody → text encoder → decoder → iSTFT
- 17 inference source files + 7 building block files
- TextChunker: sentence-boundary splitting with 510-token budget
- AudioPlayer: AVAudioEngine streaming with pause/resume/stop
- Word-level timestamps from predicted phoneme durations
- Speed control (0.5x–2.0x)
- 19 regression tests

### Issue #3 — Audio wobble fix ✅

- Root cause: two bugs in AdainResBlk1d (shortcut upsample method + missing padding)
- Intermediate tensors now numerically identical to KokoroSwift at every stage
- Mel-spectrogram comparison infrastructure for regression guarding
- A/B comparison tests against kokoro-tts
- 7 regression tests

**Total: 39 regression tests passing, 3 issues closed, tagged v0.1.0–v0.3.0**

## Phase 2: CLI — Core Commands

### Issue 4 — `yapper speak` command

CLI command for live TTS playback.

- `yapper speak "text"` — speak the argument
- `echo "text" | yapper speak` — speak from stdin
- `yapper speak < file.txt` — speak from file redirect
- `--voice NAME` and `--speed FLOAT` flags
- Uses AudioPlayer from YapperKit

### Issue 5 — `yapper voices` command

CLI command to list and preview available voices.

- `yapper voices` — list all voices with name, accent, gender
- `yapper voices --preview NAME` — speak a sample sentence with the named voice

### Issue 6 — Plain text to audio file

CLI can convert text files to M4A (default) or MP3.

- `yapper convert input.txt -o output.m4a`
- Default format: M4A (AAC). MP3 available via `--format mp3`
- Calls YapperKit for synthesis, ffmpeg for encoding
- ID3 tags: `--author`, `--title` flags
- Default output filename: same base name, `.m4a` extension
- Existing output files backed up (.bak, .1.bak, .2.bak)
- Multiple input files processed sequentially
- `--dry-run` shows planned actions without synthesising
- Non-UTF-8 and empty input rejected with descriptive errors

### Issue 7 — Epub parsing and chapter detection

CLI can extract chapters and metadata from epub files.

- Native epub parser: read OPF manifest, spine, and TOC (NCX/nav)
- Extract chapter titles and text content
- Extract metadata: title, author, cover image
- Strip HTML tags from chapter content
- Returns `[(title: String, text: String)]`

### Issue 8 — Document conversion pipeline

CLI can convert non-epub formats to chapter lists.

- PDF → pdftotext → heading-based chapter splitting
- docx/odt → pandoc → heading-based splitting
- md/html → pandoc or direct parse → heading-based splitting
- mobi → ebook-convert → epub → native parser (issue 7)
- Unified `DocumentConverter` dispatches by file extension
- Graceful errors when external tools are missing

### Issue 9 — Audiobook generation

CLI can produce a complete audiobook from a document.

- `yapper convert book.epub -o book.m4b`
- Default format: M4B for multi-chapter, M4A for single-chapter
- Per-chapter synthesis with voice assignment
- M4B output: AAC encoding, chapter markers via ffmpeg metadata, single file
- `--random-voice` (default), `--voice NAME`, `--random-voice=FILTER`
- Track numbers from chapter order or filename digits
- Multiple input files accepted (combined into one audiobook or individual files)
- Progress reporting to stderr
- Metadata embedding: title, author, cover art (m4b)
- `--dry-run` shows chapter list, voice assignments, output format

## Phase 3: Extended CLI

### Issue 10 — Clipboard reader

- `yapper speak --clipboard` reads `NSPasteboard.general` and speaks it

### Issue 11 — Screen selection reader

- `yapper speak --selection` reads selected text via macOS Accessibility APIs
- May require Accessibility permission prompt

## Phase 4: Library polish

### Issue 12 — YapperKit public API stabilisation

- Review and finalise public API surface
- Documentation comments on all public types and methods
- Package README with usage examples
- Versioned release (1.0)

### Issue 13 — Multi-language voice support

- Update `Voice` parser to recognise all language prefixes (e/f/h/i/j/p/z)
- Add `Accent` cases or a `Language` enum for non-English voices
- Update `VoiceRegistry` to list all 54 voices
- Update MisakiSwift usage to support language-specific G2P (MisakiSwift currently English-only)
- Investigate whether Kokoro-82M handles multilingual G2P or if separate G2P modules are needed per language
- `yapper voices` shows language column
- `--voice` and `--random-voice` filter by language
- `yapper speak` auto-detects language from voice prefix or accepts `--lang` flag

### Issue 14 — Resumable audiobook generation

- Save synthesis state after each chapter (which chapters are done, output files so far)
- `yapper convert --resume` picks up where a failed/interrupted generation left off
- State file stored alongside the output (e.g. `.yapper-state.json`)
- Completed chapters are not re-synthesised

### Issue 14 — Epub reader integration support

- Paragraph-level streaming API (synthesise one paragraph, callback, next)
- Playback position tracking (which paragraph/word is being spoken)
- Low-latency mode: pre-buffer next paragraph while current one plays
- API for external playback controls (pause/resume/skip/seek)

## Dependency graph

```
Phase 1 (done): #1 ─→ #2 ─→ #3

Phase 2: #4 (speak)
          #5 (voices)
          #6 (text→mp3)
          #7 (epub) ─→ #8 (doc pipeline) ─→ #9 (audiobook)

Phase 3: #10 (clipboard)
          #11 (selection)

Phase 4: #12 (API polish)
          #13 (epub reader)
```

- Issues 4, 5, 6 can proceed in parallel (independent CLI commands)
- Issue 7 (epub) can proceed in parallel with 4–6
- Issue 8 depends on 7 (epub parser)
- Issue 9 depends on 6 (mp3 encoding) and 8 (document pipeline)
- Issues 10–13 are independent of each other

## Scope summary

| Phase | Issues | Status | What you get |
|---|---|---|---|
| Phase 1 (Foundation) | #1–#3 | ✅ Done (v0.3.0) | YapperKit synthesises text to audio, numerically identical to KokoroSwift |
| Phase 2 (CLI Core) | #4–#9 | Next | Full audiobook generation CLI, feature parity with make-audiobook |
| Phase 3 (Extended) | #10–#11 | Future | Clipboard and screen selection reading |
| Phase 4 (Library) | #12–#13 | Future | Stable embeddable library for epub reader integration |

---

## Changelog

- 0.1 (2026-04-02): Initial implementation plan
- 0.2 (2026-04-02): Updated for Option C — own inference layer
- 0.3 (2026-04-03): Phase 1 complete. Updated issue numbers, marked done, added Phase 1 summary. Removed risk section (inference pipeline delivered successfully). Removed dependency checklist (all verified).
