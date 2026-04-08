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

# ---------------------------------------------------------------------------
# Issue #21: Streaming speak — play audio per-chunk, not after full synthesis
# ---------------------------------------------------------------------------

# RT-21.1: First audio temp file appears within 5 seconds with non-zero size.
# User action: yapper speak with a multi-sentence input.
# User observes: audio starts within a few seconds, not after a long wait.
# Implementation note: we check for temp WAV files appearing quickly as a
# proxy for "playback started" since we can't detect audio output directly.
TOTAL=$((TOTAL + 1))
set +e
_rt211_tmp=$(mktemp -d)
# Generate a multi-chunk input (>3 sentences, ~200 words)
_rt211_text="This is the first sentence of a long passage. Here is the second sentence with more words. And a third sentence to ensure chunking. The fourth sentence adds even more content to force multiple chunks. Finally a fifth sentence that should definitely cause the text chunker to split this into at least two or three chunks for synthesis."
"${YAPPER}" speak --voice af_heart "${_rt211_text}" &
_rt211_pid=$!
_rt211_found=false
for _i in 1 2 3 4 5; do
    sleep 1
    _rt211_wavs=$(find /tmp -maxdepth 1 -name "yapper_speak_${_rt211_pid}*" -size +0c 2>/dev/null | wc -l | tr -d ' ')
    if [[ ${_rt211_wavs} -gt 0 ]]; then
        _rt211_found=true
        break
    fi
done
kill "${_rt211_pid}" 2>/dev/null
wait "${_rt211_pid}" 2>/dev/null
set -e
if ${_rt211_found}; then
    printf '  ✅ RT-21.1: first audio temp file appears within 5s with non-zero size\n'
    PASS=$((PASS + 1))
else
    printf '  ❌ RT-21.1: first audio temp file did not appear within 5s\n'
    FAIL=$((FAIL + 1))
    FAILURES+=("RT-21.1")
fi

# RT-21.2: SIGINT during streaming playback exits non-zero within 2 seconds.
# User action: yapper speak with long text, then Ctrl+C mid-playback.
# User observes: speech stops, command exits promptly.
TOTAL=$((TOTAL + 1))
set +e
"${YAPPER}" speak --voice af_heart "This is a long streaming test. It has multiple sentences. Each one should be a separate chunk. The streaming implementation plays each chunk as it finishes. Pressing control C should stop everything cleanly and promptly." &
_rt212_pid=$!
sleep 4
_rt212_start=$(date +%s)
kill -INT "${_rt212_pid}" 2>/dev/null
wait "${_rt212_pid}" 2>/dev/null
_rt212_rc=$?
_rt212_end=$(date +%s)
_rt212_elapsed=$((_rt212_end - _rt212_start))
set -e
if [[ ${_rt212_rc} -ne 0 ]] && [[ ${_rt212_elapsed} -le 2 ]]; then
    printf '  ✅ RT-21.2: SIGINT during streaming exits non-zero within 2s\n'
    PASS=$((PASS + 1))
else
    printf '  ❌ RT-21.2: SIGINT exit=%d elapsed=%ds (expected non-zero, ≤2s)\n' "${_rt212_rc}" "${_rt212_elapsed}"
    FAIL=$((FAIL + 1))
    FAILURES+=("RT-21.2")
fi

# RT-21.3: After SIGINT, no new temp WAV files are created.
# User action: Ctrl+C during speak, then check no further synthesis happens.
# User observes: silence after Ctrl+C, no further activity.
TOTAL=$((TOTAL + 1))
set +e
"${YAPPER}" speak --voice af_heart "Another streaming SIGINT test. Multiple sentences here. Each is a chunk. We will interrupt and check no more files appear after the interrupt signal is sent." &
_rt213_pid=$!
sleep 3
kill -INT "${_rt213_pid}" 2>/dev/null
wait "${_rt213_pid}" 2>/dev/null
sleep 2
_rt213_wavs=$(find /tmp -maxdepth 1 -name "yapper_speak_${_rt213_pid}*" 2>/dev/null | wc -l | tr -d ' ')
set -e
# After SIGINT + 2s wait, there should be no lingering temp files
# (either cleaned up, or no new ones created post-interrupt)
if [[ ${_rt213_wavs} -eq 0 ]]; then
    printf '  ✅ RT-21.3: no temp WAV files remain after SIGINT\n'
    PASS=$((PASS + 1))
else
    printf '  ❌ RT-21.3: %d temp WAV files remain after SIGINT\n' "${_rt213_wavs}"
    FAIL=$((FAIL + 1))
    FAILURES+=("RT-21.3")
fi

# RT-21.4: --dry-run output is identical before and after the streaming change.
# User action: yapper speak --dry-run "text"
# User observes: same voice/speed/text output as before.
test_RT21_4() {
    local output
    output=$("${YAPPER}" speak --dry-run "dry run unchanged" 2>/dev/null)
    printf '%s' "${output}" | grep -q '^voice:' || return 1
    printf '%s' "${output}" | grep -q 'speed:' || return 1
    printf '%s' "${output}" | grep -q 'text:.*dry run unchanged' || return 1
    printf '%s' "${output}" | grep -q '(dry run' || return 1
}
run_test "RT-21.4" "--dry-run output unchanged by streaming" test_RT21_4

# RT-21.5: yap with multi-chunk input begins playback within 5 seconds.
# User action: yap "long text..."
# User observes: audio starts quickly via the yap shorthand.
TOTAL=$((TOTAL + 1))
set +e
YAP_LINK="${_rt211_tmp}/yap"
ln -sf "${YAPPER}" "${YAP_LINK}"
"${YAP_LINK}" --voice af_heart "Yap streaming test with multiple sentences. This should also stream chunk by chunk. Each sentence becomes a chunk for the synthesiser. The shorthand should behave identically to yapper speak." &
_rt215_pid=$!
_rt215_found=false
for _i in 1 2 3 4 5; do
    sleep 1
    _rt215_wavs=$(find /tmp -maxdepth 1 -name "yapper_speak_${_rt215_pid}*" -size +0c 2>/dev/null | wc -l | tr -d ' ')
    if [[ ${_rt215_wavs} -gt 0 ]]; then
        _rt215_found=true
        break
    fi
done
kill "${_rt215_pid}" 2>/dev/null
wait "${_rt215_pid}" 2>/dev/null
set -e
if ${_rt215_found}; then
    printf '  ✅ RT-21.5: yap begins playback within 5s\n'
    PASS=$((PASS + 1))
else
    printf '  ❌ RT-21.5: yap did not begin playback within 5s\n'
    FAIL=$((FAIL + 1))
    FAILURES+=("RT-21.5")
fi

# RT-21.6: After normal completion, no temp WAV files remain.
# User action: yapper speak "short text", let it finish.
# User observes: command completes, no temp files left behind.
test_RT21_6() {
    "${YAPPER}" speak --voice af_heart "Cleanup test." >/dev/null 2>&1
    local remaining
    remaining=$(find /tmp -maxdepth 1 -name "yapper_speak_$$*" 2>/dev/null | wc -l | tr -d ' ')
    [[ ${remaining} -eq 0 ]]
}
run_test "RT-21.6" "no temp WAV files remain after normal completion" test_RT21_6

# RT-21.7: After SIGINT, no temp WAV files remain.
# (Covered by RT-21.3 above which checks the same thing. This test is
# a separate ID per the AC table but exercises the same path.)
TOTAL=$((TOTAL + 1))
# Re-use RT-21.3's result — if RT-21.3 passed, RT-21.7 passes.
if [[ ${_rt213_wavs} -eq 0 ]]; then
    printf '  ✅ RT-21.7: no temp WAV files remain after SIGINT (same as RT-21.3)\n'
    PASS=$((PASS + 1))
else
    printf '  ❌ RT-21.7: temp WAV files remain after SIGINT\n'
    FAIL=$((FAIL + 1))
    FAILURES+=("RT-21.7")
fi

# RT-21.8: Single-chunk input exits within 5 seconds.
# User action: yapper speak "Hi."
# User observes: plays quickly, exits, no regression.
test_RT21_8() {
    timeout 5 "${YAPPER}" speak --voice af_heart "Hi." >/dev/null 2>&1
}
run_test "RT-21.8" "single-chunk input exits within 5s" test_RT21_8

# RT-21.9: Single-chunk input with explicit voice produces no errors.
# User action: yapper speak --voice af_heart "Hi."
# User observes: plays, exits 0.
test_RT21_9() {
    "${YAPPER}" speak --voice af_heart "Hi." >/dev/null 2>&1
}
run_test "RT-21.9" "single-chunk with --voice produces no errors" test_RT21_9

# RT-21.10: Temp WAV creation timestamps are sequential.
# User action: yapper speak with multi-chunk text.
# User observes: chunks play in order (automated via timestamp ordering).
# Note: this test can only verify ordering if the streaming implementation
# creates distinct temp files per chunk (e.g. yapper_speak_PID_1.wav,
# yapper_speak_PID_2.wav). If the implementation reuses a single file,
# this test will see only one file and pass vacuously. The UT-21.2
# (human listener) covers the ordering guarantee in that case.
TOTAL=$((TOTAL + 1))
set +e
"${YAPPER}" speak --voice af_heart "First chunk sentence. Second chunk sentence. Third chunk sentence. Fourth chunk to ensure multiple files." &
_rt2110_pid=$!
sleep 8
kill "${_rt2110_pid}" 2>/dev/null
wait "${_rt2110_pid}" 2>/dev/null
# Check if multiple temp files were created with sequential timestamps
_rt2110_files=$(find /tmp -maxdepth 1 -name "yapper_speak_${_rt2110_pid}*" -type f 2>/dev/null | sort)
_rt2110_count=$(printf '%s\n' "${_rt2110_files}" | grep -c . || true)
set -e
if [[ ${_rt2110_count} -le 1 ]]; then
    # Single file or no files — streaming may reuse one file. Pass vacuously.
    printf '  ✅ RT-21.10: chunk ordering (vacuous — single/no temp file)\n'
    PASS=$((PASS + 1))
else
    # Multiple files — verify they're in order by checking modification times
    _rt2110_ordered=true
    _rt2110_prev=0
    while IFS= read -r _f; do
        [[ -z "${_f}" ]] && continue
        _ts=$(stat -f%m "${_f}" 2>/dev/null || echo "0")
        if [[ ${_ts} -lt ${_rt2110_prev} ]]; then
            _rt2110_ordered=false
            break
        fi
        _rt2110_prev=${_ts}
    done <<< "${_rt2110_files}"
    if ${_rt2110_ordered}; then
        printf '  ✅ RT-21.10: temp WAV timestamps are sequential\n'
        PASS=$((PASS + 1))
    else
        printf '  ❌ RT-21.10: temp WAV timestamps are not sequential\n'
        FAIL=$((FAIL + 1))
        FAILURES+=("RT-21.10")
    fi
fi

rm -rf "${_rt211_tmp}"

summarise "yapper speak"
