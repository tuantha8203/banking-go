#!/usr/bin/env bash
# Contract test for the kind add-on catalog under GitOps (platform v1 T21): renders every add-on of
# deploy/argocd/kind/values.yaml the way Argo CD does (chart + values from Git, or the manifest directory) and checks
# what blocks an app-of-apps on kind:
#   1. no Service of type LoadBalancer (kind has no LB controller → Argo CD health stays Progressing → waves stall);
#   2. no resource is declared by two add-ons (Argo CD SharedResourceWarning → one Application stays OutOfSync);
#   3. Argo CD diffs server-side (API-server defaults on Gateway/HTTPRoute/CNPG Cluster otherwise show OutOfSync).
# Needs network for the chart repos (no cluster).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
cd "$ROOT"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }
CATALOG=deploy/argocd/kind/values.yaml
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

n=$(yq '.addons | length' "$CATALOG")
for i in $(seq 0 $((n - 1))); do
  name=$(yq ".addons[$i].name" "$CATALOG")
  if [[ $(yq ".addons[$i] | has(\"chart\")" "$CATALOG") == true ]]; then
    args=()
    while read -r v; do [[ -n $v ]] && args+=(-f "$v"); done < <(yq ".addons[$i].values[]?" "$CATALOG")
    helm template "$(yq ".addons[$i].releaseName // .addons[$i].name" "$CATALOG")" "$(yq ".addons[$i].chart.name" "$CATALOG")" \
      --repo "$(yq ".addons[$i].chart.repo" "$CATALOG")" --version "$(yq ".addons[$i].chart.version" "$CATALOG")" \
      -n "$(yq ".addons[$i].namespace // \"default\"" "$CATALOG")" "${args[@]}" > "$TMP/$name.yaml" 2>"$TMP/$name.err" \
      || fail "render $name: $(tail -2 "$TMP/$name.err")"
  else
    find "$(yq ".addons[$i].path" "$CATALOG")" -type f \( -name '*.yaml' -o -name '*.yml' \) -print0 | sort -z \
      | xargs -0 -I{} sh -c 'cat "$1"; echo; echo ---' _ {} > "$TMP/$name.yaml"
  fi
  ns=$(yq ".addons[$i].namespace // \"default\"" "$CATALOG")
  # key = kind/namespace/name (cluster-scoped kinds get the add-on namespace too; good enough to spot duplicates)
  yq -N 'select(.kind != null) | .kind + "/" + (.metadata.namespace // "'"$ns"'") + "/" + .metadata.name' "$TMP/$name.yaml" \
    | sed -E 's#^(Namespace|CustomResourceDefinition|ClusterRole|ClusterRoleBinding|ClusterIssuer|ValidatingWebhookConfiguration|MutatingWebhookConfiguration|PriorityClass|StorageClass|GatewayClass)/[^/]*/#\1//#' \
    | sort -u | sed "s#\$# $name#" >> "$TMP/keys"
  lb=$(yq -N 'select(.kind == "Service" and .spec.type == "LoadBalancer") | .metadata.name' "$TMP/$name.yaml")
  [[ -z $lb ]] || fail "add-on $name renders Service(s) of type LoadBalancer ($lb): kind has no LB, Argo CD health stays Progressing"
done
ok "$n add-ons rendered, no LoadBalancer Service"

dups=$(awk '{k=$1; a[k]=a[k] " " $2; c[k]++} END {for (k in c) if (c[k] > 1) print k ":" a[k]}' "$TMP/keys" | sort)
[[ -z $dups ]] || fail "resources declared by more than one add-on (Argo CD SharedResourceWarning):"$'\n'"$dups"
ok "no resource declared by two add-ons"

[[ $(yq '.configs.params["controller.diff.server.side"]' deploy/platform/argocd/values-kind.yaml) == true ]] \
  || fail "Argo CD must diff server-side (configs.params controller.diff.server.side: true)"
ok "Argo CD server-side diff on"
echo "kind-catalog: all checks passed"
