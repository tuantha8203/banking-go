#!/usr/bin/env bash
# Validates the Collector config in deploy/collector/kind.yaml (.alternateConfig) with the pinned otelcol-contrib
# image, so an unknown component/key fails here and not in the cluster (AD-13, O-7).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
VALUES="$ROOT/deploy/collector/kind.yaml"
IMAGE="otel/opentelemetry-collector-contrib:$(yq '.image.tag' "$VALUES")"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
yq '.alternateConfig' "$VALUES" > "$TMP/config.yaml"; chmod 644 "$TMP/config.yaml"
docker run --rm -e MY_POD_IP=127.0.0.1 -v "$TMP/config.yaml:/etc/otelcol/config.yaml:ro" "$IMAGE" validate --config=/etc/otelcol/config.yaml
for pipeline in traces metrics logs; do
  for p in memory_limiter resource redaction batch; do
    yq -e ".service.pipelines.$pipeline.processors | contains([\"$p\"])" "$TMP/config.yaml" >/dev/null \
      || { echo "FAIL: $pipeline pipeline lacks processor $p" >&2; exit 1; }
  done
done
[[ $(yq '.processors.resource.attributes[] | select(.key == "env") | .value' "$TMP/config.yaml") == kind ]] \
  || { echo "FAIL: resource processor must set env=kind" >&2; exit 1; }
echo "ok   collector config valid ($IMAGE)"
