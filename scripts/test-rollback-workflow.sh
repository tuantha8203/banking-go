#!/usr/bin/env bash
# Contract test for .github/workflows/rollback.yml (platform v1 T20; deployment.md § Rollback → App, D-22, D-45):
# owner-dispatched only, env kind only, same concurrency as main.yml, bg-release-bot token, guard before revert,
# workflow inputs never interpolated into shell (script injection).
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }
W=.github/workflows/rollback.yml
[[ -f $W ]] || fail "$W missing"

# 1. trigger + inputs
[[ $(yq -o=json -I=0 '.on | keys' "$W") == '["workflow_dispatch"]' ]] || fail "$W must only run on workflow_dispatch"
[[ $(yq '.on.workflow_dispatch.inputs.env.type' "$W") == choice && $(yq -o=json -I=0 '.on.workflow_dispatch.inputs.env.options' "$W") == '["kind"]' ]] \
  || fail "input env must be choice [kind] (platform v1)"
[[ $(yq '.on.workflow_dispatch.inputs.revert_sha.required' "$W") == true ]] || fail "revert_sha must be required"
ok "workflow_dispatch only; env choice [kind]; revert_sha required"

# 2. permissions + concurrency shared with main.yml
[[ $(yq '.permissions.contents' "$W") == read && $(yq '.permissions | length' "$W") == 1 ]] || fail "top-level permissions must be contents: read only"
[[ $(yq '.concurrency.group' "$W") == 'release-${{ inputs.env }}' && $(yq '.concurrency["cancel-in-progress"]' "$W") == false ]] \
  || fail "concurrency must be release-\${{ inputs.env }} without cancel (same group as main.yml)"
ok "contents: read; concurrency release-<env> (never races a bump)"

# 3. steps: App token, full history of main, guard before revert, push to main
[[ $(yq '.jobs | length' "$W") == 1 ]] || fail "one job expected"
job=$(yq '.jobs | keys | .[0]' "$W")
[[ $(yq "[.jobs.$job.steps[] | select(.uses // \"\" | test(\"create-github-app-token\"))] | length" "$W") == 1 ]] || fail "must use the bg-release-bot App token"
co=$(yq -o=json -I=0 ".jobs.$job.steps[] | select(.uses // \"\" | test(\"actions/checkout\")) | .with" "$W")
[[ $(jq -r '.ref' <<<"$co") == main && $(jq -r '."fetch-depth"' <<<"$co") == 0 ]] || fail "checkout must be ref main with fetch-depth 0: $co"
runs=$(yq ".jobs.$job.steps[].run // \"\"" "$W")
guard=$(grep -n 'scripts/rollback-check.sh' <<<"$runs" | head -1 | cut -d: -f1)
revert=$(grep -n 'git revert' <<<"$runs" | head -1 | cut -d: -f1)
[[ -n $guard && -n $revert && $guard -lt $revert ]] || fail "scripts/rollback-check.sh must run before git revert"
grep -q 'git push origin HEAD:main' <<<"$runs" || fail "revert must be pushed to main by the bot"
ok "App token, checkout main (full history), rollback-check before git revert, push to main"

# 4. no script injection: inputs only through env
if grep -n '\${{ *\(github\.event\.\)\?inputs\.' <<<"$runs"; then fail "inputs interpolated into run: pass them via env"; fi
ok "inputs reach shell only via env (no \${{ inputs.* }} in run)"
echo "rollback-workflow: all checks passed"
