# Shared helpers for kind scripts (source me after putting ./bin on PATH).
KIND_CLUSTER=${KIND_CLUSTER:-banking-go}
KIND_CONTEXT="kind-$KIND_CLUSTER"

# require_kind_context exits unless kubectl points at the kind cluster (never touch another cluster).
require_kind_context() {
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null || true)
  [[ $ctx == "$KIND_CONTEXT" ]] || { echo "kubectl context is '$ctx', want $KIND_CONTEXT (run make kind-up)" >&2; exit 1; }
}

# svc_get <namespace> <service:port> <path?query>: GET through the API server service proxy (no port-forward).
svc_get() { kubectl get --raw "/api/v1/namespaces/$1/services/$2/proxy$3"; }

# prom <promql>: instant query against the kind Prometheus; prints the JSON response.
prom() { svc_get monitoring kube-prometheus-stack-prometheus:9090 "/api/v1/query?query=$(jq -rn --arg q "$1" '$q|@uri')"; }

# prom_value <promql>: first sample value, or 0 when the result is empty.
prom_value() { prom "$1" | jq -r '.data.result[0].value[1] // "0"'; }
