#!/usr/bin/env bash
# ABOUTME: Regression tests for make-audiobook delta features (issue #20).
# ABOUTME: Metadata on all formats, track numbers, text cleanup, batch summary, --non-interactive.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: make-audiobook delta (RT-20.x)\n'

SUITE_TMP=$(mktemp -d)
trap 'rm -rf "${SUITE_TMP}"' EXIT

# ---------------------------------------------------------------------------
# AC20.1: Metadata on M4A/MP3
# ---------------------------------------------------------------------------

# RT-20.1: M4A with --author and --title has artist and album tags.
test_RT20_1() {
    printf 'Metadata test.' > "${SUITE_TMP}/rt201.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt201.txt" -o "${SUITE_TMP}/rt201.m4a" --voice af_heart --author "Test Author" --title "Test Book" --non-interactive >/dev/null 2>&1
    ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${SUITE_TMP}/rt201.m4a" 2>/dev/null | grep -q "Test Author" || return 1
    ffprobe -v quiet -show_entries format_tags=album -of csv=p=0 "${SUITE_TMP}/rt201.m4a" 2>/dev/null | grep -q "Test Book"
}
run_test "RT-20.1" "M4A output has artist and album tags" test_RT20_1

# RT-20.2: Same for MP3 output.
test_RT20_2() {
    printf 'MP3 metadata test.' > "${SUITE_TMP}/rt202.txt"
    "${YAPPER}" convert "${SUITE_TMP}/rt202.txt" -o "${SUITE_TMP}/rt202.mp3" --voice af_heart --author "Test Author" --title "Test Book" --format mp3 --non-interactive >/dev/null 2>&1
    ffprobe -v quiet -show_entries format_tags=artist -of csv=p=0 "${SUITE_TMP}/rt202.mp3" 2>/dev/null | grep -q "Test Author" || return 1
    ffprobe -v quiet -show_entries format_tags=album -of csv=p=0 "${SUITE_TMP}/rt202.mp3" 2>/dev/null | grep -q "Test Book"
}
run_test "RT-20.2" "MP3 output has artist and album tags" test_RT20_2

# RT-20.3: album_artist tag matches artist.
test_RT20_3() {
    ffprobe -v quiet -show_entries format_tags=album_artist -of csv=p=0 "${SUITE_TMP}/rt201.m4a" 2>/dev/null | grep -q "Test Author"
}
run_test "RT-20.3" "album_artist matches artist" test_RT20_3

# ---------------------------------------------------------------------------
# AC20.2: Track numbers and titles
# ---------------------------------------------------------------------------

# RT-20.4: Multi-file produces track numbers.
test_RT20_4() {
    local dir="${SUITE_TMP}/rt204"
    mkdir -p "${dir}"
    printf 'File A.' > "${dir}/a.txt"
    printf 'File B.' > "${dir}/b.txt"
    printf 'File C.' > "${dir}/c.txt"
    (cd "${dir}" && "${YAPPER}" convert a.txt b.txt c.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/a.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/b.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/c.m4a" 2>/dev/null)
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.4" "multi-file has track numbers 1/3, 2/3, 3/3" test_RT20_4

# RT-20.5: Track title matches input filename.
test_RT20_5() {
    local t1
    t1=$(ffprobe -v quiet -show_entries format_tags=title -of csv=p=0 "${SUITE_TMP}/rt204/a.m4a" 2>/dev/null)
    [[ "${t1}" == "a" ]]
}
run_test "RT-20.5" "track title matches input filename" test_RT20_5

# ---------------------------------------------------------------------------
# AC20.4: Format topology
# ---------------------------------------------------------------------------

# RT-20.7: Multi-file default produces M4A files.
test_RT20_7() {
    [[ -f "${SUITE_TMP}/rt204/a.m4a" ]] && [[ -f "${SUITE_TMP}/rt204/b.m4a" ]] && [[ -f "${SUITE_TMP}/rt204/c.m4a" ]]
}
run_test "RT-20.7" "multi-file default produces M4A" test_RT20_7

# RT-20.8: Multi-file with explicit M4B produces one M4B.
test_RT20_8() {
    local dir="${SUITE_TMP}/rt208"
    mkdir -p "${dir}"
    printf 'Chapter one.' > "${dir}/a.txt"
    printf 'Chapter two.' > "${dir}/b.txt"
    (cd "${dir}" && "${YAPPER}" convert a.txt b.txt --format m4b -o "${dir}/book.m4b" --voice af_heart --non-interactive >/dev/null 2>&1)
    [[ -f "${dir}/book.m4b" ]]
}
run_test "RT-20.8" "multi-file with --format m4b produces one M4B" test_RT20_8

# ---------------------------------------------------------------------------
# AC20.5: Text cleanup (via --dry-run showing cleaned text)
# ---------------------------------------------------------------------------

# RT-20.10: Markdown image links stripped from dry-run text.
test_RT20_10() {
    printf 'Hello ![alt text](http://example.com/image.png) world.' > "${SUITE_TMP}/rt2010.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2010.md" --voice af_heart --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -q "Text:" || printf '%s' "${output}" | grep -q "text:" || return 1
    # The image link URL should not appear in the cleaned text
    if printf '%s' "${output}" | grep -q "http://example.com/image.png"; then
        return 1
    fi
    return 0
}
run_test "RT-20.10" "markdown image links stripped from dry-run text" test_RT20_10

# RT-20.11: HTML tags stripped from dry-run text.
test_RT20_11() {
    printf '<div>Hello</div> <span>world</span>.' > "${SUITE_TMP}/rt2011.html"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2011.html" --voice af_heart --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q "<div>"; then
        return 1
    fi
    return 0
}
run_test "RT-20.11" "HTML tags stripped from dry-run text" test_RT20_11

# RT-20.12: {.class} attribute blocks stripped from dry-run text.
test_RT20_12() {
    printf 'Hello {.special-class} world.' > "${SUITE_TMP}/rt2012.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2012.md" --voice af_heart --dry-run --non-interactive 2>&1)
    if printf '%s' "${output}" | grep -q "{.special-class}"; then
        return 1
    fi
    return 0
}
run_test "RT-20.12" "{.class} blocks stripped from dry-run text" test_RT20_12

# ---------------------------------------------------------------------------
# AC20.6: Batch summary
# ---------------------------------------------------------------------------

# RT-20.13: Converting 3 valid files prints success count.
test_RT20_13() {
    local dir="${SUITE_TMP}/rt2013"
    mkdir -p "${dir}"
    printf 'File one.' > "${dir}/a.txt"
    printf 'File two.' > "${dir}/b.txt"
    printf 'File three.' > "${dir}/c.txt"
    local output
    output=$((cd "${dir}" && "${YAPPER}" convert a.txt b.txt c.txt --voice af_heart --non-interactive) 2>&1)
    printf '%s' "${output}" | grep -q "3 of 3.*converted successfully"
}
run_test "RT-20.13" "batch summary shows success count" test_RT20_13

# RT-20.14: Converting 2 valid + 1 missing prints failure.
test_RT20_14() {
    local dir="${SUITE_TMP}/rt2014"
    mkdir -p "${dir}"
    printf 'Good one.' > "${dir}/good.txt"
    printf 'Good two.' > "${dir}/good2.txt"
    local output
    set +e
    output=$((cd "${dir}" && "${YAPPER}" convert good.txt missing.txt good2.txt --voice af_heart --non-interactive) 2>&1)
    set -e
    printf '%s' "${output}" | grep -q "missing.txt"
}
run_test "RT-20.14" "batch summary lists failures" test_RT20_14

# ---------------------------------------------------------------------------
# AC20.7: --non-interactive
# ---------------------------------------------------------------------------

# RT-20.15: --non-interactive skips prompts even with TTY stdin.
test_RT20_15() {
    printf 'Non-interactive test.' > "${SUITE_TMP}/rt2015.txt"
    # If this hangs, --non-interactive isn't working (it would block on prompt).
    # The 5-second timeout catches that.
    timeout 5 "${YAPPER}" convert "${SUITE_TMP}/rt2015.txt" -o "${SUITE_TMP}/rt2015.m4a" --voice af_heart --non-interactive >/dev/null 2>&1
}
run_test "RT-20.15" "--non-interactive skips prompts" test_RT20_15

# RT-20.16: Output file is still produced with --non-interactive.
test_RT20_16() {
    [[ -f "${SUITE_TMP}/rt2015.m4a" ]]
}
run_test "RT-20.16" "output produced with --non-interactive" test_RT20_16

# ---------------------------------------------------------------------------
# AC20.8: Track numbers from filenames
# ---------------------------------------------------------------------------

# RT-20.17: Consecutive numbered files get track numbers from filenames.
test_RT20_17() {
    local dir="${SUITE_TMP}/rt2017"
    mkdir -p "${dir}"
    printf 'Chapter one.' > "${dir}/ch01.txt"
    printf 'Chapter two.' > "${dir}/ch02.txt"
    printf 'Chapter three.' > "${dir}/ch03.txt"
    (cd "${dir}" && "${YAPPER}" convert ch01.txt ch02.txt ch03.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch01.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch02.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch03.m4a" 2>/dev/null)
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.17" "consecutive numbered files get correct track numbers" test_RT20_17

# RT-20.18: Zero-start consecutive sequence detected.
test_RT20_18() {
    local dir="${SUITE_TMP}/rt2018"
    mkdir -p "${dir}"
    printf 'Part zero.' > "${dir}/ch00.txt"
    printf 'Part one.' > "${dir}/ch01.txt"
    printf 'Part two.' > "${dir}/ch02.txt"
    (cd "${dir}" && "${YAPPER}" convert ch00.txt ch01.txt ch02.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch00.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch01.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch02.m4a" 2>/dev/null)
    # 0-based filenames are shifted to 1-based for track metadata (track 0 is
    # not meaningful in ID3/MP4 tags), but the sequence is still detected as
    # consecutive rather than falling back to positional.
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.18" "zero-start consecutive sequence detected and shifted to 1-based" test_RT20_18

# RT-20.19: No integers in filenames → positional fallback.
test_RT20_19() {
    local dir="${SUITE_TMP}/rt2019"
    mkdir -p "${dir}"
    printf 'Intro.' > "${dir}/intro.txt"
    printf 'Body.' > "${dir}/body.txt"
    printf 'End.' > "${dir}/end.txt"
    (cd "${dir}" && "${YAPPER}" convert intro.txt body.txt end.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/intro.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/body.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/end.m4a" 2>/dev/null)
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.19" "no integers → positional fallback" test_RT20_19

# RT-20.20: Non-consecutive integers → positional fallback.
test_RT20_20() {
    local dir="${SUITE_TMP}/rt2020"
    mkdir -p "${dir}"
    printf 'Part five.' > "${dir}/ch05.txt"
    printf 'Part ten.' > "${dir}/ch10.txt"
    printf 'Part ninety-nine.' > "${dir}/ch99.txt"
    (cd "${dir}" && "${YAPPER}" convert ch05.txt ch10.txt ch99.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch05.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch10.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch99.m4a" 2>/dev/null)
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.20" "non-consecutive integers → positional fallback" test_RT20_20

# RT-20.21: Mixed filenames (some with integers, some without) → positional fallback.
test_RT20_21() {
    local dir="${SUITE_TMP}/rt2021"
    mkdir -p "${dir}"
    printf 'Intro.' > "${dir}/intro.txt"
    printf 'Chapter one.' > "${dir}/ch01.txt"
    printf 'Chapter two.' > "${dir}/ch02.txt"
    (cd "${dir}" && "${YAPPER}" convert intro.txt ch01.txt ch02.txt --voice af_heart --non-interactive >/dev/null 2>&1)
    local t1 t2 t3
    t1=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/intro.m4a" 2>/dev/null)
    t2=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch01.m4a" 2>/dev/null)
    t3=$(ffprobe -v quiet -show_entries format_tags=track -of csv=p=0 "${dir}/ch02.m4a" 2>/dev/null)
    [[ "${t1}" == "1/3" ]] && [[ "${t2}" == "2/3" ]] && [[ "${t3}" == "3/3" ]]
}
run_test "RT-20.21" "mixed filenames → positional fallback" test_RT20_21

# ---------------------------------------------------------------------------
# AC20.9: --dry-run shows cleaned text
# ---------------------------------------------------------------------------

# RT-20.22: --dry-run output includes cleaned text content.
test_RT20_22() {
    printf 'Hello world from dry run.' > "${SUITE_TMP}/rt2022.txt"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2022.txt" --voice af_heart --dry-run --non-interactive 2>&1)
    printf '%s' "${output}" | grep -qi "Hello world from dry run"
}
run_test "RT-20.22" "--dry-run output includes cleaned text" test_RT20_22

# RT-20.28: Markdown links reduced to link text in dry-run.
test_RT20_28() {
    printf 'Visit [Example Site](http://example.com) for more.' > "${SUITE_TMP}/rt2028.md"
    local output
    output=$("${YAPPER}" convert "${SUITE_TMP}/rt2028.md" --voice af_heart --dry-run --non-interactive 2>&1)
    # Should contain "Example Site" but not the URL
    printf '%s' "${output}" | grep -q "Example Site" || return 1
    if printf '%s' "${output}" | grep -q "http://example.com"; then
        return 1
    fi
    return 0
}
run_test "RT-20.28" "markdown links reduced to link text in dry-run" test_RT20_28

summarise "make-audiobook delta"
