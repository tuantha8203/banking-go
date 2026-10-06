#!/usr/bin/env bash
# Spec criterion 6: no plaintext Secret manifest under deploy/ — only Sealed Secrets (*.sealed.yaml).
set -euo pipefail
cd "$(dirname "$0")/.."
bad=$(grep -rlE '^kind:[[:space:]]*Secret[[:space:]]*$' deploy --include='*.yaml' --include='*.yml' | grep -v '\.sealed\.yaml$' || true)
[[ -z $bad ]] || { echo "FAIL: plain Secret manifests under deploy/:" >&2; echo "$bad" >&2; exit 1; }
for f in deploy/secrets/kind/*.sealed.yaml; do
  [[ -e $f ]] || continue
  grep -q '^kind: SealedSecret$' "$f" || { echo "FAIL: $f is not a SealedSecret" >&2; exit 1; }
  ! grep -qE '^[[:space:]]*stringData:' "$f" || { echo "FAIL: $f contains stringData" >&2; exit 1; }
done
echo "ok   no plaintext Secret under deploy/"
