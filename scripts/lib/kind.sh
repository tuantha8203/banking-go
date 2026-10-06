# Shared helpers for kind scripts (source me after putting ./bin on PATH).
KIND_CLUSTER=${KIND_CLUSTER:-banking-go}
KIND_CONTEXT="kind-$KIND_CLUSTER"

# require_kind_context exits unless kubectl points at the kind cluster (never touch another cluster).
require_kind_context() {
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null || true)
  [[ $ctx == "$KIND_CONTEXT" ]] || { echo "kubectl context is '$ctx', want $KIND_CONTEXT (run make kind-up)" >&2; exit 1; }
}
