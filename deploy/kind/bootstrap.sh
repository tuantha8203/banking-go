#!/usr/bin/env bash
# Idempotent bootstrap of the kind env (ADR 0011, spec §7):
#   1. create kind cluster banking-go (k8s 1.36.4, 1 CP + 2 workers, host 80/443) if missing
#   2. restore the Sealed Secrets controller key from ~/.config/banking-go (before any controller starts)
#   3. install/upgrade Argo CD (chart pinned); the app-of-apps root is applied from T21 on
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
ARGOCD_CHART_VERSION=10.9.6
log() { printf '[bootstrap] %s\n' "$*"; }

if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
  log "cluster $KIND_CLUSTER exists"
else
  log "creating cluster $KIND_CLUSTER"
  kind create cluster --config "$ROOT/deploy/kind/kind-config.yaml" --wait 180s
fi
kubectl config use-context "$KIND_CONTEXT" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=180s >/dev/null

"$ROOT/deploy/kind/sealed-key.sh" restore

log "installing Argo CD (chart argo-cd $ARGOCD_CHART_VERSION)"
helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd --create-namespace -f "$ROOT/deploy/platform/argocd/values-kind.yaml" --wait --timeout 10m
log "done: $(kubectl get nodes --no-headers | wc -l) nodes, context $KIND_CONTEXT"
