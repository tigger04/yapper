#!/usr/bin/env bash
# ABOUTME: Builds a release binary, tags a GitHub release, and updates the Homebrew formula.
# ABOUTME: Ships an ad-hoc signed prebuilt binary; formula never invokes xcodebuild or swift build.

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_FILE="${PROJECT_ROOT}/Sources/YapperKit/Version.swift"
FORMULA_LOCAL="${PROJECT_ROOT}/Formula/yapper.rb"
MANIFEST="${PROJECT_ROOT}/models/manifest.json"
TAP_REPO="tigger04/homebrew-tap"
FORMULA_TAP_PATH="Formula/yapper.rb"
SCHEME="yapper"
BUNDLE_NAMES=(
    "mlx-swift_Cmlx.bundle"
    "MisakiSwift_MisakiSwift.bundle"
    "ZIPFoundation_ZIPFoundation.bundle"
)

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

command -v gh >/dev/null 2>&1 || die "gh (GitHub CLI) is required."
command -v python3 >/dev/null 2>&1 || die "python3 is required."
command -v xcodebuild >/dev/null 2>&1 || die "xcodebuild is required."
command -v codesign >/dev/null 2>&1 || die "codesign is required."

get_current_version() {
    grep -oE 'let version = "[0-9]+\.[0-9]+\.[0-9]+"' "${VERSION_FILE}" \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
}

bump_version() {
    local current="$1"
    local major minor patch
    IFS='.' read -r major minor patch <<< "${current}"
    patch=$((patch + 1))
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
BINARY_ASSET="yapper-macos-arm64.tar.gz"

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

# 2. Build release binary with xcodebuild (outside Homebrew sandbox — this is the point)
printf '\nBuilding release binary with xcodebuild...\n'
build_dir=$(mktemp -d)
trap 'rm -rf -- "${build_dir}"' EXIT

(cd "${PROJECT_ROOT}" && xcodebuild build \
    -scheme "${SCHEME}" \
    -destination 'platform=OS X' \
    -configuration Release \
    -derivedDataPath "${build_dir}/DerivedData" \
    -quiet) || die "xcodebuild failed"

RELEASE_DIR="${build_dir}/DerivedData/Build/Products/Release"
[[ -f "${RELEASE_DIR}/yapper" ]] || die "Built binary not found at ${RELEASE_DIR}/yapper"

# Verify binary runs and reports the expected version
printf 'Verifying built binary...\n'
BINARY_VERSION=$("${RELEASE_DIR}/yapper" --version 2>&1 || true)
[[ "${BINARY_VERSION}" == "${NEW_VERSION}" ]] || die "Binary version mismatch: got '${BINARY_VERSION}', expected '${NEW_VERSION}'"
printf '  binary --version: %s\n' "${BINARY_VERSION}"

# Verify all expected bundles exist
for bundle in "${BUNDLE_NAMES[@]}"; do
    [[ -d "${RELEASE_DIR}/${bundle}" ]] || die "Expected resource bundle missing: ${bundle}"
done

# 3. Ad-hoc code sign the binary with hardened runtime
printf '\nAd-hoc signing binary (hardened runtime)...\n'
codesign --force --sign - --options runtime --timestamp=none "${RELEASE_DIR}/yapper"
codesign --verify --verbose "${RELEASE_DIR}/yapper" 2>&1 | sed 's/^/  /'

# 4. Stage binary + bundles and tar
staging="${build_dir}/stage"
mkdir -p "${staging}"
cp -- "${RELEASE_DIR}/yapper" "${staging}/"
for bundle in "${BUNDLE_NAMES[@]}"; do
    cp -R -- "${RELEASE_DIR}/${bundle}" "${staging}/"
done

printf '\nCreating %s...\n' "${BINARY_ASSET}"
binary_tarball="${build_dir}/${BINARY_ASSET}"
(cd "${staging}" && tar -czf "${binary_tarball}" yapper "${BUNDLE_NAMES[@]}")
BINARY_SHA256=$(shasum -a 256 "${binary_tarball}" | awk '{print $1}')
printf '  %s SHA256: %s\n' "${BINARY_ASSET}" "${BINARY_SHA256}"

# 5. Commit, tag, push
git -C "${PROJECT_ROOT}" add "${VERSION_FILE}"
git -C "${PROJECT_ROOT}" commit -m "chore: bump version to ${NEW_VERSION}"
git -C "${PROJECT_ROOT}" tag -a "${TAG}" -m "Release ${NEW_VERSION}"

printf 'Pushing to origin...\n'
git -C "${PROJECT_ROOT}" push
git -C "${PROJECT_ROOT}" push origin "${TAG}"

# 6. Create GitHub release with the binary tarball
BINARY_URL="https://github.com/tigger04/yapper/releases/download/${TAG}/${BINARY_ASSET}"
printf 'Creating GitHub release %s...\n' "${TAG}"
gh release create "${TAG}" \
    "${binary_tarball}" \
    --repo tigger04/yapper \
    --title "Yapper ${NEW_VERSION}" \
    --notes "Yapper ${NEW_VERSION} — prebuilt macOS arm64 binary.

Install via Homebrew:
\`\`\`
brew tap tigger04/tap
brew install yapper
\`\`\`

The tarball contains the ad-hoc signed \`yapper\` binary and its required Swift resource bundles. See \`scripts/release.sh\` for how it was built and packaged."

# 7. Load model/voices SHA256 from manifest
MODEL_URL=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['model']['url'])")
MODEL_SHA=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['model']['sha256'])")
VOICES_URL=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['voices']['url'])")
VOICES_SHA=$(python3 -c "import json; print(json.load(open('${MANIFEST}'))['voices']['sha256'])")

# 8. Write formula (prebuilt binary, no build step)
mkdir -p "${PROJECT_ROOT}/Formula"
cat > "${FORMULA_LOCAL}" <<RUBY
class Yapper < Formula
  desc "Fast, Apple Silicon-native text-to-speech CLI and Swift library"
  homepage "https://github.com/tigger04/yapper"
  url "${BINARY_URL}"
  sha256 "${BINARY_SHA256}"
  license "Apache-2.0"
  version "${NEW_VERSION}"

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
    # Prebuilt ad-hoc signed binary and its Swift resource bundles go into libexec;
    # a thin wrapper script in bin/ execs the real binary so Bundle.main lookups
    # resolve relative to libexec (where the .bundle directories live).
    libexec.install "yapper"
    libexec.install Dir["*.bundle"]

    (bin/"yapper").write <<~SH
      #!/bin/bash
      exec "#{libexec}/yapper" "\$@"
    SH
    (bin/"yapper").chmod 0755

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
      Yapper ships as a prebuilt Apple Silicon binary, ad-hoc code signed
      (not yet notarised — tracked in issue #13).

      Model weights and English voices are downloaded automatically at install
      time from the tigger04/yapper models-v1 release (Apache 2.0, redistributed
      from hexgrad/Kokoro-82M). They live in:
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

# 9. Mirror formula to the tap repo
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
printf '  Binary:  %s (%s)\n' "${BINARY_ASSET}" "${BINARY_SHA256:0:16}..."
printf '  Formula: %s/%s\n\n' "${TAP_REPO}" "${FORMULA_TAP_PATH}"
printf 'Install with:\n  brew tap tigger04/tap\n  brew install yapper\n'
