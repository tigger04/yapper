<!-- Version: 2.0 | Last updated: 2026-04-26 -->

# Script Reading

Yapper can convert play and screenplay scripts into multi-voice audiobooks (M4B), with distinct voices per character and narrator-read stage directions.

## Supported formats

### Org-mode (`.org`)

```org
#+TITLE: My Play
#+AUTHOR: Author Name

* Characters
|-------+---------------------|
| ALICE | A curious girl      |
| BOB   | Her quiet neighbour |
|-------+---------------------|

* Outline
Two neighbours discuss the weather.

* ACT I
** Scene 1: The Garden
*** A sunny garden. Morning.
**** ALICE
Good morning.
**** BOB softly
Is it.
*** ALICE sits down.
```

- `#+TITLE:` / `#+AUTHOR:` - metadata (used for M4B tags and audio announcement)
- `*` (L1 heading) - act or top-level section
- `**` (L2 heading) - scene boundary (becomes an M4B chapter)
- `***` (L3 heading) - stage direction
- `****` (L4 heading) - dialogue attribution (character name, optionally with acting directions)
- Body text below L4 - the dialogue itself
- `[fn:name]` - footnote reference (stripped from audio, definition read as narrator aside)
- `[fn:name] Definition text` - footnote definition (at end of file)
- Character table (`| NAME | description |`) - parsed for preamble narration

### Markdown (`.md`)

```markdown
# My Play

*by Author Name*

### Scene 1: The Garden

*A sunny garden. Morning.*

**ALICE:**
Good morning.

**BOB (softly):**
Is it.

*ALICE sits down.*
```

- `# Title` - play title
- `*by Author Name*` - author
- `### Scene Title` - scene boundary
- `*italic text*` on its own line - stage direction
- `**CHARACTER:**` or `**CHARACTER (notes):**` - dialogue attribution
- `## ACT` headings - skipped (act markers)

## Configuration

Script mode activates when a `script.yaml` file is found alongside the input file, or when `--script-config path/to/config.yaml` is specified.

### Full configuration reference

```yaml
# Metadata (overrides script file metadata)
title: "My Play"
author: "Author Name"

# Voice assignment
auto-assign-voices: true          # auto-assign voices to characters (default: true)
character-voices:                  # explicit voice assignments
  ALICE: bf_emma                   # full voice name
  BOB: bm                         # filter shorthand (British male)
narrator-voice: bf_lily            # voice for stage directions
intro-voice: bf_alice              # voice for preamble (defaults to narrator-voice)

# Content rendering
render-stage-directions: true        # synthesise stage directions (default: true)
render-intro: true                 # synthesise preamble chapter (default: true)
render-footnotes: true             # render footnote definitions as narrator asides (default: true)

# Pacing
dialogue-speed: 1.0                # speech rate for dialogue (default: 1.0)
stage-direction-speed: 0.9         # speech rate for stage directions (default: 1.0)
gap-after-dialogue: 0.3            # silence after dialogue lines in seconds (default: 0.3)
gap-after-stage-direction: 0.5     # silence after stage directions in seconds (default: 0.5)
gap-after-scene: 1.0               # silence at scene boundaries in seconds (default: 1.0)

# Performance
threads: 3                         # concurrent synthesis worker processes (default: 3)
```

### Example: complete script.yaml

```yaml
# About Time - script conversion config
title: "About Time"
author: "Tadg Paul"

# Cast
auto-assign-voices: true
character-voices:
  KEVIN: am_adam
  NESSA: af_alloy
  CAIT: bf_emma
  BEN: bm_daniel
narrator-voice: bf_alice
intro-voice: bf_alice

# What to render
render-stage-directions: true
render-intro: true
render-footnotes: true

# Pacing
dialogue-speed: 1.0
stage-direction-speed: 0.9
gap-after-dialogue: 0.3
gap-after-stage-direction: 0.5
gap-after-scene: 1.0

# Performance
threads: 3
```

Place this file as `script.yaml` alongside the script file for auto-discovery, or specify it with `--script-config path/to/config.yaml`.

### CLI flags

| Flag | Purpose |
|------|---------|
| `--script-config path` | Path to script.yaml (otherwise auto-discovered) |
| `--threads N` | Override worker process count (overrides YAML `threads`) |
| `--speed N` | Global speed multiplier (multiplied with per-type speeds) |
| `--dry-run` | Preview script structure without synthesis |
| `--non-interactive` | Use metadata from script/config without prompting |

## Voice assignment

Voices are assigned to characters in three phases:

1. **Explicit voice names** - `ALICE: bf_emma` assigns a specific Kokoro voice
2. **Filter shorthands** - `BOB: bm` picks a random British male voice
3. **Auto-assignment** - remaining characters get voices from the available pool

Filter shorthand format: first character = accent (`a` American, `b` British), second character = gender (`f` female, `m` male). Either can be omitted.

Each character retains a consistent voice throughout the entire script.

## Preamble

When `render-intro` is enabled (the default), a preamble chapter is synthesized before the first scene containing:

1. Title and author announcement
2. Character descriptions from the character table
3. Outline text

The preamble uses the `intro-voice` if specified, otherwise falls back to `narrator-voice`.

## Footnotes

Org-mode footnotes (`[fn:name]`) are supported:

- The `[fn:name]` marker is stripped from the spoken dialogue
- The footnote definition is read as a narrator aside immediately after the referencing line
- Useful for glossary notes (e.g. Hiberno-English terms)

Set `render-footnotes: false` to strip markers without reading definitions.

## Stage direction character names

Character names in stage directions are typically ALL CAPS in scripts (e.g. "KEVIN enters the room"). Yapper automatically converts these to Title Case (e.g. "Kevin enters the room") before synthesis to prevent the TTS from spelling them out letter by letter.

## Performance

Script conversion uses multi-process concurrent synthesis by default (3 worker processes). Each worker gets its own Metal context for GPU access. The thread count is configurable:

- `threads: N` in script.yaml
- `--threads N` CLI flag (overrides YAML)
- `--threads 1` for sequential synthesis

Optimal thread count depends on hardware. 3 was determined as the sweet spot on M3/24GB (1.65x speedup). Diminishing returns beyond 3-4 due to GPU saturation.

Audio trimming removes model-generated leading (~280ms) and trailing (~80ms) silence from each line before assembly. When `transcribe` (from tigger04/tap/transcribe-summarize) is available, exact Whisper word timestamps are used for precise trimming. Otherwise, heuristic fixed offsets are applied.

## Metadata precedence

Title and author are resolved in order of precedence:

1. CLI flags (`--title`, `--author`)
2. `script.yaml` values
3. Script file metadata (`#+TITLE:`, `# Title`, etc.)
4. Interactive prompt input (when TTY available)

## Output

Script mode always produces M4B output with:
- One chapter per scene (plus optional preamble chapter)
- Chapter titles matching scene headings
- Title and author M4B metadata tags
