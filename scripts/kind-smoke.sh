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
echo "kind-smoke: all checks passed"
