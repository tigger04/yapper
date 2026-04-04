#!/usr/bin/env bash
# ABOUTME: Creates a tagged GitHub release for yapper and updates the Homebrew formula.
# ABOUTME: Bumps version, tags, pushes, and mirrors Formula/yapper.rb to tigger04/homebrew-tap.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${PROJECT_ROOT}/Sources/YapperKit/Version.swift"
FORMULA_LOCAL="${PROJECT_ROOT}/Formula/yapper.rb"
MANIFEST="${PROJECT_ROOT}/models/manifest.json"
TAP_REPO="tigger04/homebrew-tap"
FORMULA_TAP_PATH="Formula/yapper.rb"

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is required."
command -v python3 >/dev/null 2>&1 || die "python3 is required."

get_current_version() {
    grep -oE 'let version = "[0-9]+\.[0-9]+\.[0-9]+"' "${VERSION_FILE}" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
}

bump_version() {
    local current="$1"
    local major minor patch
    IFS='.' read -r major minor patch <<< "${current}"
    minor=$((minor + 1))
    patch=0
    printf '%s.%s.%s' "${major}" "${minor}" "${patch}"
}

CURRENT_VERSION=$(get_current_version)
[[ -n "${CURRENT_VERSION}" ]] || die "Could not parse current version from ${VERSION_FILE}"

if [[ $# -gt 0 && -n "${1:-}" ]]; then
    NEW_VERSION="$1"
else
    NEW_VERSION=$(bump_version "${CURRENT_VERSION}")
fi

TAG="v${NEW_VERSION}"

printf '=== Yapper Release ===\n'
printf '  Current version: %s\n' "${CURRENT_VERSION}"
printf '  New version:     %s\n' "${NEW_VERSION}"
printf '  Tag:             %s\n\n' "${TAG}"

# Sanity checks
git -C "${PROJECT_ROOT}" diff --quiet || die "Working tree has uncommitted changes. Commit or stash first."
git -C "${PROJECT_ROOT}" diff --cached --quiet || die "Index has staged changes. Commit or reset first."
if git -C "${PROJECT_ROOT}" rev-parse "${TAG}" >/dev/null 2>&1; then
    die "Tag ${TAG} already exists."
fi
[[ -f "${MANIFEST}" ]] || die "models/manifest.json not found. Run 'make release-models' first."

# 1. Update version in source
printf 'Updating version in %s...\n' "${VERSION_FILE}"
tmpfile=$(mktemp)
sed "s/let version = \"${CURRENT_VERSION}\"/let version = \"${NEW_VERSION}\"/" "${VERSION_FILE}" > "${tmpfile}"
mv "${tmpfile}" "${VERSION_FILE}"

verify_version=$(get_current_version)
[[ "${verify_version}" == "${NEW_VERSION}" ]] || die "Version bump failed (got ${verify_version})"

# 2. Commit, tag, push
git -C "${PROJECT_ROOT}" add "${VERSION_FILE}"
git -C "${PROJECT_ROOT}" commit -m "chore: bump version to ${NEW_VERSION}"
git -C "${PROJECT_ROOT}" tag -a "${TAG}" -m "Release ${NEW_VERSION}"

printf 'Pushing to origin...\n'
git -C "${PROJECT_ROOT}" push
git -C "${PROJECT_ROOT}" push origin "${TAG}"

# 3. Create GitHub release for the code tag
printf 'Creating GitHub release %s...\n' "${TAG}"
gh release create "${TAG}" \
    --repo tigger04/yapper \
    --title "Yapper ${NEW_VERSION}" \
    --notes "Yapper ${NEW_VERSION} — see CHANGELOG or git log for details.

Install via Homebrew:
\`\`\`
brew tap tigger04/tap
brew install yapper
\`\`\`"

# 4. Compute SHA256 of source tarball
TARBALL_URL="https://github.com/tigger04/yapper/archive/refs/tags/${TAG}.tar.gz"
tmp_release=$(mktemp -d)
trap 'rm -rf -- "${tmp_release}"' EXIT

printf 'Downloading source tarball...\n'
curl -sL "${TARBALL_URL}" -o "${tmp_release}/source.tar.gz"
SOURCE_SHA256=$(shasum -a 256 "${tmp_release}/source.tar.gz" | awk '{print $1}')
printf '  source SHA256: %s\n' "${SOURCE_SHA256}"

# 5. Load model/voices SHA256 from manifest
MODEL_URL=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['model']['url'])")
MODEL_SHA=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['model']['sha256'])")
VOICES_URL=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['voices']['url'])")
VOICES_SHA=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['voices']['sha256'])")

# 6. Write formula
mkdir -p "${PROJECT_ROOT}/Formula"
cat > "${FORMULA_LOCAL}" <<RUBY
class Yapper < Formula
  desc "Fast, Apple Silicon-native text-to-speech CLI and Swift library"
  homepage "https://github.com/tigger04/yapper"
  url "${TARBALL_URL}"
  sha256 "${SOURCE_SHA256}"
  license "Apache-2.0"

  depends_on :macos
  depends_on arch: :arm64
  depends_on "ffmpeg"

  resource "model" do
    url "${MODEL_URL}"
    sha256 "${MODEL_SHA}"
  end

  resource "voices" do
    url "${VOICES_URL}"
    sha256 "${VOICES_SHA}"
  end

  def install
    # Pre-resolve Swift package dependencies with Swift's sandbox disabled,
    # so the resolver can run inside Homebrew's outer sandbox. Without this,
    # xcodebuild's internal package resolver triggers
    #   sandbox-exec: sandbox_apply: Operation not permitted
    system "swift", "package", "resolve", "--disable-sandbox"

    system "xcodebuild", "build",
           "-scheme", "yapper",
           "-destination", "platform=OS X",
           "-configuration", "Release",
           "-derivedDataPath", buildpath/".xcode",
           "-skipPackagePluginValidation",
           "-disableAutomaticPackageResolution"

    built = Dir["#{buildpath}/.xcode/Build/Products/Release/yapper"].first
    odie "yapper binary not found after build" unless built
    bin.install built

    (share/"yapper/models").mkpath
    (share/"yapper/voices").mkpath

    resource("model").stage do
      (share/"yapper/models").install "kokoro-v1_0.safetensors"
    end

    resource("voices").stage do
      (share/"yapper/voices").install Dir["*.safetensors"]
    end
  end

  def caveats
    <<~EOS
      Yapper builds from source and requires:
        - Xcode command-line tools (for xcodebuild)
        - The Metal Toolchain component of Xcode (for MLX shader compilation)

      Model weights and English voices are downloaded automatically at install time
      from the tigger04/yapper models-v1 release (Apache 2.0, redistributed from
      hexgrad/Kokoro-82M). They live in:
        #{share}/yapper/models
        #{share}/yapper/voices

      Try it:
        yapper speak "Hello, world"
        yapper voices
    EOS
  end

  test do
    assert_match "${NEW_VERSION}", shell_output("#{bin}/yapper --version")
  end
end
RUBY

printf 'Wrote %s\n' "${FORMULA_LOCAL}"

git -C "${PROJECT_ROOT}" add "${FORMULA_LOCAL}"
git -C "${PROJECT_ROOT}" commit -m "chore: update Homebrew formula for ${NEW_VERSION}"
git -C "${PROJECT_ROOT}" push

# 7. Mirror formula to the tap repo
printf 'Pushing formula to %s...\n' "${TAP_REPO}"
b64_file=$(mktemp)
payload_file=$(mktemp)
base64 < "${FORMULA_LOCAL}" | tr -d '\n' > "${b64_file}"

existing_sha=""
if gh api "repos/${TAP_REPO}/contents/${FORMULA_TAP_PATH}" >/dev/null 2>&1; then
    existing_sha=$(gh api "repos/${TAP_REPO}/contents/${FORMULA_TAP_PATH}" --jq '.sha')
fi

python3 - "${b64_file}" "${payload_file}" "${NEW_VERSION}" "${existing_sha}" <<'PY'
import json, sys
b64_path, payload_path, version, sha = sys.argv[1:5]
with open(b64_path) as fh:
    content = fh.read().strip()
payload = {"message": f"Update yapper to {version}", "content": content}
if sha:
    payload["sha"] = sha
with open(payload_path, "w") as fh:
    json.dump(payload, fh)
PY

gh api "repos/${TAP_REPO}/contents/${FORMULA_TAP_PATH}" \
    --method PUT --input "${payload_file}" >/dev/null

rm -f -- "${b64_file}" "${payload_file}"

printf '\n=== Release Complete ===\n'
printf '  Version: %s\n' "${NEW_VERSION}"
printf '  Tag:     %s\n' "${TAG}"
printf '  Release: https://github.com/tigger04/yapper/releases/tag/%s\n' "${TAG}"
printf '  Formula: %s/%s\n\n' "${TAP_REPO}" "${FORMULA_TAP_PATH}"
printf 'Install with:\n  brew tap tigger04/tap\n  brew install yapper\n'
