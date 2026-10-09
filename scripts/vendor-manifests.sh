#!/usr/bin/env bash
# Downloads (default) or verifies (--check) the upstream manifests pinned in deploy/platform/vendor.lock.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-download}
status=0
while read -r dest sha url; do
  [[ -z "$dest" || "$dest" == \#* ]] && continue
  if [[ $MODE == download ]]; then
    mkdir -p "$ROOT/$(dirname "$dest")"
    curl -fsSL --retry 3 -o "$ROOT/$dest.tmp" "$url"
    echo "$sha  $ROOT/$dest.tmp" | sha256sum -c --quiet - || { rm -f "$ROOT/$dest.tmp"; echo "checksum mismatch: $url" >&2; exit 1; }
    mv "$ROOT/$dest.tmp" "$ROOT/$dest"; echo "vendored $dest"
  else
    if echo "$sha  $ROOT/$dest" | sha256sum -c --quiet - 2>/dev/null; then echo "ok   $dest"; else echo "FAIL: $dest differs from vendor.lock" >&2; status=1; fi
  fi
done < "$ROOT/deploy/platform/vendor.lock"
exit $status
