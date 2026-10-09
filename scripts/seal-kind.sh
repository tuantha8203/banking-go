#!/usr/bin/env bash
# make seal: renders the kind Secrets from deploy/secrets/kind.env (git-ignored) and seals them with the cluster's
# Sealed Secrets cert into deploy/secrets/kind/<namespace>-<name>.sealed.yaml (spec §9, NFR-S7).
# Empty inputs are generated randomly and appended to kind.env. Plaintext never enters the repo.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
ENV_FILE=${BG_KIND_ENV:-$ROOT/deploy/secrets/kind.env}
CERT=${BG_SEAL_CERT:-${BG_CONFIG_DIR:-$HOME/.config/banking-go}/sealed-secrets-cert.pem}
OUT="$ROOT/deploy/secrets/kind"
[[ -s $CERT ]] || { echo "seal: no cert at $CERT — run 'make kind-platform' first (it backs up the controller key + cert)" >&2; exit 1; }
umask 077
touch "$ENV_FILE"
set -a; . "$ENV_FILE"; set +a

ensure() { # ensure VAR...: generate missing values and persist them
  local k
  for k in "$@"; do
    if [[ -z ${!k:-} ]]; then printf -v "$k" '%s' "$(openssl rand -hex 24)"; export "${k?}"; echo "$k=${!k}" >> "$ENV_FILE"; fi
  done
}
ensure PG_CORE_MIGRATOR_PASSWORD PG_CORE_APP_PASSWORD PG_PUBLIC_MIGRATOR_PASSWORD PG_PUBLIC_APP_PASSWORD \
       PG_ADMIN_MIGRATOR_PASSWORD PG_ADMIN_APP_PASSWORD RMQ_CORE_PASSWORD RMQ_PUBLIC_API_PASSWORD RMQ_ADMIN_API_PASSWORD \
       S3_ADMIN_ACCESS_KEY S3_ADMIN_SECRET_KEY S3_CORE_ACCESS_KEY S3_CORE_SECRET_KEY S3_PUBLIC_API_ACCESS_KEY S3_PUBLIC_API_SECRET_KEY

mkdir -p "$OUT"
seal() { # seal <namespace> <name> <kubectl create secret generic args...>; SEAL_LABEL=k=v labels the Secret
  local ns=$1 name=$2; shift 2
  kubectl create secret generic "$name" --namespace "$ns" "$@" --dry-run=client -o yaml \
    | if [[ -n ${SEAL_LABEL:-} ]]; then kubectl label --local -f - "$SEAL_LABEL" -o yaml; else cat; fi \
    | kubeseal --cert "$CERT" --format yaml > "$OUT/$ns-$name.sealed.yaml"
  echo "sealed $ns/$name"
}
PG=pg-rw.banking-data.svc:5432
RMQ=rmq.banking-data.svc:5672
dsn() { printf 'postgres://%s:%s@%s/%s?sslmode=require' "$1" "$2" "$PG" "$3"; }
amqp() { printf 'amqp://%s:%s@%s/banking' "$1" "$2" "$RMQ"; }

# banking-data: CNPG managed role passwords (basic-auth), RabbitMQ users, SeaweedFS S3 identities
for r in core:migrator core:app public:migrator public:app admin:migrator admin:app; do
  db=${r%%:*}; role=${r#*:}; var="PG_${db^^}_${role^^}_PASSWORD"
  seal banking-data "pg-$db-$role" --type=kubernetes.io/basic-auth \
    --from-literal=username="${db}_${role}" --from-literal=password="${!var}"
done
# User credential Secrets need this label or the Topology Operator (v1.20) webhook rejects the User.
TOPO=rabbitmq.com/topology-operator=true
SEAL_LABEL=$TOPO seal banking-data rmq-user-core --from-literal=username=core --from-literal=password="$RMQ_CORE_PASSWORD"
SEAL_LABEL=$TOPO seal banking-data rmq-user-public-api --from-literal=username=public-api --from-literal=password="$RMQ_PUBLIC_API_PASSWORD"
SEAL_LABEL=$TOPO seal banking-data rmq-user-admin-api --from-literal=username=admin-api --from-literal=password="$RMQ_ADMIN_API_PASSWORD"
s3cfg=$(jq -cn \
  --arg aa "$S3_ADMIN_ACCESS_KEY" --arg as "$S3_ADMIN_SECRET_KEY" \
  --arg ca "$S3_CORE_ACCESS_KEY" --arg cs "$S3_CORE_SECRET_KEY" \
  --arg pa "$S3_PUBLIC_API_ACCESS_KEY" --arg ps "$S3_PUBLIC_API_SECRET_KEY" \
  '{identities: [
     {name: "admin", credentials: [{accessKey: $aa, secretKey: $as}], actions: ["Admin", "Read", "Write", "List", "Tagging"]},
     {name: "core", credentials: [{accessKey: $ca, secretKey: $cs}], actions: ["Read:banking-kind", "List:banking-kind"]},
     {name: "public-api", credentials: [{accessKey: $pa, secretKey: $ps}], actions: ["Write:banking-kind"]}]}')
seal banking-data seaweedfs-s3-config --from-literal=seaweedfs_s3_config="$s3cfg"

# banking: migrator DSNs (PreSync Jobs) and runtime env (envFromSecrets)
seal banking core-migrator-dsn --from-literal=dsn="$(dsn core_migrator "$PG_CORE_MIGRATOR_PASSWORD" core)"
seal banking public-api-migrator-dsn --from-literal=dsn="$(dsn public_migrator "$PG_PUBLIC_MIGRATOR_PASSWORD" public)"
seal banking admin-api-migrator-dsn --from-literal=dsn="$(dsn admin_migrator "$PG_ADMIN_MIGRATOR_PASSWORD" admin)"
seal banking core-env \
  --from-literal=BG_CORE_DB_DSN="$(dsn core_app "$PG_CORE_APP_PASSWORD" core)" \
  --from-literal=BG_CORE_AMQP_URL="$(amqp core "$RMQ_CORE_PASSWORD")" \
  --from-literal=BG_CORE_S3_ACCESS_KEY_ID="$S3_CORE_ACCESS_KEY" --from-literal=BG_CORE_S3_SECRET_ACCESS_KEY="$S3_CORE_SECRET_KEY"
seal banking core-worker-env \
  --from-literal=BG_CORE_WORKER_DB_DSN="$(dsn core_app "$PG_CORE_APP_PASSWORD" core)" \
  --from-literal=BG_CORE_WORKER_AMQP_URL="$(amqp core "$RMQ_CORE_PASSWORD")" \
  --from-literal=BG_CORE_WORKER_S3_ACCESS_KEY_ID="$S3_CORE_ACCESS_KEY" --from-literal=BG_CORE_WORKER_S3_SECRET_ACCESS_KEY="$S3_CORE_SECRET_KEY"
seal banking public-api-env \
  --from-literal=BG_PUBLIC_API_DB_DSN="$(dsn public_app "$PG_PUBLIC_APP_PASSWORD" public)" \
  --from-literal=BG_PUBLIC_API_AMQP_URL="$(amqp public-api "$RMQ_PUBLIC_API_PASSWORD")" \
  --from-literal=BG_PUBLIC_API_S3_ACCESS_KEY_ID="$S3_PUBLIC_API_ACCESS_KEY" --from-literal=BG_PUBLIC_API_S3_SECRET_ACCESS_KEY="$S3_PUBLIC_API_SECRET_KEY"
seal banking admin-api-env \
  --from-literal=BG_ADMIN_API_DB_DSN="$(dsn admin_app "$PG_ADMIN_APP_PASSWORD" admin)" \
  --from-literal=BG_ADMIN_API_AMQP_URL="$(amqp admin-api "$RMQ_ADMIN_API_PASSWORD")"
# monitoring: Alertmanager config with the Telegram receiver (T16); skipped until the owner fills TELEGRAM_*.
if [[ -n ${TELEGRAM_BOT_TOKEN:-} && -n ${TELEGRAM_CHAT_ID:-} ]]; then
  # Telegram egress: TELEGRAM_PROXY_URL from kind.env, else the host's HTTPS proxy (kind pods have no proxy env);
  # set TELEGRAM_PROXY_URL= (empty) in kind.env to connect directly.
  export TELEGRAM_PROXY_URL=${TELEGRAM_PROXY_URL-${HTTPS_PROXY:-${https_proxy:-}}}
  echo "alertmanager telegram proxy: ${TELEGRAM_PROXY_URL:-none}"
  seal monitoring alertmanager-kind-config --from-file=alertmanager.yaml=<("$ROOT/scripts/render-alertmanager.sh")
else
  echo "skip monitoring/alertmanager-kind-config: set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in $ENV_FILE"
fi
"$ROOT/scripts/check-no-plain-secrets.sh"
