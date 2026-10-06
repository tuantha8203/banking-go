#!/usr/bin/env bash
# Backup/restore of the kind Sealed Secrets controller key outside the repo (spec §9, ADR 0011).
#   sealed-key.sh restore   apply the saved key into kube-system before the controller starts (no-op without a backup)
#   sealed-key.sh backup    save the controller key(s) + public cert to $BG_CONFIG_DIR (default ~/.config/banking-go), 0600
# Always talks to the kind context (never the current one), so a foreign key is never saved or restored.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
DIR=${BG_CONFIG_DIR:-$HOME/.config/banking-go}
KEY="$DIR/sealed-secrets-key.yaml"
CERT="$DIR/sealed-secrets-cert.pem"
NS=kube-system
LABEL=sealedsecrets.bitnami.com/sealed-secrets-key
trap 'rm -f "$KEY.tmp" "$CERT.tmp"' EXIT

case "${1:-}" in
  restore)
    if [[ -s "$KEY" ]]; then
      kubectl --context "$KIND_CONTEXT" -n "$NS" apply -f "$KEY" >/dev/null
      echo "[sealed-key] restored controller key from $KEY"
    else
      echo "[sealed-key] no backup at $KEY: the controller will create a new key; re-run 'make seal' and commit"
    fi ;;
  backup)
    keys=$(kubectl --context "$KIND_CONTEXT" -n "$NS" get secret -l "$LABEL" -o name)
    [[ -n $keys ]] || { echo "[sealed-key] no controller key in $NS yet: nothing to back up"; exit 0; }
    mkdir -p "$DIR" && chmod 700 "$DIR"
    umask 077
    kubectl --context "$KIND_CONTEXT" -n "$NS" get secret -l "$LABEL" -o yaml \
      | yq 'del(.items[].metadata.resourceVersion, .items[].metadata.uid, .items[].metadata.creationTimestamp, .items[].metadata.managedFields, .metadata)' \
      > "$KEY.tmp"
    mv "$KEY.tmp" "$KEY"
    kubeseal --context "$KIND_CONTEXT" --controller-namespace "$NS" --controller-name sealed-secrets-controller --fetch-cert > "$CERT.tmp"
    mv "$CERT.tmp" "$CERT"
    echo "[sealed-key] backed up to $KEY and $CERT" ;;
  *) echo "usage: $0 restore|backup" >&2; exit 2 ;;
esac
