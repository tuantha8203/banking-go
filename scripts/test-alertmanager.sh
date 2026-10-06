#!/usr/bin/env bash
# Alertmanager config as code (spec §10): renders observability/alertmanager/kind.yaml with dummy Telegram values,
# validates it with amtool and checks routing: critical + Watchdog → telegram, the rest → "null".
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TELEGRAM_BOT_TOKEN=123456:TEST-token_x TELEGRAM_CHAT_ID=-1001234 scripts/render-alertmanager.sh > "$TMP/am.yaml"
amtool check-config "$TMP/am.yaml" >/dev/null || fail "amtool check-config"
route() { amtool config routes test --config.file="$TMP/am.yaml" "$@"; }
[[ $(route alertname=Watchdog severity=none service=platform) == telegram ]] || fail "Watchdog must go to telegram"
[[ $(route alertname=ErrorBudgetBurnFast severity=critical service=public-api) == telegram ]] || fail "critical must go to telegram"
[[ $(route alertname=LatencyP95Breach severity=warning service=public-api) == null ]] || fail "warning must go to null on kind"
if TELEGRAM_BOT_TOKEN='x"; rm -rf /' TELEGRAM_CHAT_ID=1 scripts/render-alertmanager.sh >/dev/null 2>&1; then fail "malformed token accepted"; fi
echo "ok   alertmanager kind config: valid, critical + Watchdog → telegram"
