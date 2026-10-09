#!/usr/bin/env bash
# Regression tests for the kind scripts (platform v1 review S1: F1, T22 R1–R3), run by `make kind-test`:
# Sealed Secrets key backup and kind-ca always target the kind cluster, kind-down never deletes the cluster when the
# backup (or cluster listing) fails, and check-platform rejects a stale key backup.
# Needs the kind cluster up; never deletes it (fake kind) and never touches ~/.config/banking-go (temp dirs).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }

ORIG_KUBECONFIG=${KUBECONFIG:-}
with_real_kubeconfig() { if [[ -n $ORIG_KUBECONFIG ]]; then KUBECONFIG=$ORIG_KUBECONFIG "$@"; else env -u KUBECONFIG "$@"; fi; }

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
HOME="$TMP/home" make -s -C "$ROOT" kind-ca KIND_CLUSTER="$KIND_CLUSTER" >"$TMP/out2" 2>&1 || fail "kind-ca with foreign current context: $(cat "$TMP/out2")"
grep -q 'BEGIN CERTIFICATE' "$TMP/home/.config/banking-go/kind-ca.crt" || fail "kind-ca wrote no CA"
ok "kind-ca targets $KIND_CONTEXT regardless of current context"

# 3. kind-down stops before deleting the cluster when the backup fails (fake kind records delete calls)
cat > "$TMP/kind" <<EOF
#!/usr/bin/env bash
case "\$1" in get) echo "$KIND_CLUSTER" ;; delete) echo "\$*" >> "$TMP/kind.calls" ;; esac
EOF
chmod +x "$TMP/kind"
: > "$TMP/notadir"   # BG_CONFIG_DIR is a file → backup cannot write
if BG_CONFIG_DIR="$TMP/notadir" make -s -C "$ROOT" kind-down KIND="$TMP/kind" KIND_CLUSTER="$KIND_CLUSTER" >"$TMP/out3" 2>&1; then
  fail "kind-down succeeded although the backup failed"
fi
[[ ! -s $TMP/kind.calls ]] || fail "kind-down deleted the cluster after a failed backup: $(cat "$TMP/kind.calls")"
ok "kind-down aborts before delete when the backup fails"

# 4. kind-down stops before deleting the cluster when listing clusters fails (T22 R1)
cat > "$TMP/kind-broken" <<EOF
#!/usr/bin/env bash
case "\$1" in get) echo "ERROR: failed to list clusters" >&2; exit 1 ;; delete) echo "\$*" >> "$TMP/kind.calls" ;; esac
EOF
chmod +x "$TMP/kind-broken"
if BG_CONFIG_DIR="$TMP/cfg" make -s -C "$ROOT" kind-down KIND="$TMP/kind-broken" KIND_CLUSTER="$KIND_CLUSTER" >"$TMP/out4" 2>&1; then
  fail "kind-down succeeded although 'kind get clusters' failed"
fi
[[ ! -s $TMP/kind.calls ]] || fail "kind-down deleted the cluster without a backup: $(cat "$TMP/kind.calls")"
ok "kind-down aborts before delete when listing clusters fails"

# 5. check-platform accepts the fresh backup and rejects a stale one (T22 R2)
with_real_kubeconfig env BG_CONFIG_DIR="$TMP/cfg" "$ROOT/deploy/kind/check-platform.sh" >"$TMP/out5" 2>&1 \
  || fail "check-platform rejects a fresh backup: $(tail -3 "$TMP/out5")"
mkdir -p "$TMP/stale"
yq '.items[].data."tls.crt" = ("not-the-running-key" | @base64)' "$TMP/cfg/sealed-secrets-key.yaml" > "$TMP/stale/sealed-secrets-key.yaml"
cp "$TMP/cfg/sealed-secrets-cert.pem" "$TMP/stale/"
if with_real_kubeconfig env BG_CONFIG_DIR="$TMP/stale" "$ROOT/deploy/kind/check-platform.sh" >"$TMP/out6" 2>&1; then
  fail "check-platform accepted a stale Sealed Secrets key backup"
fi
grep -q 'Sealed Secrets backup is stale' "$TMP/out6" || fail "check-platform failed for another reason: $(tail -3 "$TMP/out6")"
ok "check-platform rejects a stale Sealed Secrets key backup"
echo "kind-test: all checks passed"
