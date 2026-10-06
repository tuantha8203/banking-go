#!/usr/bin/env bash
# Downloads the CLIs pinned in tools/k8s-tools.lock into <bin-dir>, verifying sha256. No global install.
#   scripts/install-k8s-tools.sh ./bin
set -euo pipefail
BIN=${1:?usage: install-k8s-tools.sh <bin-dir>}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LOCK="$ROOT/tools/k8s-tools.lock"
[[ "$(uname -s)-$(uname -m)" == "Linux-x86_64" ]] || { echo "install-k8s-tools: only linux-amd64 is pinned in $LOCK" >&2; exit 1; }
mkdir -p "$BIN/helm-plugins"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT

while read -r name version sha url; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  file="$TMP/$(basename "$url")"
  curl -fsSL --retry 3 -o "$file" "$url"
  echo "$sha  $file" | sha256sum -c --quiet - || { echo "checksum mismatch for $name $version" >&2; exit 1; }
  v=${version#v}
  case "$name" in
    kubectl)  install -m 0755 "$file" "$BIN/kubectl" ;;
    helm)     tar -xzf "$file" -C "$TMP" linux-amd64/helm && install -m 0755 "$TMP/linux-amd64/helm" "$BIN/helm" ;;
    helm-unittest)
      rm -rf "$BIN/helm-plugins/unittest" && mkdir -p "$BIN/helm-plugins/unittest"
      tar -xzf "$file" -C "$BIN/helm-plugins/unittest" ;;
    promtool) tar -xzf "$file" -C "$TMP" "prometheus-$v.linux-amd64/promtool" && install -m 0755 "$TMP/prometheus-$v.linux-amd64/promtool" "$BIN/promtool" ;;
    amtool)   tar -xzf "$file" -C "$TMP" "alertmanager-$v.linux-amd64/amtool" && install -m 0755 "$TMP/alertmanager-$v.linux-amd64/amtool" "$BIN/amtool" ;;
    kubeseal) tar -xzf "$file" -C "$TMP" kubeseal && install -m 0755 "$TMP/kubeseal" "$BIN/kubeseal" ;;
    actionlint) tar -xzf "$file" -C "$TMP" actionlint && install -m 0755 "$TMP/actionlint" "$BIN/actionlint" ;;
    cosign)   install -m 0755 "$file" "$BIN/cosign" ;;
    gh)       tar -xzf "$file" -C "$TMP" "gh_${v}_linux_amd64/bin/gh" && install -m 0755 "$TMP/gh_${v}_linux_amd64/bin/gh" "$BIN/gh" ;;
    *) echo "install-k8s-tools: unknown tool $name" >&2; exit 1 ;;
  esac
  echo "installed $name $version"
done < "$LOCK"
