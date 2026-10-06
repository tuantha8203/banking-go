#!/usr/bin/env bash
# Asserts the kind add-ons are installed and healthy (spec §8). One section per wave group; later tasks append.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }
ready() { kubectl get "$@" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'; }
require_kind_context

# --- waves -30/-20/-19/-18: CRDs, controllers, issuers, gateway
v=$(kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' || true)
[[ $v == v1.6.2 ]] || fail "Gateway API CRDs bundle-version=$v (want v1.6.2)"; ok "Gateway API CRDs $v"
for d in cert-manager/cert-manager traefik/traefik cnpg-system/cloudnative-pg kube-system/sealed-secrets-controller \
         rabbitmq-system/rabbitmq-cluster-operator rabbitmq-system/messaging-topology-operator; do
  kubectl -n "${d%%/*}" rollout status "deploy/${d#*/}" --timeout=180s >/dev/null || fail "deployment $d not available"
  ok "deployment $d"
done
for ci in selfsigned kind-ca bg-internal-ca; do
  [[ $(ready clusterissuer "$ci") == True ]] || fail "ClusterIssuer $ci not Ready"; ok "ClusterIssuer $ci"
done
[[ $(ready -n traefik certificate wildcard-kind-localhost) == True ]] || fail "Certificate traefik/wildcard-kind-localhost not Ready"
[[ $(kubectl -n traefik get gateway traefik-gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}') == True ]] \
  || fail "Gateway traefik/traefik-gateway not Programmed"; ok "Gateway traefik-gateway Programmed"
issuer=$(curl -skv --max-time 10 https://probe.kind.localhost/ 2>&1 | grep -i 'issuer:' || true)
[[ $issuer == *"banking-go kind root CA"* ]] || fail "TLS on :443 is not issued by the kind CA ($issuer)"
code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 https://probe.kind.localhost/)
[[ $code == 404 ]] || fail "Traefik on :443 answered $code for an unknown host (want 404)"; ok "Traefik serves *.kind.localhost with the kind CA"
[[ -s ${BG_CONFIG_DIR:-$HOME/.config/banking-go}/sealed-secrets-key.yaml ]] || fail "Sealed Secrets key not backed up"
ok "Sealed Secrets key backed up"
