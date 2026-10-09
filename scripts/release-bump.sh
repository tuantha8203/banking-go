#!/usr/bin/env bash
# Writes deploy/releases/<env>.yaml for bg-release-bot (spec §4, "Thiết kế", D-23). Only main.yml runs it against the
# real file; humans and AI never edit deploy/releases/* (hook). Output is replaced atomically, untouched on error.
#   scripts/release-bump.sh <env> <git_sha> <gh_owner> <digests_dir> <out_file>
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
die() { echo "release-bump: $*" >&2; exit 1; }
[[ $# -eq 5 ]] || die "usage: release-bump.sh <env> <git_sha> <gh_owner> <digests_dir> <out_file>"
env=$1 sha=$2 owner=$3 dir=$4 out=$5
[[ $env =~ ^[a-z]+$ ]] || die "bad env $env"
[[ $sha =~ ^[0-9a-f]{40}$ ]] || die "git sha must be 40 lowercase hex chars"
[[ $owner =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "owner must be a lowercase GitHub login (GHCR)"
tmp=$(mktemp "$(dirname "$out")/.release-bump.XXXXXX")
trap 'rm -f "$tmp"' EXIT
{
  echo "# Written by bg-release-bot (.github/workflows/main.yml) for env $env. Do not edit; roll back with rollback.yml."
  echo "release: sha-${sha:0:7}"
  echo "gitSha: $sha"
  while read -r name image _rest; do
    [[ -z $name || $name == \#* ]] && continue
    [[ -f $dir/$image ]] || die "missing digest file $dir/$image"
    d=$(tr -d '[:space:]' < "$dir/$image")
    [[ $d =~ ^sha256:[0-9a-f]{64}$ ]] || die "bad digest for $image: $d"
    echo "$name:"
    echo "  image: ghcr.io/$owner/banking-go/$image"
    echo "  digest: $d"
  done < "$ROOT/deploy/deployables.tsv"
} > "$tmp"
mv "$tmp" "$out"
trap - EXIT
