#!/usr/bin/env bash
# Deploys the 10 thin charts with helm directly using locally built images (S1/S2, before GitOps; kind only).
# Migration Jobs run first as Helm pre-install/pre-upgrade hooks (same Job is an Argo CD PreSync hook in S3).
#   IMAGE_PREFIX=banking-go IMAGE_TAG=local scripts/kind-apps.sh [deployable ...]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
PREFIX=${IMAGE_PREFIX:-banking-go}
TAG=${IMAGE_TAG:-local}
require_kind_context
while read -r name image _rest <&3; do
  [[ -z $name || $name == \#* ]] && continue
  [[ $# -eq 0 || " $* " == *" $name "* ]] || continue
  chart="$ROOT/deploy/helm/$name"
  echo "== $name ($PREFIX/$image:$TAG)"
  helm dependency build "$chart" >/dev/null
  helm upgrade --install "$name" "$chart" --namespace banking --create-namespace \
    -f "$chart/values-kind.yaml" \
    --set image.repository="$PREFIX/$image" --set image.tag="$TAG" --set image.pullPolicy=Never \
    --wait --timeout 5m
done 3< "$ROOT/deploy/deployables.tsv"
echo "kind-apps: done"
