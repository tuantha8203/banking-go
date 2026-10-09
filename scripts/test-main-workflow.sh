#!/usr/bin/env bash
# Contract test for .github/workflows/main.yml (platform v1 T19; spec §4, deployment.md § Pipeline, D-19, D-22, D-38):
# release runs only from main, CI first, Trivy gate, push + keyless sign/attest by digest, and only bg-release-bot
# writes deploy/releases/kind.yaml. Also: ci.yml no longer triggers on push (main.yml calls it) and runs scripts-test.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }
M=.github/workflows/main.yml
CI=.github/workflows/ci.yml
[[ -f $M ]] || fail "$M missing"

# 1. triggers, permissions, concurrency
[[ $(yq '[.on | keys | .[] | select(. != "push" and . != "workflow_dispatch")] | length' "$M") == 0 ]] \
  || fail "$M may only trigger on push/workflow_dispatch (D-38): $(yq -o=json -I=0 '.on | keys' "$M")"
[[ $(yq -o=json -I=0 '.on.push.branches' "$M") == '["main"]' ]] || fail "$M must run on push to main only"
[[ $(yq '.on.push["paths-ignore"] | contains(["deploy/releases/**"])' "$M") == true ]] || fail "bot bumps must not retrigger (paths-ignore deploy/releases/**)"
[[ $(yq '.permissions.contents' "$M") == read && $(yq '.permissions | length' "$M") == 1 ]] || fail "top-level permissions must be contents: read only"
[[ $(yq '.concurrency.group' "$M") == release-kind && $(yq '.concurrency["cancel-in-progress"]' "$M") == false ]] || fail "concurrency release-kind, no cancel"
ok "triggers push main (paths-ignore deploy/releases/**), contents: read, concurrency release-kind"

# 2. CI first
[[ $(yq '.jobs.ci.uses' "$M") == ./.github/workflows/ci.yml ]] || fail "job ci must call ./.github/workflows/ci.yml"
[[ $(yq -o=json -I=0 '[.jobs.build.needs] | flatten' "$M") == '["ci"]' ]] || fail "build must need ci"
[[ $(yq -o=json -I=0 '[.jobs.bump.needs] | flatten' "$M") == '["build"]' ]] || fail "bump must need build"
ok "ci → build → bump"

# 3. build: 6 images, Trivy gate, push + sign/attest by digest, digest artifact
want=$(awk '!/^#/ && NF {print $2}' deploy/deployables.tsv | sort -u)
got=$(yq '.jobs.build.strategy.matrix.include[].image' "$M" | sort -u)
[[ $got == "$want" ]] || fail "build matrix [$(echo $got)] != deployables.tsv images [$(echo $want)]"
[[ $(yq '.jobs.build.permissions["id-token"]' "$M") == write && $(yq '.jobs.build.permissions.packages' "$M") == write ]] \
  || fail "build needs id-token: write (keyless) and packages: write"
build_runs=$(yq '.jobs.build.steps[].run // ""' "$M")
grep -q 'aquasec/trivy' <<<"$build_runs" && grep -q -- '--exit-code 1' <<<"$build_runs" && grep -q -- '--severity CRITICAL' <<<"$build_runs" \
  || fail "build must gate on Trivy CRITICAL (exit-code 1)"
grep -q 'docker push' <<<"$build_runs" || fail "build must push"
grep -qE 'cosign sign --yes "\$REF"' <<<"$build_runs" && grep -qE 'cosign attest --yes --type spdxjson' <<<"$build_runs" \
  || fail "build must cosign sign + attest spdxjson"
[[ $(yq '.jobs.build.steps[] | select(.run // "" | test("cosign sign")) | .env.REF' "$M") == *'@${{ steps.push.outputs.digest }}' ]] \
  || fail "cosign must sign by digest (REF=<image>@<digest>)"
[[ $(yq '.jobs.build.steps[] | select(.uses // "" | test("upload-artifact")) | .with.name' "$M") == 'digest-${{ matrix.image }}' ]] \
  || fail "digest artifact digest-<image>"
ok "build: $(wc -w <<<"$want") images, Trivy CRITICAL gate, push, sign + attest by digest, digest artifact"

# 4. bump: bg-release-bot token, release-bump.sh, only job that writes deploy/releases
[[ $(yq '[.jobs.bump.steps[] | select(.uses // "" | test("create-github-app-token"))] | length' "$M") == 1 ]] || fail "bump must use the GitHub App token"
bump_runs=$(yq '.jobs.bump.steps[].run // ""' "$M")
grep -q 'scripts/release-bump.sh kind' <<<"$bump_runs" || fail "bump must call scripts/release-bump.sh kind"
grep -q 'chore(release): kind' <<<"$bump_runs" || fail "bump commit message chore(release): kind <sha7>"
for j in $(yq '.jobs | keys | .[]' "$M"); do
  [[ $j == bump ]] && continue
  if yq ".jobs.$j" "$M" | grep -q 'deploy/releases'; then fail "only bump may touch deploy/releases (found in $j)"; fi
done
ok "bump: GitHub App token, release-bump.sh, only writer of deploy/releases"

# 5. ci.yml: no push trigger (called by main.yml), deploy job runs scripts-test
[[ $(yq '.on | has("push")' "$CI") == false ]] || fail "$CI must not trigger on push (main.yml calls it via workflow_call)"
yq '.jobs.deploy.steps[].run // ""' "$CI" | grep -qF 'make scripts-test' || fail "$CI deploy job must run make scripts-test"
ok "ci.yml: pull_request + workflow_call only, deploy runs scripts-test"
echo "main-workflow: all checks passed"
