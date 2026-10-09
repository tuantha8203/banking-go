#!/usr/bin/env bash
# Installs the kind add-ons of deploy/argocd/kind/values.yaml in sync-wave order with helm/kubectl directly.
# Temporary path for S1/S2 (no GitHub yet), kind only; T21 hands the same catalog to Argo CD.
#   scripts/kind-platform.sh [--max-wave N] [name ...]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
CATALOG="$ROOT/deploy/argocd/kind/values.yaml"
MAX_WAVE=1000
ONLY=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-wave) MAX_WAVE=$2; shift 2 ;;
    *) ONLY+=("$1"); shift ;;
  esac
done
require_kind_context

# fd 3 keeps helm/kubectl/post commands from reading the catalog stream; the loop runs in this shell (set -e applies).
while IFS= read -r a <&3; do
  get() { jq -r "$1 // empty" <<<"$a"; }
  name=$(get .name); wave=$(get .wave); ns=$(get .namespace)
  (( wave <= MAX_WAVE )) || continue
  [[ ${#ONLY[@]} -eq 0 || " ${ONLY[*]} " == *" $name "* ]] || continue
  echo "== wave $wave: $name"
  if [[ -n $(get .chart.name) ]]; then
    args=(upgrade --install "$(get '.releaseName // .name')" "$(get .chart.name)" --repo "$(get .chart.repo)"
          --version "$(get .chart.version)" --namespace "$ns" --create-namespace --wait --timeout 10m)
    while IFS= read -r v; do [[ -n $v ]] && args+=(-f "$ROOT/$v"); done < <(jq -r '.values[]? // empty' <<<"$a")
    helm "${args[@]}"
  else
    dir="$ROOT/$(get .path)"
    if ! find "$dir" -name '*.yaml' -o -name '*.yml' | grep -q .; then echo "   (no manifests in $(get .path), skipped)"; continue; fi
    [[ -z $ns ]] || kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply --server-side --force-conflicts -R -f "$dir"
  fi
  w=$(get .wait); [[ -z $w ]] || eval "kubectl wait $w"
  p=$(get .post); [[ -z $p ]] || (cd "$ROOT" && eval "$p")
done 3< <(yq -o=json -I=0 '.addons | sort_by(.wave) | .[]' "$CATALOG")
echo "kind-platform: done"
