#!/usr/bin/env bash
# Asserts the kind cluster matches spec §7: k8s 1.36, 1 control-plane + 2 workers, host 80/443, Argo CD running.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
require_kind_context
[[ $(kubectl get nodes --no-headers | wc -l) -eq 3 ]] || fail "want 3 nodes"
[[ $(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l) -eq 1 ]] || fail "want 1 control-plane"
versions=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' | sort -u)
[[ $versions == v1.36.4 ]] || fail "kubelet versions: $versions (want v1.36.4)"
[[ $(kubectl get nodes -l ingress-ready=true -o name) == "node/$KIND_CLUSTER-control-plane" ]] || fail "control-plane must carry ingress-ready=true"
ports=$(docker inspect "$KIND_CLUSTER-control-plane" --format '{{json .HostConfig.PortBindings}}')
[[ $ports == *'"80/tcp"'* && $ports == *'"443/tcp"'* ]] || fail "host ports 80/443 not mapped: $ports"
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s >/dev/null || fail "argocd-server not available"
echo "ok   kind cluster $KIND_CLUSTER: 3 nodes v1.36.4, 80/443 on control-plane, Argo CD running"
