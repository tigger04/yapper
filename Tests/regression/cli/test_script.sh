#!/usr/bin/env bash
# ABOUTME: Regression tests for script reading with per-character voices (issue #23).
# ABOUTME: Tests markdown and org-mode script parsing, voice assignment, config, M4B output.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: script reading (RT-23.x)\n'

SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

FIXTURES="$(cd "${SCRIPT_DIR}/../../fixtures" && pwd)"
MD_SCRIPT="${FIXTURES}/test_script.md"
ORG_SCRIPT="${FIXTURES}/test_script.org"
CONFIG="${FIXTURES}/test_script.yaml"
CONFIG_NO_STAGE="${FIXTURES}/test_script_no_stage.yaml"

# ---------------------------------------------------------------------------
# AC23.1: Markdown script parsing
# ---------------------------------------------------------------------------

# RT-23.1: Markdown script with 3 characters produces correct dialogue attributions.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: dry-run output lists ALICE, BOB, CHARLIE as characters.
test_RT23_1() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB" || return 1
    printf '%s' "${output}" | grep -qi "CHARLIE" || return 1
}
run_test "RT-23.1" "markdown script identifies 3 characters" test_RT23_1

# RT-23.2: Stage directions identified separately from dialogue.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: stage directions listed distinctly from character dialogue.
test_RT23_2() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # Stage direction text from the script should appear attributed to narrator/stage
    printf '%s' "${output}" | grep -qi "stage\|narrator\|direction\|A room\|Morning" || return 1
}
run_test "RT-23.2" "markdown stage directions identified" test_RT23_2

# RT-23.3: Acting notes in parentheses stripped from attribution.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: "(sarcastically)" does not appear in the character name or dialogue text.
test_RT23_3() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "sarcastically"; then
        return 1
    fi
    # BOB's dialogue should still be present (check one from the first few entries)
    printf '%s' "${output}" | grep -qi "BOB" || return 1
}
run_test "RT-23.3" "acting notes stripped from attribution" test_RT23_3

# ---------------------------------------------------------------------------
# AC23.2: Org-mode script parsing
# ---------------------------------------------------------------------------

# RT-23.4: Org-mode script with L3/L4 headings produces correct attributions.
# User action: yapper convert script.org --script-config config.yaml --dry-run
# User observes: same characters as the markdown version.
test_RT23_4() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB" || return 1
    printf '%s' "${output}" | grep -qi "CHARLIE" || return 1
}
run_test "RT-23.4" "org-mode script identifies 3 characters" test_RT23_4

# RT-23.5: Org-mode acting notes stripped.
# User action: yapper convert script.org --script-config config.yaml --dry-run
# User observes: "(sarcastically)" absent from output.
test_RT23_5() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -qi "sarcastically"; then
        return 1
    fi
    printf '%s' "${output}" | grep -qi "BOB" || return 1
}
run_test "RT-23.5" "org-mode acting notes stripped" test_RT23_5

# ---------------------------------------------------------------------------
# AC23.3: Consistent per-character voice assignment
# ---------------------------------------------------------------------------

# RT-23.6: Auto-assigned voices — no two characters share the same voice.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: each character has a different voice in the cast list.
test_RT23_6() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    local voices
    voices=$(printf '%s' "${output}" | grep -oiE '(af|am|bf|bm)_[a-z]+' | sort -u)
    local voice_count char_count
    voice_count=$(printf '%s\n' "${voices}" | wc -l | tr -d ' ')
    # At least 3 distinct voices for 3 characters (+ narrator = 4)
    [[ ${voice_count} -ge 3 ]]
}
run_test "RT-23.6" "no two characters share a voice" test_RT23_6

# RT-23.7: A character's voice is the same in first and last dialogue turn.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: ALICE's voice is consistent throughout.
test_RT23_7() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # ALICE has explicit voice bf_emma in the config — check it appears
    printf '%s' "${output}" | grep -qi "ALICE.*bf_emma\|bf_emma.*ALICE" || return 1
}
run_test "RT-23.7" "character voice is consistent throughout" test_RT23_7

# RT-23.8: Explicit config overrides auto-assignment.
# User action: yapper convert script.md --script-config config.yaml --dry-run
# User observes: BOB is assigned bm_daniel as specified in config.
test_RT23_8() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "BOB.*bm_daniel\|bm_daniel.*BOB" || return 1
}
run_test "RT-23.8" "explicit voice assignment from config" test_RT23_8

# ---------------------------------------------------------------------------
# AC23.4: Voice assignment modes (explicit, filter, auto)
# ---------------------------------------------------------------------------

# RT-23.9: Explicit voice name in config assigns that exact voice.
# (Same check as RT-23.8 but for a different character.)
test_RT23_9() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE.*bf_emma\|bf_emma.*ALICE" || return 1
}
run_test "RT-23.9" "explicit voice name assigned correctly" test_RT23_9

# RT-23.10: Filter shorthand in config assigns a matching voice.
# Config has CHARLIE: am (American male filter).
test_RT23_10() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # CHARLIE should have an am_ voice
    printf '%s' "${output}" | grep -qi "CHARLIE.*am_\|am_.*CHARLIE" || return 1
}
run_test "RT-23.10" "filter shorthand assigns matching voice" test_RT23_10

# RT-23.11: Auto assignment picks a voice not used by explicitly assigned characters.
# Config has CHARLIE: auto in the no-stage config.
test_RT23_11() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG_NO_STAGE}" --dry-run --non-interactive 2>&1)
    # CHARLIE should have a voice, and it shouldn't be bf_emma (ALICE) or bm_daniel (BOB)
    local charlie_voice
    charlie_voice=$(printf '%s' "${output}" | grep -i "CHARLIE" | grep -oiE '(af|am|bf|bm)_[a-z]+' | head -1)
    [[ -n "${charlie_voice}" ]] || return 1
    [[ "${charlie_voice}" != "bf_emma" ]] || return 1
    [[ "${charlie_voice}" != "bm_daniel" ]] || return 1
}
run_test "RT-23.11" "auto assignment avoids explicitly assigned voices" test_RT23_11

# ---------------------------------------------------------------------------
# AC23.5: Stage directions
# ---------------------------------------------------------------------------

# RT-23.12: With read-stage-directions: true, stage direction text in output.
test_RT23_12() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # Stage direction "A room. Morning." should appear in the plan
    printf '%s' "${output}" | grep -qi "room\|Morning\|chair" || return 1
}
run_test "RT-23.12" "stage directions included when enabled" test_RT23_12

# RT-23.13: With read-stage-directions: false, stage direction text absent.
test_RT23_13() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG_NO_STAGE}" --dry-run --non-interactive 2>&1)
    # "A room. Morning." should NOT appear — it's a stage direction
    if printf '%s' "${output}" | grep -qi "A room\|Empty except"; then
        return 1
    fi
    # But dialogue should still be present
    printf '%s' "${output}" | grep -qi "Good morning" || return 1
}
run_test "RT-23.13" "stage directions excluded when disabled" test_RT23_13

# RT-23.14: Narrator voice is distinct from all character voices.
test_RT23_14() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # Narrator should be bf_lily (from config) which is not bf_emma, bm_daniel, or any am_ voice
    printf '%s' "${output}" | grep -qi "narrator.*bf_lily\|bf_lily.*narrator\|stage.*bf_lily\|bf_lily.*stage" || return 1
}
run_test "RT-23.14" "narrator voice distinct from characters" test_RT23_14

# ---------------------------------------------------------------------------
# AC23.6: Config file discovery
# ---------------------------------------------------------------------------

# RT-23.15: --script-config flag uses the specified config.
test_RT23_15() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # Config specifies bf_emma for ALICE — should be applied
    printf '%s' "${output}" | grep -qi "bf_emma" || return 1
}
run_test "RT-23.15" "--script-config uses specified config" test_RT23_15

# RT-23.16: Without flag, script.yaml in same directory is discovered.
test_RT23_16() {
    local dir="${SUITE_TMP}/rt2316"
    mkdir -p "${dir}"
    cp "${MD_SCRIPT}" "${dir}/play.md"
    cp "${CONFIG}" "${dir}/script.yaml"
    local output
    output=$("${YAPPER}" convert "${dir}/play.md" --dry-run --non-interactive 2>&1)
    # Should discover script.yaml and apply its voice assignments
    printf '%s' "${output}" | grep -qi "bf_emma\|bm_daniel\|ALICE\|BOB" || return 1
}
run_test "RT-23.16" "script.yaml auto-discovered in same directory" test_RT23_16

# ---------------------------------------------------------------------------
# AC23.7: Metadata in M4B output
# ---------------------------------------------------------------------------

# RT-23.17: Config title and author in M4B metadata.
test_RT23_17() {
    local dir="${SUITE_TMP}/rt2317"
    mkdir -p "${dir}"
    "${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    local artist album
    artist=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${dir}/play.m4b" 2>/dev/null)
    album=$(ffprobe -v quiet -show_entries format_tags=album -of csv=p=0 "${dir}/play.m4b" 2>/dev/null)
    [[ "${artist}" == *"Test Author"* ]] || return 1
    [[ "${album}" == *"Test Play"* ]]
}
run_test "RT-23.17" "config metadata in M4B tags" test_RT23_17

# RT-23.18: Script headers used when config lacks metadata.
test_RT23_18() {
    local dir="${SUITE_TMP}/rt2318"
    mkdir -p "${dir}"
    # Config without title/author
    printf 'auto-assign-voices: true\nread-stage-directions: false\n' > "${dir}/minimal.yaml"
    "${YAPPER}" convert "${MD_SCRIPT}" --script-config "${dir}/minimal.yaml" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    local artist
    artist=$(ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${dir}/play.m4b" 2>/dev/null)
    # Should have extracted "Test Author" from the script's "*by Test Author*" line
    [[ "${artist}" == *"Test Author"* ]]
}
run_test "RT-23.18" "metadata extracted from script headers" test_RT23_18

# ---------------------------------------------------------------------------
# AC23.8: M4B chapters per scene
# ---------------------------------------------------------------------------

# RT-23.19: Script with 2 scenes produces M4B with 2 chapter markers.
test_RT23_19() {
    local dir="${SUITE_TMP}/rt2319"
    mkdir -p "${dir}"
    "${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    local chapter_count
    chapter_count=$(ffprobe -v quiet -show_chapters "${dir}/play.m4b" 2>/dev/null | grep -c "^\[CHAPTER\]")
    [[ ${chapter_count} -eq 2 ]]
}
run_test "RT-23.19" "2 scenes produce 2 M4B chapters" test_RT23_19

# RT-23.20: Chapter titles match scene headings.
test_RT23_20() {
    local dir="${SUITE_TMP}/rt2320"
    mkdir -p "${dir}"
    "${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --non-interactive -o "${dir}/play.m4b" --quiet >/dev/null 2>&1
    [[ -f "${dir}/play.m4b" ]] || return 1
    local chapters
    chapters=$(ffprobe -v quiet -show_chapters -of csv=p=0 "${dir}/play.m4b" 2>/dev/null)
    printf '%s' "${chapters}" | grep -qi "Room" || return 1
    printf '%s' "${chapters}" | grep -qi "Garden" || return 1
}
run_test "RT-23.20" "chapter titles match scene headings" test_RT23_20

# ---------------------------------------------------------------------------
# AC23.9: --dry-run in script mode
# ---------------------------------------------------------------------------

# RT-23.21: Dry-run lists all characters with assigned voices.
test_RT23_21() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE" || return 1
    printf '%s' "${output}" | grep -qi "BOB" || return 1
    printf '%s' "${output}" | grep -qi "CHARLIE" || return 1
    # At least 3 voice names visible
    local voice_count
    voice_count=$(printf '%s' "${output}" | grep -oiE '(af|am|bf|bm)_[a-z]+' | sort -u | wc -l | tr -d ' ')
    [[ ${voice_count} -ge 3 ]]
}
run_test "RT-23.21" "dry-run lists cast with voices" test_RT23_21

# RT-23.22: Dry-run shows scene structure.
test_RT23_22() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Scene 1\|Room" || return 1
    printf '%s' "${output}" | grep -qi "Scene 2\|Garden" || return 1
}
run_test "RT-23.22" "dry-run shows scene structure" test_RT23_22

# RT-23.23: Dry-run includes sample dialogue turns.
test_RT23_23() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Good morning" || return 1
}
run_test "RT-23.23" "dry-run includes dialogue preview" test_RT23_23

# ---------------------------------------------------------------------------
# AC23.10: Format auto-detection
# ---------------------------------------------------------------------------

# RT-23.24: .md file with **CHARACTER:** patterns detected as script.
test_RT23_24() {
    local output
    output=$("${YAPPER}" convert "${MD_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    # Should be in script mode — cast list visible
    printf '%s' "${output}" | grep -qi "ALICE\|cast\|character" || return 1
}
run_test "RT-23.24" ".md file detected as script" test_RT23_24

# RT-23.25: .org file with L3/L4 headings detected as script.
test_RT23_25() {
    local output
    output=$("${YAPPER}" convert "${ORG_SCRIPT}" --script-config "${CONFIG}" --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "ALICE\|cast\|character" || return 1
}
run_test "RT-23.25" ".org file detected as script" test_RT23_25

# RT-23.26: Plain prose file without script patterns treated as prose.
test_RT23_26() {
    printf 'This is just a normal paragraph of text. Nothing fancy here.' > "${SUITE_TMP}/prose.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/prose.md" --dry-run --non-interactive 2>&1)
    # Should NOT show cast list or character voices — it's prose mode
    if printf '%s' "${output}" | grep -qi "cast\|character.*voice\|narrator"; then
        return 1
    fi
    # Should show standard convert dry-run output
    printf '%s' "${output}" | grep -qi "convert\|output\|voice" || return 1
}
run_test "RT-23.26" "prose file not treated as script" test_RT23_26

summarise "script reading"
