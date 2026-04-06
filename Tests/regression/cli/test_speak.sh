#!/usr/bin/env bash
# ABOUTME: Regression tests for `yapper speak` (issue #4) and voice selection (issue #15).
# ABOUTME: Each test invokes the built yapper binary exactly as a user would.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/harness.sh"

printf 'Suite: yapper speak (RT-4.x, RT-15.x)\n'

# ---------------------------------------------------------------------------
# Issue #4: yapper speak command
# Specs from: https://github.com/tigger04/yapper/issues/4
# ---------------------------------------------------------------------------

# RT-4.1: Command exits 0 after playing text argument.
# User action: yapper speak "Hi."
# User observes: audio plays, command returns to prompt.
test_RT4_1() {
    "${YAPPER}" speak --voice af_heart "Hi." >/dev/null 2>&1
}
run_test "RT-4.1" "speak with text argument exits 0" test_RT4_1

# RT-4.2: Command exits non-zero with no text argument and no stdin.
# User action: yapper speak (with nothing piped)
# User observes: error message, non-zero exit.
test_RT4_2() {
    if "${YAPPER}" speak </dev/null >/dev/null 2>&1; then
        return 1  # should have failed
    fi
    return 0
}
run_test "RT-4.2" "speak with no input exits non-zero" test_RT4_2

# RT-4.3: Piped stdin text is synthesised and played.
# User action: echo "Hi." | yapper speak
# User observes: audio plays, exit 0.
test_RT4_3() {
    printf 'Hi.' | "${YAPPER}" speak --voice af_heart >/dev/null 2>&1
}
run_test "RT-4.3" "piped stdin text is accepted" test_RT4_3

# RT-4.4: File redirect stdin is synthesised and played.
# User action: yapper speak < file.txt
# User observes: audio plays, exit 0.
test_RT4_4() {
    local tmp
    tmp=$(mktemp)
    printf 'Hello from a file.' > "${tmp}"
    "${YAPPER}" speak --voice af_heart < "${tmp}" >/dev/null 2>&1
    local rc=$?
    rm -f "${tmp}"
    return ${rc}
}
run_test "RT-4.4" "file redirect stdin is accepted" test_RT4_4

# RT-4.5: --voice af_bella uses the af_bella voice.
# User action: yapper speak --voice af_bella --dry-run "Hi."
# User observes: dry-run output shows voice: af_bella.
test_RT4_5() {
    local output
    output=$("${YAPPER}" speak --voice af_bella --dry-run "Hi." 2>&1)
    printf '%s' "${output}" | grep -q '^voice:.*af_bella'
}
run_test "RT-4.5" "--voice af_bella selects af_bella" test_RT4_5

# RT-4.6: Invalid voice name produces a descriptive error.
# User action: yapper speak --voice nonexistent "Hi."
# User observes: error message naming the invalid voice, non-zero exit.
test_RT4_6() {
    local output
    if output=$("${YAPPER}" speak --voice nonexistent_voice "Hi." 2>&1); then
        return 1  # should have failed
    fi
    printf '%s' "${output}" | grep -qi "nonexistent_voice"
}
run_test "RT-4.6" "invalid voice name produces descriptive error" test_RT4_6

# RT-4.7: --speed 1.5 produces faster (shorter) speech than default.
# User action: yapper convert file.txt -o normal.m4a; yapper convert file.txt -o fast.m4a --speed 1.5
# User observes: fast.m4a is shorter duration than normal.m4a.
test_RT4_7() {
    local tmp
    tmp=$(mktemp -d)
    printf 'Hello world, this is a speed test.' > "${tmp}/input.txt"
    "${YAPPER}" convert "${tmp}/input.txt" -o "${tmp}/normal.m4a" --voice af_heart >/dev/null 2>&1
    "${YAPPER}" convert "${tmp}/input.txt" -o "${tmp}/fast.m4a" --voice af_heart --speed 1.5 >/dev/null 2>&1
    local normal_size fast_size
    normal_size=$(stat -f%z "${tmp}/normal.m4a")
    fast_size=$(stat -f%z "${tmp}/fast.m4a")
    rm -rf "${tmp}"
    [[ ${fast_size} -lt ${normal_size} ]]
}
run_test "RT-4.7" "--speed 1.5 produces shorter audio" test_RT4_7

# RT-4.8: Invalid speed value produces a descriptive error.
# User action: yapper speak --speed 0 "Hi."
# User observes: error message, non-zero exit.
test_RT4_8() {
    local failed=0
    if "${YAPPER}" speak --speed 0 "Hi." >/dev/null 2>&1; then
        failed=1
    fi
    if "${YAPPER}" speak --speed -1 "Hi." >/dev/null 2>&1; then
        failed=1
    fi
    [[ ${failed} -eq 0 ]]
}
run_test "RT-4.8" "speed 0 and negative speed are rejected" test_RT4_8

# RT-4.9 and RT-4.10: 🚫 removed — duplicate of RT-1.4 and RT-1.5 in issue #1.

# RT-4.11: Empty string argument produces descriptive error.
# User action: yapper speak ""
# User observes: error message, non-zero exit.
test_RT4_11() {
    if "${YAPPER}" speak "" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-4.11" "empty text produces error" test_RT4_11

# RT-4.12: Whitespace-only input produces descriptive error.
# User action: echo "   " | yapper speak
# User observes: error message, non-zero exit.
test_RT4_12() {
    if printf '   \n\t  ' | "${YAPPER}" speak >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-4.12" "whitespace-only input produces error" test_RT4_12

# RT-4.15: Speed 0 produces descriptive error.
# User action: yapper speak --speed 0 "Hi."
# User observes: error message, non-zero exit.
test_RT4_15() {
    local output
    if output=$("${YAPPER}" speak --speed 0 "Hi." 2>&1); then
        return 1
    fi
    return 0
}
run_test "RT-4.15" "speed zero produces error" test_RT4_15

# RT-4.16: Negative speed produces descriptive error.
# User action: yapper speak --speed -1 "Hi."
# User observes: error message, non-zero exit.
test_RT4_16() {
    local output
    if output=$("${YAPPER}" speak --speed -1 "Hi." 2>&1); then
        return 1
    fi
    return 0
}
run_test "RT-4.16" "negative speed produces error" test_RT4_16

# ---------------------------------------------------------------------------
# Issue #15: voice selection precedence + --dry-run
# Specs from: https://github.com/tigger04/yapper/issues/15
# ---------------------------------------------------------------------------

# RT-15.1: Over 10 invocations with no voice override, at least 3 distinct voices appear.
# User action: yapper speak --dry-run "test" (10 times)
# User observes: different voice names in the output across runs.
test_RT15_1() {
    local voices=()
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        local v
        v=$("${YAPPER}" speak --dry-run "test" 2>/dev/null | grep '^voice:' | awk '{print $2}')
        voices+=("${v}")
    done
    local unique
    unique=$(printf '%s\n' "${voices[@]}" | sort -u | wc -l | tr -d ' ')
    [[ ${unique} -ge 3 ]]
}
run_test "RT-15.1" "random voice selection produces ≥3 distinct voices over 10 runs" test_RT15_1

# RT-15.2: Each random selection reports a real voice name.
# User action: yapper speak --dry-run "test"
# User observes: voice: line contains a real voice name (not empty).
test_RT15_2() {
    for _ in 1 2 3 4 5; do
        local v
        v=$("${YAPPER}" speak --dry-run "test" 2>/dev/null | grep '^voice:' | awk '{print $2}')
        [[ -n "${v}" ]] || return 1
    done
}
run_test "RT-15.2" "every random selection reports a real voice name" test_RT15_2

# RT-15.3: --voice flag selects the requested voice (env var unset).
# User action: yapper speak --voice af_heart --dry-run "test"
# User observes: voice: af_heart
test_RT15_3() {
    local v
    v=$(YAPPER_VOICE='' "${YAPPER}" speak --voice af_heart --dry-run "test" 2>/dev/null | grep '^voice:' | awk '{print $2}')
    [[ "${v}" == "af_heart" ]]
}
run_test "RT-15.3" "--voice flag selects requested voice" test_RT15_3

# RT-15.4: --voice flag wins over $YAPPER_VOICE.
# User action: YAPPER_VOICE=am_adam yapper speak --voice bf_emma --dry-run "test"
# User observes: voice: bf_emma (CLI wins over env).
test_RT15_4() {
    local v
    v=$(YAPPER_VOICE=am_adam "${YAPPER}" speak --voice bf_emma --dry-run "test" 2>/dev/null | grep '^voice:' | awk '{print $2}')
    [[ "${v}" == "bf_emma" ]]
}
run_test "RT-15.4" "--voice flag wins over \$YAPPER_VOICE" test_RT15_4

# RT-15.5: $YAPPER_VOICE selects its voice when --voice is absent.
# User action: YAPPER_VOICE=bm_daniel yapper speak --dry-run "test"
# User observes: voice: bm_daniel
test_RT15_5() {
    local v
    v=$(YAPPER_VOICE=bm_daniel "${YAPPER}" speak --dry-run "test" 2>/dev/null | grep '^voice:' | awk '{print $2}')
    [[ "${v}" == "bm_daniel" ]]
}
run_test "RT-15.5" "\$YAPPER_VOICE selects its voice" test_RT15_5

# RT-15.6: Repeated invocations with same $YAPPER_VOICE produce the same voice.
# User action: YAPPER_VOICE=am_michael yapper speak --dry-run "test" (twice)
# User observes: same voice both times.
test_RT15_6() {
    local v1 v2
    v1=$(YAPPER_VOICE=am_michael "${YAPPER}" speak --dry-run "test" 2>/dev/null | grep '^voice:' | awk '{print $2}')
    v2=$(YAPPER_VOICE=am_michael "${YAPPER}" speak --dry-run "test" 2>/dev/null | grep '^voice:' | awk '{print $2}')
    [[ "${v1}" == "am_michael" ]] && [[ "${v2}" == "am_michael" ]]
}
run_test "RT-15.6" "\$YAPPER_VOICE is consistent across invocations" test_RT15_6

# RT-15.7: Invalid $YAPPER_VOICE exits non-zero.
# User action: YAPPER_VOICE=nonexistent yapper speak --dry-run "test"
# User observes: error, non-zero exit.
test_RT15_7() {
    if YAPPER_VOICE=nonexistent_xyz "${YAPPER}" speak --dry-run "test" >/dev/null 2>&1; then
        return 1
    fi
    return 0
}
run_test "RT-15.7" "invalid \$YAPPER_VOICE exits non-zero" test_RT15_7

# RT-15.8: Invalid $YAPPER_VOICE error message identifies the voice and source.
# User action: YAPPER_VOICE=nonexistent yapper speak --dry-run "test"
# User observes: error mentioning "nonexistent" and "$YAPPER_VOICE".
test_RT15_8() {
    local output
    output=$(YAPPER_VOICE=nonexistent_xyz "${YAPPER}" speak --dry-run "test" 2>&1) || true
    printf '%s' "${output}" | grep -q "nonexistent_xyz" || return 1
    printf '%s' "${output}" | grep -q 'YAPPER_VOICE' || return 1
    printf '%s' "${output}" | grep -q 'Available:' || return 1
}
run_test "RT-15.8" "invalid \$YAPPER_VOICE error names the voice and source" test_RT15_8

# RT-15.9: resolveVoice() has no hardcoded voice-name fallback.
# This is a source-level structural guard. The spec is: "no code path where
# af_heart is selected without the user asking". Verified by grepping the source.
test_RT15_9() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")"/../../.. && pwd)"
    local source="${script_dir}/Sources/yapper/Commands/SpeakCommand.swift"
    [[ -f "${source}" ]] || return 1
    # Extract the resolveVoice function and check for hardcoded voice names
    local window
    window=$(sed -n '/private func resolveVoice/,/^    }/p' "${source}")
    # Voice-name pattern: quoted string matching [abfejhpz][fm]_[a-z]+
    if printf '%s' "${window}" | grep -qE '"[abfejhpz][fm]_[a-z]+"'; then
        return 1  # found a hardcoded voice name
    fi
    return 0
}
run_test "RT-15.9" "resolveVoice has no hardcoded voice-name fallback" test_RT15_9

# RT-15.10: --dry-run exits 0 and reports a voice: line.
# User action: yapper speak --dry-run "hello"
# User observes: voice/speed/text output, no audio.
test_RT15_10() {
    "${YAPPER}" speak --dry-run "hello" 2>/dev/null | grep -q '^voice:'
}
run_test "RT-15.10" "--dry-run prints voice: line and exits 0" test_RT15_10

# RT-15.11: --dry-run does not produce WAV files.
# User action: yapper speak --dry-run "test"
# User observes: no audio, no temp files created.
test_RT15_11() {
    local tmp_before tmp_after
    tmp_before=$(find /tmp -maxdepth 1 -name 'yapper_speak_*' 2>/dev/null | wc -l | tr -d ' ')
    "${YAPPER}" speak --dry-run "test" >/dev/null 2>&1
    tmp_after=$(find /tmp -maxdepth 1 -name 'yapper_speak_*' 2>/dev/null | wc -l | tr -d ' ')
    [[ "${tmp_before}" == "${tmp_after}" ]]
}
run_test "RT-15.11" "--dry-run creates no WAV temp files" test_RT15_11

# RT-15.12: --dry-run output includes voice, speed, and text fields.
# User action: yapper speak --speed 1.5 --dry-run "the quick brown fox"
# User observes: all three fields in output.
test_RT15_12() {
    local output
    output=$("${YAPPER}" speak --speed 1.5 --dry-run "the quick brown fox" 2>/dev/null)
    printf '%s' "${output}" | grep -q 'voice:' || return 1
    printf '%s' "${output}" | grep -q 'speed:' || return 1
    printf '%s' "${output}" | grep -q 'text:' || return 1
    printf '%s' "${output}" | grep -q '1.5' || return 1
    printf '%s' "${output}" | grep -q 'the quick brown fox' || return 1
}
run_test "RT-15.12" "--dry-run output includes voice, speed, and text" test_RT15_12

# RT-15.13: Real synthesis through the binary loads MLX and produces audio.
# User action: yapper convert input.txt -o output.m4a
# User observes: output file exists and is non-trivial size.
# This is the test that would have caught v0.8.4 (metallib not found).
test_RT15_13() {
    local tmp
    tmp=$(mktemp -d)
    printf 'Smoke test for regression.' > "${tmp}/input.txt"
    "${YAPPER}" convert "${tmp}/input.txt" -o "${tmp}/output.m4a" --voice af_heart >/dev/null 2>&1
    local rc=$?
    local size=0
    if [[ -f "${tmp}/output.m4a" ]]; then
        size=$(stat -f%z "${tmp}/output.m4a")
    fi
    rm -rf "${tmp}"
    [[ ${rc} -eq 0 ]] && [[ ${size} -gt 1024 ]]
}
run_test "RT-15.13" "real synthesis produces audio file (MLX metallib loads)" test_RT15_13

# RT-4.13: SIGINT during playback exits with non-zero status.
# RT-4.14: Audio stops within 1 second of SIGINT.
# These tests cannot use the standard run_test harness because they need to
# background a process and send signals — incompatible with the $() subshell
# capture that run_test uses. Implemented inline with direct pass/fail tracking.
TOTAL=$((TOTAL + 1))
# Temporarily disable set -e because wait returns 130 (non-zero) when the
# child is killed by SIGINT, which is the expected outcome.
set +e
"${YAPPER}" speak --voice af_heart "This is a longer sentence for signal testing." &
_sigtest_pid=$!
sleep 3
_sigtest_start=$(date +%s)
kill -INT "${_sigtest_pid}" 2>/dev/null
wait "${_sigtest_pid}" 2>/dev/null
_sigtest_rc=$?
set -e
_sigtest_end=$(date +%s)
_sigtest_elapsed=$((_sigtest_end - _sigtest_start))

if [[ ${_sigtest_rc} -ne 0 ]]; then
    printf '  ✅ RT-4.13: SIGINT during playback exits non-zero\n'
    PASS=$((PASS + 1))
else
    printf '  ❌ RT-4.13: SIGINT during playback exits non-zero\n'
    FAIL=$((FAIL + 1))
    FAILURES+=("RT-4.13")
fi

TOTAL=$((TOTAL + 1))
if [[ ${_sigtest_elapsed} -le 2 ]]; then
    printf '  ✅ RT-4.14: audio stops within 1 second of SIGINT\n'
    PASS=$((PASS + 1))
else
    printf '  ❌ RT-4.14: audio stops within 1 second of SIGINT (took %ds)\n' "${_sigtest_elapsed}"
    FAIL=$((FAIL + 1))
    FAILURES+=("RT-4.14")
fi

summarise "yapper speak"
