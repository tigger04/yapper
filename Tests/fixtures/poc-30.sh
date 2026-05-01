#!/usr/bin/env bash
# ABOUTME: POC #30 — run Mode A (script mode) and Mode B (contextual splice) for comparison.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="/tmp/poc-30"
mkdir -p "${OUT}"
FIXTURE="${SCRIPT_DIR}/poc-30.org"

# Config for consistent voice assignment
cat > "${OUT}/script.yaml" <<YAML
auto-assign-voices: false
render-intro: false
render-stage-directions: true
character-voices:
  BOB: bm_daniel
  ALICE: bf_emma
  FOOBAR: am_adam
narrator-voice: af_heart
YAML

printf -- '=== POC #30: Contextual Dialogue Synthesis ===\n\n'

# Mode A: current script mode
printf -- '--- Mode A: yapper convert (script mode) ---\n'
time yapper convert "${FIXTURE}" \
    --script-config "${OUT}/script.yaml" \
    --non-interactive --threads 1 \
    -o "${OUT}/mode_a.m4b" 2>&1

# Extract WAV for comparison
ffmpeg -y -i "${OUT}/mode_a.m4b" -c:a pcm_s16le -ar 24000 "${OUT}/mode_a.wav" -loglevel quiet

printf '\n--- Mode B: contextual splice ---\n'
time yapper context-poc "${FIXTURE}" \
    --script-config "${OUT}/script.yaml" \
    --output-dir "${OUT}" 2>&1

printf '\n=== Compare ===\n'
printf '  %s/mode_a.wav  — current script mode\n' "${OUT}"
printf '  %s/mode_b.wav  — contextual splice\n' "${OUT}"
printf '\nValidate with: transcribe words %s/mode_b.wav\n' "${OUT}"
