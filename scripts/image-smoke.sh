#!/usr/bin/env bash
# Runs every locally built image and probes it (platform v1 T3/T4). Needs Docker + curl.
#   scripts/image-smoke.sh [prefix] [tag]      (defaults: banking-go local; VERSION env = expected version)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREFIX=${1:-banking-go}
TAG=${2:-local}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }
CIDS=()
cleanup() { [[ ${#CIDS[@]} -eq 0 ]] || docker rm -f "${CIDS[@]}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

host_port() { docker port "$1" "$2/tcp" | head -1 | sed 's/.*://'; }
wait_http() { # wait_http <url> → body
  for _ in $(seq 40); do curl -fsS --max-time 2 "$1" 2>/dev/null && return 0; sleep 0.25; done
  return 1
}

go_check() { # go_check <deployable> <image> <command> <admin_port>
  local name=$1 image=$2 cmd=$3 admin=$4 ref="$PREFIX/$2:$TAG" cid port body
  [[ $(docker inspect -f '{{.Config.User}}' "$ref") == 65532:65532 ]] || fail "$ref must run as 65532:65532"
  cid=$(docker run -d -p "127.0.0.1::$admin" --entrypoint "$cmd" "$ref"); CIDS+=("$cid")
  port=$(host_port "$cid" "$admin")
  body=$(wait_http "http://127.0.0.1:$port/livez") || { docker logs "$cid" >&2; fail "$name: /livez not ready"; }
  [[ $body == '{"status":"ok"}' ]] || fail "$name: /livez body $body"
  if [[ -n ${VERSION:-} ]]; then
    docker logs "$cid" 2>&1 | grep -q "\"version\":\"$VERSION\"" || fail "$name: logs lack version $VERSION"
  fi
  docker rm -f "$cid" >/dev/null
  ok "$name ($ref $cmd) /livez"
}

migrate_check() { # migrate_check <image> <command> <env-prefix>
  docker run --rm --entrypoint "$2" -e "$3_MIGRATOR_DSN=postgres://m:x@127.0.0.1:1/db?connect_timeout=1" \
    "$PREFIX/$1:$TAG" migrate up >/dev/null || fail "$2 migrate up (no migrations) must exit 0"
  ok "$2 migrate up → no-op"
}

spa_check() { # spa_check <deployable> <image>
  local name=$1 ref="$PREFIX/$2:$TAG" dir cid port base asset
  [[ $(docker inspect -f '{{.Config.User}}' "$ref") == 101 ]] || fail "$ref must run as uid 101"
  dir=$(mktemp -d)
  printf "window.__BG_CONFIG__ = { apiBaseUrl: 'https://api.smoke.test', env: 'smoke', release: 'smoke' }\n" > "$dir/config.js"
  chmod 644 "$dir/config.js"
  cid=$(docker run -d --read-only --tmpfs /tmp:rw,mode=1777 -e BG_API_ORIGIN=https://api.smoke.test \
    -v "$dir/config.js:/usr/share/nginx/html/config.js:ro" -p 127.0.0.1::8080 "$ref"); CIDS+=("$cid")
  port=$(host_port "$cid" 8080); base="http://127.0.0.1:$port"
  wait_http "$base/healthz" >/dev/null || { docker logs "$cid" >&2; fail "$name: /healthz not ready"; }
  curl -fsS "$base/" | grep -q '<div id="root">' || fail "$name: / is not the SPA"
  curl -fsS "$base/" | grep -q 'src="/config.js"' || fail "$name: index.html does not load /config.js"
  curl -fsS "$base/accounts/123" | grep -q '<div id="root">' || fail "$name: no SPA fallback"
  curl -fsS "$base/config.js" | grep -q 'api.smoke.test' || fail "$name: /config.js is not the mounted file"
  curl -fsSI "$base/config.js" | grep -qi '^cache-control: no-cache' || fail "$name: /config.js must be no-cache"
  asset=$(curl -fsS "$base/" | grep -o '/assets/[^"]*\.js' | head -1)
  curl -fsSI "$base$asset" | grep -qi '^cache-control: .*immutable' || fail "$name: $asset must be immutable"
  curl -fsSI "$base/" | grep -qi "^content-security-policy: .*connect-src 'self' https://api.smoke.test" || fail "$name: CSP connect-src"
  docker rm -f "$cid" >/dev/null; rm -rf "$dir"
  ok "$name ($ref) nginx: SPA, config.js, cache headers, CSP"
}

while read -r name image cmd _app admin; do
  [[ -z $name || $name == \#* ]] && continue
  if [[ $cmd != - ]]; then go_check "$name" "$image" "$cmd" "$admin"; else spa_check "$name" "$image"; fi
done < "$ROOT/deploy/deployables.tsv"

migrate_check core /usr/local/bin/core BG_CORE
migrate_check public-api /usr/local/bin/public-api BG_PUBLIC_API
migrate_check admin-api /usr/local/bin/admin-api BG_ADMIN_API
echo "image-smoke: all images passed"
