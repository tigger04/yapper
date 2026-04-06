#!/usr/bin/env bash
# ABOUTME: Regression tests for `yapper convert` (issue #6).
# ABOUTME: Each test invokes the built yapper binary exactly as a user would.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: yapper convert (RT-6.x)\n'

# Shared temp directory for this suite
SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

# ---------------------------------------------------------------------------
# Issue #6: plain text to audio file conversion
# Specs from: https://github.com/tigger04/yapper/issues/6
# ---------------------------------------------------------------------------

# RT-6.1: Output file exists and is valid M4A (ffprobe confirms).
# User action: yapper convert input.txt -o output.m4a
# User observes: output.m4a exists, plays in any audio player.
test_RT6_1() {
    printf 'Hello world.' > "${SUITE_TMP}/rt61.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt61.txt" -o "${SUITE_TMP}/rt61.m4a" --voice af_heart >/dev/null 2>&1
    [[ -f "${SUITE_TMP}/rt61.m4a" ]] || return 1
    ffprobe -v quiet -show_entries format=format_name -of csv=p=0 "${SUITE_TMP}/rt61.m4a" 2>/dev/null | grep -qE "m4a|mov"
}
run_test "RT-6.1" "output is valid M4A" test_RT6_1

# RT-6.2: Output audio duration is proportional to input text length.
# User action: convert short text, convert long text, compare durations.
# User observes: longer text produces longer audio.
test_RT6_2() {
    printf 'Hi.' > "${SUITE_TMP}/rt62_short.txt"
    printf 'This is a much longer sentence with many more words to speak aloud during this test.' > "${SUITE_TMP}/rt62_long.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt62_short.txt" -o "${SUITE_TMP}/rt62_short.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${SUITE_TMP}/rt62_long.txt" -o "${SUITE_TMP}/rt62_long.m4a" --voice af_heart >/dev/null 2>&1
    local short_size long_size
    short_size=$(stat -f%z "${SUITE_TMP}/rt62_short.m4a")
    long_size=$(stat -f%z "${SUITE_TMP}/rt62_long.m4a")
    [[ ${long_size} -gt ${short_size} ]]
}
run_test "RT-6.2" "duration proportional to text length" test_RT6_2

# RT-6.3: yapper convert notes.txt produces notes.m4a (default output name).
# User action: yapper convert notes.txt (no -o flag)
# User observes: notes.m4a appears in the same directory.
test_RT6_3() {
    local dir="${SUITE_TMP}/rt63"
    mkdir -p "${dir}"
    printf 'Default name test.' > "${dir}/notes.txt"
    (cd "${dir}" && "${YAPPER}" convert notes.txt --voice af_heart >/dev/null 2>&1)
    [[ -f "${dir}/notes.m4a" ]]
}
run_test "RT-6.3" "default output name is input.m4a" test_RT6_3

# RT-6.4: Explicit -o flag overrides the default name.
# User action: yapper convert input.txt -o custom.m4a
# User observes: custom.m4a exists, input.m4a does not.
test_RT6_4() {
    local dir="${SUITE_TMP}/rt64"
    mkdir -p "${dir}"
    printf 'Override test.' > "${dir}/input.txt"
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/custom.m4a" --voice af_heart >/dev/null 2>&1
    [[ -f "${dir}/custom.m4a" ]] && [[ ! -f "${dir}/input.m4a" ]]
}
run_test "RT-6.4" "explicit -o overrides default name" test_RT6_4

# RT-6.5: --voice am_adam produces audio with the specified voice.
# User action: yapper convert file.txt --voice am_adam --dry-run
# User observes: dry-run output shows voice: am_adam.
test_RT6_5() {
    printf 'Voice test.' > "${SUITE_TMP}/rt65.txt"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt65.txt" --voice am_adam --dry-run 2>&1)
    printf '%s' "${output}" | grep -qi "am_adam"
}
run_test "RT-6.5" "--voice selects the specified voice" test_RT6_5

# RT-6.6: --speed 1.5 produces shorter audio than default.
# User action: convert same text at normal and fast speed, compare.
# User observes: fast output file is smaller.
test_RT6_6() {
    printf 'Speed test sentence with enough words.' > "${SUITE_TMP}/rt66.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt66.txt" -o "${SUITE_TMP}/rt66_normal.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${SUITE_TMP}/rt66.txt" -o "${SUITE_TMP}/rt66_fast.m4a" --voice af_heart --speed 1.5 >/dev/null 2>&1
    local normal_size fast_size
    normal_size=$(stat -f%z "${SUITE_TMP}/rt66_normal.m4a")
    fast_size=$(stat -f%z "${SUITE_TMP}/rt66_fast.m4a")
    [[ ${fast_size} -lt ${normal_size} ]]
}
run_test "RT-6.6" "--speed 1.5 produces shorter audio" test_RT6_6

# RT-6.7: --author "Name" sets the artist ID3 tag.
# User action: yapper convert file.txt --author "Test Author" -o out.m4a
# User observes: ffprobe shows artist=Test Author.
test_RT6_7() {
    printf 'Metadata test.' > "${SUITE_TMP}/rt67.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt67.txt" -o "${SUITE_TMP}/rt67.m4a" --voice af_heart --author "Test Author" >/dev/null 2>&1
    ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${SUITE_TMP}/rt67.m4a" 2>/dev/null | grep -q "Test Author"
}
run_test "RT-6.7" "--author embeds artist metadata" test_RT6_7

# RT-6.9: Missing input file produces descriptive error.
# User action: yapper convert nonexistent.txt
# User observes: error message, non-zero exit.
test_RT6_9() {
    if "${YAPPER}" convert "${SUITE_TMP}/nonexistent_file.txt" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-6.9" "missing input file produces error" test_RT6_9

# RT-6.10: Missing ffmpeg produces actionable error message.
# This test checks the error-path code, not the actual ffmpeg presence.
# We keep the existing Swift implementation since it manipulates PATH
# to simulate ffmpeg absence — that's an engine-level concern.
# See #17 for the KEEP decision.

# RT-6.13: Empty text file produces descriptive error.
# User action: yapper convert empty.txt
# User observes: error message, non-zero exit.
test_RT6_13() {
    printf '' > "${SUITE_TMP}/rt613.txt"
    if "${YAPPER}" convert "${SUITE_TMP}/rt613.txt" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-6.13" "empty file produces error" test_RT6_13

# RT-6.14: Whitespace-only file produces descriptive error.
# User action: yapper convert whitespace.txt
# User observes: error message, non-zero exit.
test_RT6_14() {
    printf '   \n\t  \n' > "${SUITE_TMP}/rt614.txt"
    if "${YAPPER}" convert "${SUITE_TMP}/rt614.txt" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-6.14" "whitespace-only file produces error" test_RT6_14

# RT-6.15: Existing output file is renamed to .bak before overwriting.
# User action: yapper convert file.txt twice to same output path.
# User observes: output.m4a exists, output.m4a.bak exists.
test_RT6_15() {
    local dir="${SUITE_TMP}/rt615"
    mkdir -p "${dir}"
    printf 'Backup test.' > "${dir}/input.txt"
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart >/dev/null 2>&1
    [[ -f "${dir}/output.m4a" ]] && [[ -f "${dir}/output.m4a.bak" ]]
}
run_test "RT-6.15" "existing output backed up to .bak" test_RT6_15

# RT-6.16: Multiple runs produce .bak, .1.bak, .2.bak etc.
# User action: yapper convert file.txt three times to same output path.
# User observes: output.m4a, output.m4a.bak, output.m4a.1.bak all exist.
test_RT6_16() {
    local dir="${SUITE_TMP}/rt616"
    mkdir -p "${dir}"
    printf 'Incremental backup test.' > "${dir}/input.txt"
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${dir}/input.txt" -o "${dir}/output.m4a" --voice af_heart >/dev/null 2>&1
    [[ -f "${dir}/output.m4a" ]] && [[ -f "${dir}/output.m4a.bak" ]] && ls "${dir}"/output.m4a.*.bak >/dev/null 2>&1
}
run_test "RT-6.16" "incremental backups (.bak, .1.bak)" test_RT6_16

# RT-6.19: Multiple input files produce multiple output files.
# User action: yapper convert a.txt b.txt c.txt
# User observes: a.m4a, b.m4a, c.m4a all exist.
test_RT6_19() {
    local dir="${SUITE_TMP}/rt619"
    mkdir -p "${dir}"
    printf 'File A.' > "${dir}/a.txt"
    printf 'File B.' > "${dir}/b.txt"
    printf 'File C.' > "${dir}/c.txt"
    (cd "${dir}" && "${YAPPER}" convert a.txt b.txt c.txt --voice af_heart >/dev/null 2>&1)
    [[ -f "${dir}/a.m4a" ]] && [[ -f "${dir}/b.m4a" ]] && [[ -f "${dir}/c.m4a" ]]
}
run_test "RT-6.19" "multiple inputs produce multiple outputs" test_RT6_19

# RT-6.21: Zero input files produces descriptive error.
# User action: yapper convert (no arguments)
# User observes: error message, non-zero exit.
test_RT6_21() {
    if "${YAPPER}" convert >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-6.21" "zero inputs produces error" test_RT6_21

summarise "yapper convert"
