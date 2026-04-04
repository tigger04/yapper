<!-- Version: 0.4 | Last updated: 2026-04-04 -->

# Yapper - Implementation Plan

## Phasing

Work is divided into issues. Each issue is self-contained with its own ACs and tests. Issues are ordered by dependency - later issues build on earlier ones.

## Phase 1: Foundation ✅ (v0.1.0-v0.3.0)

All Phase 1 work is complete.

### [Issue #1](https://github.com/tigger04/yapper/issues/1) - Project scaffolding + model/voice loading ✅

- Swift Package with `YapperKit` (library) and `yapper` (executable) targets
- Dependencies: MisakiSwift 1.0.6, MLX Swift 0.30.2, swift-argument-parser 1.7.1
- `xcodebuild` required for Metal shader compilation (not `swift build`)
- VoiceRegistry loads individual `.safetensors` voice files (v1.0 format, not `.npz`)
- Makefile with build, test, install, uninstall targets
- 13 regression tests

### [Issue #2](https://github.com/tigger04/yapper/issues/2) - Inference engine + text chunking + live playback ✅

- Full Kokoro-82M inference pipeline: BERT -> duration -> prosody -> text encoder -> decoder -> iSTFT
- 17 inference source files + 7 building block files
- TextChunker: sentence-boundary splitting with 510-token budget
- AudioPlayer: AVAudioEngine streaming with pause/resume/stop
- Word-level timestamps from predicted phoneme durations
- Speed control (0.5x-2.0x)
- 19 regression tests

### [Issue #3](https://github.com/tigger04/yapper/issues/3) - Audio wobble fix ✅

- Root cause: two bugs in AdainResBlk1d (shortcut upsample method + missing padding)
- Intermediate tensors now numerically identical to KokoroSwift at every stage
- Mel-spectrogram comparison infrastructure for regression guarding
- A/B comparison tests against kokoro-tts
- 7 regression tests

## Phase 2: CLI - Core Commands ✅ (v0.4.0-v0.7.0)

All Phase 2 work is complete.

### [Issue #4](https://github.com/tigger04/yapper/issues/4) - `yapper speak` command ✅

- `yapper speak "text"` - speak the argument
- `echo "text" | yapper speak` - speak from stdin
- `yapper speak < file.txt` - speak from file redirect
- `--voice NAME` and `--speed FLOAT` flags
- Playback via afplay (temp WAV)
- 14 regression tests

### [Issue #5](https://github.com/tigger04/yapper/issues/5) - `yapper voices` command ✅

- `yapper voices` - list all voices with name, accent, gender
- `yapper voices --preview NAME` - speak a sample sentence with the named voice
- 8 regression tests

### [Issue #6](https://github.com/tigger04/yapper/issues/6) - Plain text to audio file ✅

- `yapper convert input.txt -o output.m4a`
- Default format: M4A (AAC). MP3 available via `--format mp3`
- ID3 tags: `--author`, `--title` flags
- Existing output files backed up (.bak, .1.bak, .2.bak)
- Multiple input files, `--dry-run`, non-UTF-8/empty rejection
- 25 regression tests

### [Issue #7](https://github.com/tigger04/yapper/issues/7) - Epub parsing and chapter detection ✅

- Native epub parser: OPF manifest, spine, TOC (NCX + nav)
- Epub 2 and epub 3 support
- HTML stripping, entity decoding, metadata extraction
- Edge cases: no-TOC, missing metadata, invalid ZIP, zero-byte
- 21 regression tests

### [Issue #8](https://github.com/tigger04/yapper/issues/8) - Document conversion pipeline ✅

- PDF (pdftotext), docx/odt (pandoc), md/html (h1 splitting), txt (ALL CAPS heuristics), mobi (ebook-convert)
- Case-insensitive extension dispatch, YAML frontmatter stripping
- Missing tool errors with install hints
- 18 regression tests

### [Issue #9](https://github.com/tigger04/yapper/issues/9) - Audiobook generation ✅

- M4B with chapter markers, voice-per-chapter, metadata, progress on stderr
- Default M4B for multi-chapter, M4A for single-chapter
- Track numbers from chapter order or filename digits
- Interactive metadata prompts (TTY-aware)
- Validated: chapter markers display in Apple Books
- 14 regression tests

**Total: ~110 regression tests passing, tagged v0.7.0**

## Other resolved issues

### [Issue #10](https://github.com/tigger04/yapper/issues/10) - Standalone CLI binary ✅

- Resolved by switching MisakiSwift to static linking (forked with `type: .dynamic` removed)
- Upstream PR: [mlalma/MisakiSwift#13](https://github.com/mlalma/MisakiSwift/pull/13)

### [Issue #11](https://github.com/tigger04/yapper/issues/11) - Homebrew formula and notarised cask

- Pending

### [Issue #12](https://github.com/tigger04/yapper/issues/12) - Multi-language voice support

- 54 voices across 8 languages downloaded, 28 English currently recognized
- Pending G2P investigation for non-English languages

## Phase 3: Extended CLI

### Issue - Clipboard reader

- `yapper speak --clipboard` reads `NSPasteboard.general` and speaks it

### Issue - Screen selection reader

- `yapper speak --selection` reads selected text via macOS Accessibility APIs
- May require Accessibility permission prompt

## Phase 4: Library polish

### Issue - YapperKit public API stabilization

- Review and finalize public API surface
- Documentation comments on all public types and methods
- Package README with usage examples
- Versioned release (1.0)

### Issue - Multi-language voice support

- Update `Voice` parser to recognize all language prefixes (e/f/h/i/j/p/z)
- Add `Accent` cases or a `Language` enum for non-English voices
- Update MisakiSwift usage to support language-specific G2P
- `yapper voices` shows language column

### Issue - Resumable audiobook generation

- Save synthesis state after each chapter
- `yapper convert --resume` picks up where a failed/interrupted generation left off

### Issue - Epub reader integration support

- Paragraph-level streaming API
- Playback position tracking
- Low-latency mode: pre-buffer next paragraph while current one plays

## Scope summary

| Phase | Issues | Status | What you get |
|---|---|---|---|
| Phase 1 (Foundation) | [#1](https://github.com/tigger04/yapper/issues/1)-[#3](https://github.com/tigger04/yapper/issues/3) | ✅ v0.3.0 | YapperKit synthesizes text to audio, numerically identical to KokoroSwift |
| Phase 2 (CLI Core) | [#4](https://github.com/tigger04/yapper/issues/4)-[#9](https://github.com/tigger04/yapper/issues/9) | ✅ v0.7.0 | Full audiobook generation CLI, feature parity with make-audiobook |
| Phase 3 (Extended) | TBD | Future | Clipboard and screen selection reading |
| Phase 4 (Library) | TBD | Future | Stable embeddable library, multi-language, resumable generation |

---

## Changelog

- 0.1 (2026-04-02): Initial implementation plan
- 0.2 (2026-04-02): Updated for Option C - own inference layer
- 0.3 (2026-04-03): Phase 1 complete
- 0.4 (2026-04-04): Phase 2 complete. All issue links added. Phase 3/4 issue numbers TBD.
