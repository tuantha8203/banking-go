#!/usr/bin/env bash
# Contract test for .github/workflows/ci.yml (platform v1 T18; deployment.md § Pipeline, D-45): the PR gate builds every
# image without pushing, lints/tests deploy + observability as code, lints the workflows — and actionlint really
# rejects a broken workflow (negative control), so a green `make actionlint` means something.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }
CI=.github/workflows/ci.yml
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

# 1. actionlint is wired and clean on the repo
make -s actionlint >"$TMP/actionlint.out" 2>&1 || { cat "$TMP/actionlint.out" >&2; fail "make actionlint"; }
ok "make actionlint clean"

# 2. negative control: actionlint rejects a workflow with an unknown `needs`
cat > "$TMP/bad.yml" <<'EOF'
on: pull_request
jobs:
  build:
    needs: [does-not-exist]
    runs-on: ubuntu-latest
    steps:
      - run: echo hi
EOF
if actionlint "$TMP/bad.yml" >"$TMP/neg.out" 2>&1; then fail "actionlint accepted a broken workflow"; fi
grep -q 'does-not-exist' "$TMP/neg.out" || fail "actionlint failed for another reason: $(head -3 "$TMP/neg.out")"
ok "actionlint rejects a broken workflow (negative control)"

# 3. triggers and permissions (D-45: no pull_request_target)
[[ $(yq '(.on | has("pull_request")) and (.on | has("workflow_call"))' "$CI") == true ]] || fail "$CI must run on pull_request and workflow_call"
if grep -l 'pull_request_target' .github/workflows/*.yml; then fail "pull_request_target is forbidden (D-45)"; fi
[[ $(yq '.permissions.contents' "$CI") == read ]] || fail "$CI top-level permissions must be contents: read"
ok "triggers pull_request + workflow_call, no pull_request_target, contents: read"

# 4. jobs
for j in images deploy observability actionlint; do
  [[ $(yq ".jobs | has(\"$j\")" "$CI") == true ]] || fail "$CI lacks job $j"
done
ok "jobs images, deploy, observability, actionlint"

# 5. images matrix == images of deploy/deployables.tsv, built but never pushed
want=$(awk '!/^#/ && NF {print $2}' deploy/deployables.tsv | sort -u)
got=$(yq '.jobs.images.strategy.matrix.include[].image' "$CI" | sort -u)
[[ $got == "$want" ]] || fail "images matrix [$(echo $got)] != deployables.tsv images [$(echo $want)]"
[[ $(yq '[.jobs.images.steps[].with.push // false] | any' "$CI") == false ]] || fail "images job must not push"
if yq '.jobs.images' "$CI" | grep -nE 'docker (push|login)|registry-1|ghcr\.io'; then fail "images job must not log in or push"; fi
ok "images matrix = $(wc -w <<<"$want") images from deploy/deployables.tsv, no push"

# 6. deploy / observability / actionlint jobs run the local targets
runs() { yq ".jobs.$1.steps[].run // \"\"" "$CI"; }
for want in 'make helm-lint helm-test' 'scripts/vendor-manifests.sh --check' 'scripts/check-no-plain-secrets.sh'; do
  runs deploy | grep -qF -- "$want" || fail "deploy job must run '$want'"
done
for t in alerts-test dashboards-test alertmanager-test runbooks-test obs-gen-check collector-validate; do
  runs observability | grep -qw -- "$t" || fail "observability job must run make $t"
done
runs actionlint | grep -qF 'make actionlint' || fail "actionlint job must run make actionlint"
ok "deploy, observability, actionlint jobs run the make targets"
echo "ci-workflow: all checks passed"
