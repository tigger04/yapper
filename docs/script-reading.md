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

For the full configuration reference, config cascade rules, and example configs, see [docs/config.md](config.md).

Script-specific config keys include voice assignment, content rendering (stage directions, preamble, footnotes), pacing (per-type speed and gaps), and performance (thread count). All keys are optional with sensible defaults.

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
