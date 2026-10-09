#!/usr/bin/env bash
# Tests scripts/release-bump.sh (bg-release-bot): file format from spec "Thiết kế", core-worker shares the core image.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
sha=0123456789abcdef0123456789abcdef01234567
mkdir "$TMP/d"; i=0
for img in core public-api admin-api mocks web-customer web-admin; do i=$((i + 1)); printf 'sha256:%064d\n' "$i" > "$TMP/d/$img"; done

scripts/release-bump.sh kind "$sha" acme "$TMP/d" "$TMP/kind.yaml"
[[ $(yq '.release' "$TMP/kind.yaml") == sha-0123456 ]] || fail "release"
[[ $(yq '.gitSha' "$TMP/kind.yaml") == "$sha" ]] || fail "gitSha"
[[ $(yq 'keys | length' "$TMP/kind.yaml") == 12 ]] || fail "want release + gitSha + 10 deployables"
[[ $(yq '."public-api".image' "$TMP/kind.yaml") == ghcr.io/acme/banking-go/public-api ]] || fail "public-api image"
[[ $(yq '."core-worker".image' "$TMP/kind.yaml") == ghcr.io/acme/banking-go/core ]] || fail "core-worker must use the core image"
[[ $(yq '."core-worker".digest' "$TMP/kind.yaml") == "$(cat "$TMP/d/core")" ]] || fail "core-worker digest = core digest"
[[ $(yq '."mock-otp".image' "$TMP/kind.yaml") == ghcr.io/acme/banking-go/mocks ]] || fail "mock-otp image"
[[ $(yq '."web-admin".digest' "$TMP/kind.yaml") == "$(cat "$TMP/d/web-admin")" ]] || fail "web-admin digest"

echo keep > "$TMP/out.yaml"; rm "$TMP/d/web-admin"
if scripts/release-bump.sh kind "$sha" acme "$TMP/d" "$TMP/out.yaml" 2>/dev/null; then fail "missing digest accepted"; fi
[[ $(cat "$TMP/out.yaml") == keep ]] || fail "output overwritten on error"
if scripts/release-bump.sh kind "$sha" Acme "$TMP/d" "$TMP/out.yaml" 2>/dev/null; then fail "uppercase owner accepted"; fi
if scripts/release-bump.sh kind abc acme "$TMP/d" "$TMP/out.yaml" 2>/dev/null; then fail "short sha accepted"; fi
echo "ok   release-bump"
