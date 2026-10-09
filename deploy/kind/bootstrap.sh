#!/usr/bin/env bash
# Idempotent bootstrap of the kind env (ADR 0011, spec §7):
#   1. create kind cluster banking-go (k8s 1.36.4, 1 CP + 2 workers, host 80/443) if missing
#   2. restore the Sealed Secrets controller key from ~/.config/banking-go (before any controller starts)
#   3. install/upgrade Argo CD (chart pinned; afterwards Argo CD manages itself, wave -25)
#   4. with GH_OWNER: repo-server proxy ConfigMap (dev machine behind a proxy), root app-of-apps over HTTPS (public repo, no
#      credentials — ADR 0014), wait Synced/Healthy, back up the Sealed Secrets key
#      without GH_OWNER: stop after Argo CD (offline path: make kind-platform kind-apps)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
ARGOCD_CHART_VERSION=10.9.6
CONFIG_DIR=${BG_CONFIG_DIR:-$HOME/.config/banking-go}
log() { printf '[bootstrap] %s\n' "$*"; }
die() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

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

if [[ -z ${GH_OWNER:-} ]]; then
  log "GH_OWNER not set: Argo CD only (offline path: make kind-platform kind-apps)"
  exit 0
fi
owner=${GH_OWNER,,}
[[ $owner =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "GH_OWNER '$GH_OWNER' is not a GitHub login"
repo="https://github.com/$owner/banking-go.git"

# repo-server egress (ADR 0014): the company network blocks SSH to GitHub and kind pods have no proxy. The proxy comes from
# this machine (ARGOCD_PROXY_URL, else HTTPS_PROXY; ARGOCD_PROXY_URL= → direct) and never goes into Git.
proxy=${ARGOCD_PROXY_URL-${HTTPS_PROXY:-${https_proxy:-}}}
if [[ -n $proxy ]]; then
  kind_net=$(docker network inspect kind -f '{{range .IPAM.Config}}{{.Subnet}},{{end}}' 2>/dev/null || true)
  no_proxy="${NO_PROXY:-${no_proxy:-}},localhost,127.0.0.1,10.96.0.0/16,10.244.0.0/16,${kind_net%,},.svc,.cluster.local,kind.localhost"
  kubectl -n argocd create configmap argocd-repo-server-proxy --from-literal=HTTPS_PROXY="$proxy" --from-literal=HTTP_PROXY="$proxy" \
    --from-literal=NO_PROXY="${no_proxy#,}" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  log "argocd-repo-server egress via proxy (ConfigMap argocd-repo-server-proxy, not in Git)"
else
  kubectl -n argocd delete configmap argocd-repo-server-proxy --ignore-not-found >/dev/null
  log "argocd-repo-server egress: direct (no proxy)"
fi
kubectl -n argocd rollout restart deploy/argocd-repo-server >/dev/null
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=180s >/dev/null

log "applying root app-of-apps bg-kind-root"
sed "s|\${GH_OWNER}|$owner|g" "$ROOT/deploy/kind/root.yaml" | kubectl apply -f - >/dev/null
"$ROOT/deploy/kind/wait-argocd.sh"
"$ROOT/deploy/kind/sealed-key.sh" backup
log "done: GitOps from $repo"
