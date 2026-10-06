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

while read -r name image cmd _app admin; do
  [[ -z $name || $name == \#* ]] && continue
  if [[ $cmd != - ]]; then go_check "$name" "$image" "$cmd" "$admin"; fi
done < "$ROOT/deploy/deployables.tsv"

migrate_check core /usr/local/bin/core BG_CORE
migrate_check public-api /usr/local/bin/public-api BG_PUBLIC_API
migrate_check admin-api /usr/local/bin/admin-api BG_ADMIN_API
echo "image-smoke: all images passed"
