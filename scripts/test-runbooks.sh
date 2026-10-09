#!/usr/bin/env bash
# Every runbook_url of observability/alerts resolves to a runbook with the observability.md § Runbooks skeleton.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
urls=$(yq -N '.groups[].rules[] | select(has("alert")) | .labels.runbook_url' observability/alerts/*.yaml | sort -u)
[[ $(wc -w <<<"$urls") -ge 5 ]] || fail "want ≥ 5 runbooks (spec §10), got: $urls"
for u in $urls; do
  [[ -f $u ]] || fail "missing runbook $u"
  head -1 "$u" | grep -q '^# [A-Za-z]' || fail "$u must start with '# <AlertName>'"
  grep -q '^- Mức / NFR / AD:' "$u" || fail "$u lacks '- Mức / NFR / AD:'"
  for h in '## Ý nghĩa' '## Tác động' '## Kiểm tra (chỉ đọc)' '## Xử lý' '## Không được làm' '## Đóng sự cố'; do
    grep -qxF "$h" "$u" || fail "$u lacks section '$h'"
  done
  echo "ok   $u"
done
