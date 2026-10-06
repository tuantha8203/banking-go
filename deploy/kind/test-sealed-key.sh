#!/usr/bin/env bash
# Regression test for review F1 (platform v1): Sealed Secrets key backup and kind-ca always target the kind cluster,
# and kind-down never deletes the cluster when the backup fails. Needs the kind cluster up; never deletes it (fake kind).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }

# Kubeconfig whose current context is NOT kind (unreachable server), with the kind context still present.
export KUBECONFIG="$TMP/kubeconfig"
kind get kubeconfig --name "$KIND_CLUSTER" > "$KUBECONFIG"
kubectl config set-cluster elsewhere --server=https://127.0.0.1:1 >/dev/null
kubectl config set-context elsewhere --cluster=elsewhere --user="$KIND_CONTEXT" >/dev/null
kubectl config use-context elsewhere >/dev/null

# 1. backup reads the kind cluster even when the current context points elsewhere
BG_CONFIG_DIR="$TMP/cfg" "$ROOT/deploy/kind/sealed-key.sh" backup >"$TMP/out1" 2>&1 \
  || fail "backup with foreign current context: $(cat "$TMP/out1")"
[[ $(yq '.items[0].metadata.namespace' "$TMP/cfg/sealed-secrets-key.yaml") == kube-system ]] || fail "backup has no kube-system key"
grep -q 'BEGIN CERTIFICATE' "$TMP/cfg/sealed-secrets-cert.pem" || fail "backup has no cert"
ok "sealed-key backup targets $KIND_CONTEXT regardless of current context"

# 2. kind-ca reads the kind cluster even when the current context points elsewhere
HOME="$TMP/home" make -s -C "$ROOT" kind-ca >"$TMP/out2" 2>&1 || fail "kind-ca with foreign current context: $(cat "$TMP/out2")"
grep -q 'BEGIN CERTIFICATE' "$TMP/home/.config/banking-go/kind-ca.crt" || fail "kind-ca wrote no CA"
ok "kind-ca targets $KIND_CONTEXT regardless of current context"

# 3. kind-down stops before deleting the cluster when the backup fails (fake kind records delete calls)
cat > "$TMP/kind" <<EOF
#!/usr/bin/env bash
case "\$1" in get) echo "$KIND_CLUSTER" ;; delete) echo "\$*" >> "$TMP/kind.calls" ;; esac
EOF
chmod +x "$TMP/kind"
: > "$TMP/notadir"   # BG_CONFIG_DIR is a file → backup cannot write
if BG_CONFIG_DIR="$TMP/notadir" make -s -C "$ROOT" kind-down KIND="$TMP/kind" >"$TMP/out3" 2>&1; then
  fail "kind-down succeeded although the backup failed"
fi
[[ ! -s $TMP/kind.calls ]] || fail "kind-down deleted the cluster after a failed backup: $(cat "$TMP/kind.calls")"
ok "kind-down aborts before delete when the backup fails"
echo "sealed-key: all checks passed"
