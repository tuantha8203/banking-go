#!/usr/bin/env bash
# Asserts the kind add-ons are installed and healthy (spec §8). One section per wave group; later tasks append.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }
ready() { kubectl get "$@" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'; }
require_kind_context

# --- waves -30/-20/-19/-18: CRDs, controllers, issuers, gateway
v=$(kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}' || true)
[[ $v == v1.6.2 ]] || fail "Gateway API CRDs bundle-version=$v (want v1.6.2)"; ok "Gateway API CRDs $v"
for d in cert-manager/cert-manager traefik/traefik cnpg-system/cloudnative-pg kube-system/sealed-secrets-controller \
         rabbitmq-system/rabbitmq-cluster-operator rabbitmq-system/messaging-topology-operator; do
  kubectl -n "${d%%/*}" rollout status "deploy/${d#*/}" --timeout=180s >/dev/null || fail "deployment $d not available"
  ok "deployment $d"
done
for ci in selfsigned kind-ca bg-internal-ca; do
  [[ $(ready clusterissuer "$ci") == True ]] || fail "ClusterIssuer $ci not Ready"; ok "ClusterIssuer $ci"
done
[[ $(ready -n traefik certificate wildcard-kind-localhost) == True ]] || fail "Certificate traefik/wildcard-kind-localhost not Ready"
[[ $(kubectl -n traefik get gateway traefik-gateway -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}') == True ]] \
  || fail "Gateway traefik/traefik-gateway not Programmed"; ok "Gateway traefik-gateway Programmed"
issuer=$(curl -skv --max-time 10 https://probe.kind.localhost/ 2>&1 | grep -i 'issuer:' || true)
[[ $issuer == *"banking-go kind root CA"* ]] || fail "TLS on :443 is not issued by the kind CA ($issuer)"
code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 https://probe.kind.localhost/)
[[ $code == 404 ]] || fail "Traefik on :443 answered $code for an unknown host (want 404)"; ok "Traefik serves *.kind.localhost with the kind CA"
key_backup=${BG_CONFIG_DIR:-$HOME/.config/banking-go}/sealed-secrets-key.yaml
[[ -s $key_backup ]] || fail "Sealed Secrets key not backed up"
running=$(kubectl -n kube-system get secret -l sealedsecrets.bitnami.com/sealed-secrets-key \
  -o jsonpath='{range .items[*]}{.data.tls\.crt}{"\n"}{end}' | sort)
saved=$(yq '.items[].data."tls.crt"' "$key_backup" | sort)
[[ -n $running && $running == "$saved" ]] || fail "Sealed Secrets backup is stale: $key_backup does not hold the running key(s) (run deploy/kind/sealed-key.sh backup)"
ok "Sealed Secrets key backed up (matches the running key)"

# --- waves -18/-15/-14: secrets + data
"$ROOT/scripts/check-no-plain-secrets.sh"
[[ $(kubectl -n banking-data get cluster.postgresql.cnpg.io pg -o jsonpath='{.status.phase}') == "Cluster in healthy state" ]] \
  || fail "CNPG cluster banking-data/pg not healthy"
psqlq() { kubectl -n banking-data exec pg-1 -c postgres -- psql -U postgres -tAc "$1"; }
roles=$(psqlq "select string_agg(rolname, ',' order by rolname) from pg_roles where rolname ~ '^(core|public|admin)_(migrator|app)\$'")
[[ $roles == admin_app,admin_migrator,core_app,core_migrator,public_app,public_migrator ]] || fail "pg roles: $roles"
dbs=$(psqlq "select string_agg(datname || ':' || pg_get_userbyid(datdba), ',' order by datname) from pg_database where datname in ('core','public','admin')")
[[ $dbs == admin:admin_migrator,core:core_migrator,public:public_migrator ]] || fail "pg databases: $dbs"
ok "postgres pg: databases + 6 managed roles"
rmqctl() { kubectl -n banking-data exec rmq-server-0 -c rabbitmq -- rabbitmqctl --quiet --no-table-headers "$@"; }
ex=$(rmqctl list_exchanges --vhost banking name type)
for e in $'banking.events\ttopic' $'banking.commands\tdirect' $'banking.dlx\tdirect' \
         $'banking.retry.1\tfanout' $'banking.retry.2\tfanout' $'banking.retry.3\tfanout'; do
  grep -qxF "$e" <<<"$ex" || fail "exchange missing: ${e//$'\t'/ }"
done
q=$(rmqctl list_queues --vhost banking name arguments)
grep -E '^banking\.retry\.1[[:space:]].*x-message-ttl.*10000' <<<"$q" >/dev/null || fail "banking.retry.1 TTL 10s missing"
users=$(rmqctl list_users)
for u in core public-api admin-api; do grep -q "^$u[[:space:]]" <<<"$users" || fail "rabbitmq user $u missing"; done
ok "rabbitmq rmq: exchanges, retry queues, users"
pod=$(kubectl -n banking-data get pods -l app.kubernetes.io/name=seaweedfs -o name | head -1)
kubectl -n banking-data exec "$pod" -- sh -c 'echo s3.bucket.list | weed shell' 2>/dev/null | grep -q banking-kind \
  || fail "SeaweedFS bucket banking-kind missing"
ok "seaweedfs bucket banking-kind"
