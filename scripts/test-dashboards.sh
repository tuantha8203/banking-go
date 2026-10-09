#!/usr/bin/env bash
# Dashboards as code (spec §10, observability.md § Dashboards): valid Grafana 12.4 JSON, uid bg-<file>,
# only fixed datasource uids (prom, traces), unique panel ids, required panels present.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $*" >&2; exit 1; }
declare -A REQUIRED=(
  [service-overview]='Rate (req/s)|Errors (5xx ratio)|Duration p95 (s)'
  [platform]='Argo CD applications|PostgreSQL up|RabbitMQ messages ready'
)
n_files=0
for f in observability/dashboards/*.json; do
  [[ -e $f ]] || fail "no dashboards in observability/dashboards"
  n=$(basename "$f" .json); n_files=$((n_files + 1))
  jq empty "$f" 2>/dev/null || fail "$f is not valid JSON"
  [[ $(jq -r .uid "$f") == "bg-$n" ]] || fail "$f: uid must be bg-$n"
  [[ $(jq -r .schemaVersion "$f") -ge 41 ]] || fail "$f: schemaVersion must be ≥ 41 (Grafana 12.4)"
  bad=$(jq -r '[.. | objects | select(has("datasource")) | .datasource | objects | .uid] | unique
               | map(select(. != "prom" and . != "traces")) | join(",")' "$f")
  [[ -z $bad ]] || fail "$f: datasource uid(s) '$bad' (allowed: prom, traces)"
  [[ $(jq '[.panels[].id] | length == (unique | length)' "$f") == true ]] || fail "$f: duplicate panel ids"
  [[ -n ${REQUIRED[$n]:-} ]] || fail "$f: add its required panels to $0"
  IFS='|' read -ra want <<<"${REQUIRED[$n]}"
  for t in "${want[@]}"; do
    jq -e --arg t "$t" 'any(.panels[]; .title == $t)' "$f" >/dev/null || fail "$f: missing panel '$t'"
  done
  echo "ok   $f"
done
[[ $n_files -ge 2 ]] || fail "want service-overview and platform dashboards"
