#!/usr/bin/env bash
# Renders the Alertmanager template with TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID from the environment (stdout).
#   TELEGRAM_BOT_TOKEN=… TELEGRAM_CHAT_ID=… scripts/render-alertmanager.sh [template]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEMPLATE=${1:-$ROOT/observability/alertmanager/kind.yaml}
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}" "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is required}"
[[ $TELEGRAM_CHAT_ID =~ ^-?[0-9]+$ ]] || { echo "render-alertmanager: TELEGRAM_CHAT_ID must be numeric" >&2; exit 1; }
[[ $TELEGRAM_BOT_TOKEN =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] || { echo "render-alertmanager: TELEGRAM_BOT_TOKEN has an unexpected format" >&2; exit 1; }
sed -e "s|\${TELEGRAM_BOT_TOKEN}|$TELEGRAM_BOT_TOKEN|g" -e "s|\${TELEGRAM_CHAT_ID}|$TELEGRAM_CHAT_ID|g" "$TEMPLATE"
