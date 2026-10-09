#!/usr/bin/env bash
# Asserts every pinned k8s/devops CLI in ./bin has the expected version (platform v1 T1).
set -euo pipefail
B=${1:-bin}
fail() { echo "FAIL: $*" >&2; exit 1; }
expect() { # expect <regex> <cmd...>
  local want=$1 out; shift
  out=$("$@" 2>&1) || fail "$* did not run: $out"
  grep -Eq -- "$want" <<<"$out" || fail "$*: want /$want/ in: $out"
  echo "ok   $1 → $want"
}
expect 'kind v0\.33\.0'                       "$B/kind" version
expect 'Client Version: v1\.36\.5'            "$B/kubectl" version --client
expect '^v4\.3\.0'                            "$B/helm" version --short
expect 'kubeconform[[:space:]]+v0\.8\.0'      go version -m "$B/kubeconform"
expect 'version v?4\.54\.1'                   "$B/yq" --version
expect 'promtool, version 3\.15\.0'           "$B/promtool" --version
expect 'amtool, version 0\.34\.1'             "$B/amtool" --version
expect '0\.40\.0'                             "$B/kubeseal" --version
expect '1\.7\.12'                             "$B/actionlint" -version
expect 'unittest[[:space:]]+1\.2\.1'          env HELM_PLUGINS="$B/helm-plugins" "$B/helm" plugin list
expect 'v3\.1\.3'                             "$B/cosign" version
expect 'gh version 2\.102\.0'                 "$B/gh" --version
expect 'version: 0\.11\.0'                   "$B/shellcheck" --version
echo "all k8s tools pinned"
