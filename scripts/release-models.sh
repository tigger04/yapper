#!/usr/bin/env bash
# ABOUTME: Packages Kokoro model weights and English voices and uploads them to the models-v1 release.
# ABOUTME: Prints SHA256 values for the formula update step.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
STAGING_DIR="${TMPDIR:-/tmp}/yapper-release-models"
RELEASE_TAG="models-v1"

DATA_ROOT="${HOME}/.local/share/yapper"
MODEL_SRC="${DATA_ROOT}/models/kokoro-v1_0.safetensors"
VOICES_SRC="${DATA_ROOT}/voices"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is required. Install with: brew install gh"
command -v tar >/dev/null 2>&1 || die "tar is required."
command -v shasum >/dev/null 2>&1 || die "shasum is required."

# 1. Verify source files exist
[[ -f "${MODEL_SRC}" ]] || die "Model weights not found at ${MODEL_SRC}"
[[ -d "${VOICES_SRC}" ]] || die "Voices directory not found at ${VOICES_SRC}"

# 2. Filter English voices (a*, b*)
english_voices=()
while IFS= read -r -d '' voice; do
    english_voices+=("$(basename "${voice}")")
done < <(find "${VOICES_SRC}" -maxdepth 1 -type f \( -name 'a[fm]_*.safetensors' -o -name 'b[fm]_*.safetensors' \) -print0 | sort -z)

[[ ${#english_voices[@]} -gt 0 ]] || die "No English voices found in ${VOICES_SRC}"

printf 'Including %d English voice(s):\n' "${#english_voices[@]}"
for v in "${english_voices[@]}"; do
    printf '  %s\n' "${v}"
done

# 3. Stage files
mkdir -p "${STAGING_DIR}"
trap 'rm -rf -- "${STAGING_DIR}"' EXIT

printf '\nStaging model safetensors...\n'
cp -- "${MODEL_SRC}" "${STAGING_DIR}/kokoro-v1_0.safetensors"

printf 'Building voices.tar.gz...\n'
(cd "${VOICES_SRC}" && tar -czf "${STAGING_DIR}/voices.tar.gz" "${english_voices[@]}")

# 4. Compute SHA256 values
printf '\nComputing SHA256:\n'
model_sha=$(shasum -a 256 "${STAGING_DIR}/kokoro-v1_0.safetensors" | awk '{print $1}')
voices_sha=$(shasum -a 256 "${STAGING_DIR}/voices.tar.gz" | awk '{print $1}')
printf '  kokoro-v1_0.safetensors  %s\n' "${model_sha}"
printf '  voices.tar.gz            %s\n' "${voices_sha}"

# 5. Write manifest for downstream release.sh consumption
MANIFEST="${PROJECT_ROOT}/models/manifest.json"
mkdir -p "$(dirname "${MANIFEST}")"
cat > "${MANIFEST}" <<JSON
{
  "release_tag": "${RELEASE_TAG}",
  "model": {
    "filename": "kokoro-v1_0.safetensors",
    "url": "https://github.com/tigger04/yapper/releases/download/${RELEASE_TAG}/kokoro-v1_0.safetensors",
    "sha256": "${model_sha}"
  },
  "voices": {
    "filename": "voices.tar.gz",
    "url": "https://github.com/tigger04/yapper/releases/download/${RELEASE_TAG}/voices.tar.gz",
    "sha256": "${voices_sha}",
    "count": ${#english_voices[@]}
  }
}
JSON
printf '\nWrote %s\n' "${MANIFEST}"

# 6. Create or update the release
if gh release view "${RELEASE_TAG}" >/dev/null 2>&1; then
    printf '\nUploading to existing release %s...\n' "${RELEASE_TAG}"
    gh release upload "${RELEASE_TAG}" \
        "${STAGING_DIR}/kokoro-v1_0.safetensors" \
        "${STAGING_DIR}/voices.tar.gz" \
        --clobber
else
    printf '\nCreating release %s...\n' "${RELEASE_TAG}"
    gh release create "${RELEASE_TAG}" \
        "${STAGING_DIR}/kokoro-v1_0.safetensors" \
        "${STAGING_DIR}/voices.tar.gz" \
        --title "Yapper model assets (${RELEASE_TAG})" \
        --notes "Kokoro-82M model weights and English voice embeddings for yapper. Redistributed under Apache 2.0 from hexgrad/Kokoro-82M." \
        --prerelease
fi

# 7. Commit manifest if changed
if git -C "${PROJECT_ROOT}" diff --quiet -- "${MANIFEST}"; then
    :
else
    git -C "${PROJECT_ROOT}" add "${MANIFEST}"
    git -C "${PROJECT_ROOT}" commit -m "chore: update model manifest SHA256 hashes for ${RELEASE_TAG}"
fi

printf '\n--- Release Summary ---\n'
printf '  Tag:           %s\n' "${RELEASE_TAG}"
printf '  Model SHA256:  %s\n' "${model_sha}"
printf '  Voices SHA256: %s\n' "${voices_sha}"
printf '  Voice count:   %d\n' "${#english_voices[@]}"
printf 'Done.\n'
