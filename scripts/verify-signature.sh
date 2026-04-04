#!/usr/bin/env bash
# ABOUTME: Verifies a yapper release binary is Developer ID signed, hardened, timestamped, and notarised.
# ABOUTME: Used as a pre-upload gate in release.sh and as a standalone post-release sanity check.

set -euo pipefail
IFS=$'\n\t'

usage() {
    cat >&2 <<EOF
Usage: ${0##*/} <path-to-directory-containing-yapper>

Expects a directory containing:
  - yapper                          (the Mach-O binary, Developer ID signed)
  - mlx-swift_Cmlx.bundle           (signed)
  - MisakiSwift_MisakiSwift.bundle  (signed)
  - ZIPFoundation_ZIPFoundation.bundle (signed)

Verifies:
  1. Main binary codesign envelope is valid (--verify --deep --strict)
  2. Main binary authority is a Developer ID Application identity
  3. Main binary has a secure timestamp
  4. Main binary was signed with hardened runtime
  5. Each .bundle has its own _CodeSignature/ (inside-out signing)

Notarisation acceptance is verified separately by release.sh at submission time
via notarytool's 'status: Accepted' response — spctl --assess does not recognise
bare Mach-O binaries (it reports 'does not seem to be an app'), and stapling does
not apply to bare Mach-O, so local post-hoc notarisation verification is not
feasible. Trust chain for end users: the signature alone (Developer ID + hardened
runtime + timestamp) is what Apple's online Gatekeeper check validates against
its notary database at first launch.

Exits 0 on all checks passing, non-zero with diagnostic output on any failure.
EOF
}

die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
ok()  { printf '  ✓ %s\n' "$*"; }

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

target_dir="$1"
[[ -d "${target_dir}" ]] || die "not a directory: ${target_dir}"

binary="${target_dir}/yapper"
[[ -f "${binary}" ]] || die "yapper binary not found at ${binary}"

expected_bundles=(
    "mlx-swift_Cmlx.bundle"
    "MisakiSwift_MisakiSwift.bundle"
    "ZIPFoundation_ZIPFoundation.bundle"
)

printf 'Verifying %s\n' "${target_dir}"

# 1. codesign envelope
codesign --verify --deep --strict --verbose=4 "${binary}" 2>&1 \
    | sed 's/^/    /' \
    || die "codesign --verify failed on ${binary}"
ok "codesign envelope valid"

# 2+3+4. Inspect authority, timestamp, hardened runtime
display_output=$(codesign --display --verbose=4 "${binary}" 2>&1)

if ! printf '%s\n' "${display_output}" | grep -q '^Authority=Developer ID Application:'; then
    printf '%s\n' "${display_output}" | sed 's/^/    /' >&2
    die "binary is not signed with a Developer ID Application authority"
fi
ok "authority is Developer ID Application"

if ! printf '%s\n' "${display_output}" | grep -q '^Timestamp='; then
    printf '%s\n' "${display_output}" | sed 's/^/    /' >&2
    die "binary is missing the secure timestamp (required for notarisation)"
fi
ok "secure timestamp present"

# Hardened runtime appears in "CodeDirectory ... flags=0x10000(runtime)" — the 'runtime' token
if ! printf '%s\n' "${display_output}" | grep -Eq 'flags=0x[0-9a-f]+\([^)]*runtime'; then
    printf '%s\n' "${display_output}" | sed 's/^/    /' >&2
    die "binary is missing hardened runtime flag"
fi
ok "hardened runtime enabled"

# 5. Each resource bundle must be independently code-signed (inside-out)
for bundle in "${expected_bundles[@]}"; do
    bundle_path="${target_dir}/${bundle}"
    [[ -d "${bundle_path}" ]] || die "expected bundle missing: ${bundle}"
    if [[ ! -d "${bundle_path}/Contents/_CodeSignature" ]]; then
        die "bundle not code-signed (no _CodeSignature/): ${bundle}"
    fi
    codesign --verify --verbose=4 "${bundle_path}" >/dev/null 2>&1 \
        || die "codesign --verify failed on ${bundle}"
    ok "${bundle} signed (inside-out)"
done

printf 'All checks passed.\n'
