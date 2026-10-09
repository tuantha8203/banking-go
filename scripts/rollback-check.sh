#!/usr/bin/env bash
# rollback.yml guard (deployment.md § Rollback → App, D-22): <sha> must be on the current branch and change only
# deploy/releases/<env>.yaml, so bg-release-bot may push its revert directly. Config rollbacks go through a PR (v2+).
#   scripts/rollback-check.sh <sha> <env>
set -euo pipefail
die() { echo "rollback-check: $*" >&2; exit 1; }
sha=${1:-}; env=${2:-}
[[ $env == kind ]] || die "env '$env' is not supported in platform v1 (kind only)"
[[ $sha =~ ^[0-9a-f]{7,40}$ ]] || die "revert_sha must be a hex commit sha"
git cat-file -e "$sha^{commit}" 2>/dev/null || die "unknown commit $sha"
git merge-base --is-ancestor "$sha" HEAD || die "$sha is not on this branch"
files=$(git diff-tree --no-commit-id --name-only -r "$sha")
[[ $files == "deploy/releases/$env.yaml" ]] || die "$sha must change only deploy/releases/$env.yaml, changes: $(echo $files)"
echo "ok: $sha only changes deploy/releases/$env.yaml"
