#!/usr/bin/env bash
# make kind-smoke: end-to-end checks of the kind env through Traefik (spec criteria 3–5).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
RELEASES=${RELEASES_FILE:-$ROOT/deploy/releases/kind.yaml}
NS=banking
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }
require_kind_context

# 1. APIs through Traefik (-k: kind CA, see make kind-ca)
check_json() { # check_json <host> <path>
  local url="https://$1$2" code
  code=$(curl -sk --max-time 10 -o "$TMP/body" -w '%{http_code}' "$url") || fail "$url unreachable"
  [[ $code == 200 && $(tr -d '\n' < "$TMP/body") == '{"status":"ok"}' ]] || fail "$url → $code $(head -c 200 "$TMP/body")"
  ok "$url → 200 {\"status\":\"ok\"}"
}
# 2. SPAs: 200 HTML
check_html() { # check_html <host>
  local url="https://$1/" out
  out=$(curl -sk --max-time 10 -o "$TMP/body" -w '%{http_code} %{content_type}' "$url") || fail "$url unreachable"
  [[ $out == "200 text/html"* ]] && grep -q '<div id="root">' "$TMP/body" || fail "$url → $out"
  ok "$url → 200 HTML"
}
check_json api.kind.localhost /v1/ping
check_json admin-api.kind.localhost /v1/ping
check_html app.kind.localhost
check_html admin.kind.localhost

# 3. Migration Jobs Completed (PreSync / Helm hook)
for j in core-migrate public-api-migrate admin-api-migrate; do
  [[ $(kubectl -n $NS get job "$j" -o jsonpath='{.status.succeeded}') == 1 ]] || fail "job $j not Completed"
  ok "job $j Completed"
done

# 4. Running digests == deploy/releases/kind.yaml (written only by bg-release-bot)
if [[ -f $RELEASES ]]; then
  while read -r name _rest; do
    [[ -z $name || $name == \#* ]] && continue
    want=$(yq ".\"$name\".digest" "$RELEASES")
    [[ $want == sha256:* ]] || fail "$RELEASES has no digest for $name"
    got=$(kubectl -n $NS get pods -l "app.kubernetes.io/name=$name" --field-selector=status.phase=Running \
      -o jsonpath='{range .items[*]}{.status.containerStatuses[0].imageID}{"\n"}{end}' | sort -u)
    [[ -n $got ]] || fail "no running pod for $name"
    while read -r id; do [[ $id == *"@$want" ]] || fail "$name runs $id, want @$want"; done <<<"$got"
    ok "$name runs $want"
  done < "$ROOT/deploy/deployables.tsv"
else
  echo "skip digest check: $RELEASES not found (bg-release-bot writes it from main.yml, S3/T19)"
fi

# 5. Telemetry (spec criterion 5): traffic → trace in Jaeger + RED metric in Prometheus
for _ in $(seq 20); do curl -sk -o /dev/null --max-time 5 https://api.kind.localhost/v1/ping; done
start=$(date -u -d '-15 min' +%Y-%m-%dT%H:%M:%SZ); end=$(date -u -d '+1 min' +%Y-%m-%dT%H:%M:%SZ)
spans=0
for _ in $(seq 36); do
  spans=$(svc_get observability jaeger:16686 "/api/v3/traces?query.service_name=public-api&query.start_time_min=$start&query.start_time_max=$end" 2>/dev/null \
    | jq '[.. | objects | .spans? // empty | .[]] | length' 2>/dev/null || echo 0)
  [[ $spans -gt 0 ]] && break; sleep 5
done
[[ $spans -gt 0 ]] || fail "no public-api trace in Jaeger (/api/v3/traces)"
ok "Jaeger has $spans public-api span(s)"
rps=0
for _ in $(seq 36); do
  # keep traffic flowing: after a fresh rollout the first export already holds the burst above, and rate() needs an increase
  for _ in $(seq 5); do curl -sk -o /dev/null --max-time 5 https://api.kind.localhost/v1/ping; done
  rps=$(prom_value 'sum(rate(http_server_request_duration_seconds_count{service_name="public-api"}[5m]))')
  awk -v v="$rps" 'BEGIN{exit !(v > 0)}' && break; sleep 5
done
awk -v v="$rps" 'BEGIN{exit !(v > 0)}' || fail "Prometheus RED rate for public-api is 0"
ok "Prometheus RED rate public-api = $rps req/s"

# 6. Dashboards as code are loaded in Grafana (spec criterion 5)
guser=$(kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-user}' | base64 -d)
gpass=$(kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
for uid in bg-service-overview bg-platform; do
  curl -sk --max-time 10 -u "$guser:$gpass" "https://grafana.kind.localhost/api/dashboards/uid/$uid" \
    | jq -e --arg u "$uid" '.dashboard.uid == $u' >/dev/null || fail "Grafana dashboard $uid missing"
  ok "Grafana dashboard $uid"
done

# 7. Watchdog reaches Telegram (spec criterion 5): at least one HTTP request to the Telegram API succeeded.
#    alertmanager_notifications_failed_total only grows once retries are exhausted, so count successful requests.
active=$(svc_get monitoring kube-prometheus-stack-alertmanager:9093 '/api/v2/alerts?filter=alertname%3D%22Watchdog%22' | jq 'length')
[[ $active -ge 1 ]] || fail "Watchdog not active in Alertmanager"
delivered=0
for _ in $(seq 24); do
  delivered=$(prom_value 'sum(alertmanager_notification_requests_total{integration="telegram"}) - sum(alertmanager_notification_requests_failed_total{integration="telegram"})')
  awk -v v="$delivered" 'BEGIN{exit !(v > 0)}' && break; sleep 5
done
requests=$(prom_value 'sum(alertmanager_notification_requests_total{integration="telegram"})')
awk -v v="$delivered" 'BEGIN{exit !(v > 0)}' || fail "no successful telegram request ($requests attempted, all failed; see alertmanager logs)"
ok "Alertmanager delivered $delivered telegram request(s) successfully"
echo "kind-smoke: all checks passed"
