#!/usr/bin/env bash
# Tests scripts/rollback-check.sh against a throwaway git repo.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
repo=$(mktemp -d); trap 'rm -rf "$repo"' EXIT
g() { git -C "$repo" "$@"; }
g init -q -b main && g config user.email t@example.invalid && g config user.name test
mkdir -p "$repo/deploy/releases"
echo a > "$repo/README"; g add -A; g commit -qm init; A=$(g rev-parse HEAD)
echo "digest: 1" > "$repo/deploy/releases/kind.yaml"; g add -A; g commit -qm "chore(release): kind 1"; B=$(g rev-parse HEAD)
echo b >> "$repo/README"; echo "digest: 2" > "$repo/deploy/releases/kind.yaml"; g add -A; g commit -qm mixed; C=$(g rev-parse HEAD)
check() { (cd "$repo" && "$ROOT/scripts/rollback-check.sh" "$@") >/dev/null 2>&1; }
check "$B" kind || fail "digest-only bump must be accepted"
if check "$C" kind; then fail "commit touching other files accepted"; fi
if check "$A" kind; then fail "commit without deploy/releases/kind.yaml accepted"; fi
if check "$B" prod; then fail "env prod accepted in platform v1"; fi
if check deadbeef kind; then fail "unknown sha accepted"; fi
if check 'B;rm' kind; then fail "non-hex sha accepted"; fi
# a digest-only commit that is not on main (side branch) must be rejected
g checkout -q -b side "$B"; echo "digest: 9" > "$repo/deploy/releases/kind.yaml"; g add -A; g commit -qm "chore(release): kind 9"; S=$(g rev-parse HEAD); g checkout -q main
if check "$S" kind; then fail "commit not on main accepted"; fi
echo "ok   rollback-check"
