#!/usr/bin/env bash
# Asserts the 10 deployables run on kind: Deployments available, migration Jobs Completed (spec §6, AD-26).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
require_kind_context
while read -r name _rest; do
  [[ -z $name || $name == \#* ]] && continue
  kubectl -n banking rollout status "deploy/$name" --timeout=300s >/dev/null || fail "deployment banking/$name not available"
  echo "ok   deployment $name"
done < "$ROOT/deploy/deployables.tsv"
for j in core-migrate public-api-migrate admin-api-migrate; do
  [[ $(kubectl -n banking get job "$j" -o jsonpath='{.status.succeeded}') == 1 ]] || fail "job banking/$j not Completed"
  kubectl -n banking logs "job/$j" | grep -q 'migrate: no migrations, nothing to do\|migrate: done' || fail "job $j log lacks migrate result"
  echo "ok   job $j Completed"
done
