#!/usr/bin/env bash
# Waits until every Application of the kind app-of-apps (root + add-ons + apps) is Synced and Healthy (spec criterion 1).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
require_kind_context
CATALOG="$ROOT/deploy/argocd/kind/values.yaml"
want=$(( $(yq '.addons | length' "$CATALOG") + $(yq '.apps | length' "$CATALOG") + 1 ))
deadline=$(( $(date +%s) + ${WAIT_TIMEOUT:-1800} ))
while :; do
  apps=$(kubectl -n argocd get applications.argoproj.io -o json)
  total=$(jq '.items | length' <<<"$apps")
  bad=$(jq -r '[.items[] | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
               | "\(.metadata.name)=\(.status.sync.status // "?")/\(.status.health.status // "?")"] | join(" ")' <<<"$apps")
  if [[ $total -ge $want && -z $bad ]]; then echo "ok   $total Argo CD applications Synced/Healthy"; exit 0; fi
  (( $(date +%s) < deadline )) || { echo "FAIL: $total/$want applications; not ready: $bad" >&2; exit 1; }
  echo "waiting: $total/$want applications; not ready: ${bad:-none}"
  sleep 15
done
