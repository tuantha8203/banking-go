#!/usr/bin/env bash
# Renders the Alertmanager template with TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID from the environment (stdout).
#   TELEGRAM_BOT_TOKEN=… TELEGRAM_CHAT_ID=… [TELEGRAM_PROXY_URL=http://host:port] scripts/render-alertmanager.sh [template]
# TELEGRAM_PROXY_URL (optional): HTTP proxy for api.telegram.org when the cluster has no direct egress (corporate proxy).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
TEMPLATE=${1:-$ROOT/observability/alertmanager/kind.yaml}
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}" "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is required}"
[[ $TELEGRAM_CHAT_ID =~ ^-?[0-9]+$ ]] || { echo "render-alertmanager: TELEGRAM_CHAT_ID must be numeric" >&2; exit 1; }
[[ $TELEGRAM_BOT_TOKEN =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] || { echo "render-alertmanager: TELEGRAM_BOT_TOKEN has an unexpected format" >&2; exit 1; }
proxy=${TELEGRAM_PROXY_URL:-}
[[ -z $proxy || $proxy =~ ^https?://[A-Za-z0-9.-]+(:[0-9]{1,5})?/?$ ]] \
  || { echo "render-alertmanager: TELEGRAM_PROXY_URL must be http(s)://host[:port] without credentials" >&2; exit 1; }
rendered=$(sed -e "s|\${TELEGRAM_BOT_TOKEN}|$TELEGRAM_BOT_TOKEN|g" -e "s|\${TELEGRAM_CHAT_ID}|$TELEGRAM_CHAT_ID|g" "$TEMPLATE")
if [[ -n $proxy ]]; then
  PROXY=$proxy yq '(.receivers[] | select(.name == "telegram") | .telegram_configs[].http_config.proxy_url) = strenv(PROXY)' <<<"$rendered"
else
  printf '%s\n' "$rendered"
fi
