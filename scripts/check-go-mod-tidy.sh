#!/usr/bin/env bash
# Every Go module in go.work is tidy: `go mod tidy -diff` prints nothing (platform v1 review S1 F5, T22).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
bad=0
for m in $(go work edit -json | jq -r '.Use[].DiskPath'); do
  if out=$(cd "$m" && go mod tidy -diff 2>&1) && [[ -z $out ]]; then
    echo "ok   $m tidy"
  else
    echo "FAIL: $m is not tidy (run: cd $m && go mod tidy)" >&2
    printf '%s\n' "$out" | head -20 >&2
    bad=1
  fi
done
exit $bad
