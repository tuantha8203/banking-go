#!/usr/bin/env bash
# make kind-watch: post-deploy watch on kind (observability.md § Post-deploy watch; kind = informative, 10 min).
# Exit 1 on breach and print the rollback command for the owner (AI only proposes it, constitution IV.3).
#   WATCH_MINUTES=10 scripts/kind-watch.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
require_kind_context
MINUTES=${WATCH_MINUTES:-10}
STEP=${WATCH_STEP_SECONDS:-60}
int() { printf '%.0f' "$1"; }
restarts0=$(int "$(prom_value 'sum(kube_pod_container_status_restarts_total{namespace="banking"})')")
end=$(( $(date +%s) + MINUTES * 60 ))
breach=""
while :; do
  crit=$(int "$(prom_value 'count(ALERTS{alertstate="firing",severity="critical"})')")
  err=$(prom_value 'max(sli:error_ratio:rate5m)')
  restarts=$(( $(int "$(prom_value 'sum(kube_pod_container_status_restarts_total{namespace="banking"})')") - restarts0 ))
  printf '%s critical=%s error_ratio_5m=%s new_restarts=%s\n' "$(date -u +%H:%M:%S)" "$crit" "$err" "$restarts"
  if (( crit > 0 )); then breach="critical alert firing"; fi
  if awk -v e="$err" 'BEGIN{exit !(e > 0.005)}'; then breach="5xx/server-error ratio > 0.5%"; fi
  if (( restarts > 0 )); then breach="pod restarts in namespace banking"; fi
  [[ -z $breach && $(date +%s) -lt $end ]] || break
  sleep "$STEP"
done
if [[ -n $breach ]]; then
  sha=$(git -C "$ROOT" log -1 --format=%h -- deploy/releases/kind.yaml 2>/dev/null || true)
  echo "WATCH FAILED: $breach"
  echo "Đề xuất (owner quyết): gh workflow run rollback.yml -f env=kind -f revert_sha=${sha:-<bump_sha>}"
  exit 1
fi
echo "watch ok: $MINUTES phút không vượt ngưỡng"
