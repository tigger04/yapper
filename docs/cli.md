<!-- Version: 1.0 | Last updated: 2026-04-26 -->

# CLI Guide

Yapper provides three commands and a shorthand:

| Command | Purpose |
|---------|---------|
| `yapper speak` | Speak text aloud through system speakers |
| `yapper convert` | Convert files to audio (M4A, MP3, M4B) |
| `yapper voices` | List and preview available voices |
| `yap` | Shorthand for `yapper speak` |

## Speaking text

```bash
# Speak text aloud
yap "Hello, this is yapper."

# Pin a specific voice
yap --voice bf_emma "Hello, this is yapper."

# Persistent voice via environment variable
export YAPPER_VOICE=bm_daniel
yap "Now I sound like Daniel every time."

# Custom pronunciation with inline IPA
yap "Hello [Taḋg](/taɪɡ/), how are you today?"

# Read from stdin
echo "Text from a pipe" | yap

# Adjust speed (0.5 = slower, 2.0 = faster)
yap --speed 0.8 "Speaking more slowly now."

# Preview without synthesis
yap --dry-run "What voice would this use?"
```

### Voice resolution

The voice is resolved from three sources, in order of priority:

1. `--voice <name>` - CLI flag, wins unconditionally
2. `$YAPPER_VOICE` - environment variable for persistent preference
3. Random - a different voice on every invocation

Invalid voice names produce a clear error rather than silently falling back.

## Converting files

```bash
# Single file to M4A
yapper convert notes.txt -o notes.m4a

# Single file to MP3
yapper convert notes.txt --format mp3

# Epub to M4B audiobook with chapter markers
yapper convert book.epub -o book.m4b

# Multiple files into one audiobook
yapper convert *.md -o collection.m4b

# Specific voice for conversion
yapper convert notes.txt --voice af_heart -o notes.m4a

# Set metadata
yapper convert notes.txt --title "My Notes" --author "Me" -o notes.m4a

# Non-interactive mode (no prompts, for scripts/CI)
yapper convert book.epub --non-interactive -o book.m4b

# Preview conversion plan without synthesising
yapper convert book.epub --dry-run
```

### Supported input formats

| Format | Extension | Requires |
|--------|-----------|----------|
| Plain text | `.txt` | - |
| Markdown | `.md`, `.markdown` | - |
| Epub | `.epub` | - |
| PDF | `.pdf` | `pdftotext` (poppler) |
| Word | `.docx` | `pandoc` |
| OpenDocument | `.odt` | `pandoc` |
| HTML | `.html` | `pandoc` |
| Mobi | `.mobi` | `ebook-convert` (Calibre) |

### Output formats

| Format | Extension | Notes |
|--------|-----------|-------|
| M4A | `.m4a` | Default for single files |
| M4B | `.m4b` | Default for multi-chapter input; audiobook with chapter markers |
| MP3 | `.mp3` | Via `--format mp3` |

The output format is inferred from: `--format` flag > `-o` file extension > automatic (M4B for multi-chapter, M4A otherwise).

## Script conversion

Convert plays and screenplays with distinct voices per character:

```bash
# Force script mode with defaults (no config file needed)
yapper convert play.org --script

# Auto-detect from script.yaml alongside the script file
yapper convert play.org

# Specify config explicitly
yapper convert play.fountain --script-config config.yaml

# Preview cast and structure
yapper convert play.org --script --dry-run

# Control concurrency
yapper convert play.org --threads 1
```

Supported script formats: org-mode (`.org`), markdown (`.md`), Fountain (`.fountain`). See [script-reading.md](script-reading.md) for format details.

## Voice management

```bash
# List all available voices
yapper voices

# List voice names only (scriptable)
yapper voices -1

# Preview a specific voice
yapper voices --preview bf_emma

# Preview all British female voices
yapper voices --preview bf

# Preview all voices with the full Stella passage
yapper voices --preview all --full

# Preview with custom text
yapper voices --preview am_adam "Custom text to speak."

# Preview with text from stdin
echo "Text from pipe" | yapper voices --preview bf -
```

### Filter shorthands

Voice filters use a two-character code: accent + gender.

| Code | Meaning |
|------|---------|
| `a` | American accent |
| `b` | British accent |
| `f` | Female |
| `m` | Male |

Examples: `bf` = British female, `am` = American male, `a` = any American, `f` = any female.

## Common flags

| Flag | Commands | Purpose |
|------|----------|---------|
| `--voice <name>` | speak, convert | Specific voice name |
| `--speed <n>` | speak, convert | Speed multiplier (default: 1.0) |
| `--dry-run` | speak, convert | Preview without synthesis |
| `-q`, `--quiet` | speak, convert | Suppress progress output |
| `--non-interactive` | convert | Skip interactive prompts |
| `-o <path>` | convert | Output file path |
| `--format <fmt>` | convert | Output format (m4a, mp3, m4b) |
| `--script` | convert | Force script mode using defaults |
| `--threads <n>` | convert | Worker processes for script mode |
| `--script-config <path>` | convert | Path to script YAML config |
| `--title <text>` | convert | Title metadata |
| `--author <text>` | convert | Author metadata |
| `-1` | voices | One name per line |
| `--preview <spec>` | voices | Preview voice(s) |
| `--full` | voices | Full Stella passage for preview |
