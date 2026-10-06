# Platform v1 Implementation Plan

> **For agentic workers:** Implement one task at a time with `/write-tests` then `/implement` (next task from `scripts/sprint.sh next`). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mỗi commit lên `main` được đóng gói (6 image ký + SBOM trên GHCR), digest ghi vào `deploy/releases/kind.yaml`, và Argo CD triển khai lên cluster `kind` trên máy dev cùng add-on platform + observability as code — kiểm chứng GitOps, rollback, telemetry trước v2 (VPS) và v3 (AWS).

**Architecture:** Một library chart `deploy/helm/_lib` là nơi duy nhất có template K8s; 10 chart mỏng chỉ có values. Add-on và app của env `kind` khai báo một lần trong catalog `deploy/argocd/kind/values.yaml` (chart + version + values + sync-wave): S1/S2 cài bằng `helm`/`kubectl` trực tiếp từ catalog đó (`scripts/kind-platform.sh`, `scripts/kind-apps.sh`) để chạy được khi chưa có GitHub; S3 đổi sang app-of-apps Argo CD đọc đúng catalog ấy, image lấy theo digest từ `deploy/releases/kind.yaml` do bot ghi. Observability as code: rule Prometheus/dashboard JSON trong `observability/` được sinh thành `PrometheusRule`/ConfigMap bằng `scripts/gen-observability.sh`.

**Tech Stack:** Go 1.27.1, goose v3.28.0, pgx v5.11.0, testcontainers-go v0.44.0; Docker buildx; distroless static-debian12, nginx-unprivileged 1.30.5; kind v0.33.0 (kindest/node v1.36.4), kubectl v1.36.5, Helm v4.3.0, helm-unittest v1.2.1, kubeconform v0.8.0, yq v4.54.1, promtool v3.15.0, amtool v0.34.1, kubeseal v0.40.0, actionlint v1.7.12; Argo CD v3.5.3 (chart 10.9.6), Gateway API v1.6.2, cert-manager v1.21.2, Sealed Secrets v0.40.0 (chart 2.20.0), Traefik v3.7.13 (chart 41.6.1), CloudNativePG 1.30.1 (chart 0.29.1), RabbitMQ Cluster Operator v2.23.0 + Messaging Topology Operator v1.20.3, RabbitMQ 4.3.6, PostgreSQL 18.6, SeaweedFS 4.48 (chart 4.48.0), kube-prometheus-stack 91.9.0 (+ prometheus-operator-crds 32.0.1), Grafana 12.4.12, Jaeger 2.21.0 (chart 4.14.1), otelcol-contrib 0.162.0 (chart opentelemetry-collector 0.175.1); GitHub Actions (checkout v7, setup-go v7, setup-buildx v4, build-push v7, login v4, sbom-action v0.24.3 + syft v1.54.0, cosign-installer v4.1.2 + cosign v3.1.3, create-github-app-token v3, upload-artifact v7, download-artifact v8), Trivy 0.75.0.

**Spec:** `docs/features/platform/v1/spec.md` (đọc cùng plan này). Nguồn liên quan: `docs/foundation/deployment.md`, `docs/foundation/observability.md`, `docs/adr/0011-moi-truong-kind-cho-gitops-local.md`, spine AD-13, AD-14, AD-26, Stack.

## Global Constraints

- Phạm vi image (spec §1): 6 image cho 10 deployable — `core` (binary `core`, `core-worker`), `public-api`, `admin-api`, `mocks` (4 binary), `web-customer`, `web-admin`. Go: multi-stage → `gcr.io/distroless/static-debian12:nonroot`, `CGO_ENABLED=0`, `-trimpath`, version/commit qua ldflags. SPA: build Vite → `nginxinc/nginx-unprivileged`, `config.js` runtime từ ConfigMap.
- `migrate up` cho `core`, `public-api`, `admin-api`: goose với migration embed (`services/<svc>/migrations`), DSN của role migrator; không có migration nào thì no-op thành công (D-25).
- Interface chart (spec "Thiết kế"): `image.repository`, `command`, `ports.app`, `ports.admin`, `replicas`, `resources`, `env`, `envFromSecrets`, `route.{enabled,host,pathPrefix}`, `migration.{enabled,dsnSecret}`, `mtls.enabled`, `shutdownTimeoutSeconds`. Digest: `image.digest` từ `deploy/releases/<env>.yaml` (khóa = tên deployable).
- `deploy/releases/kind.yaml`: `{ <deployable>: { image: ghcr.io/<GH_OWNER>/banking-go/<image>, digest: sha256:… } }`. `GH_OWNER` là biến duy nhất: Makefile `GH_OWNER ?=`, values `global.ghOwner`, `repoURL` Argo CD (bootstrap điền từ nó). GHCR yêu cầu chữ thường → luôn dùng `${GH_OWNER,,}`.
- Host trên kind: `api.`, `admin-api.`, `app.`, `admin.`, `grafana.`, `jaeger.`, `argocd.`, `rabbitmq.` + `.kind.localhost`.
- kind: k8s 1.36 (`kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed`, kind v0.33.0), 1 CP + 2 worker, 80/443 ra host. RAM ~6–7 GB → request thấp, 1 replica trên kind.
- Không Bitnami chart/image (AD-14), ngoại lệ duy nhất: image controller Sealed Secrets (D-8). Chart Sealed Secrets lấy từ repo của project: `https://bitnami.github.io/sealed-secrets` (repo GitHub đã chuyển `bitnami-labs` → `bitnami`, URL cũ trả 404).
- Rolling update (deployment.md): `maxUnavailable: 0`, `maxSurge: 1`, `minReadySeconds: 10`, `progressDeadlineSeconds: 300`, `preStop` sleep 5 s, `terminationGracePeriodSeconds` = `shutdownTimeoutSeconds` + 15 (30 → 45, AD-26), `/livez` `/readyz` trên admin port.
- Migration: PreSync Job (`argocd.argoproj.io/hook: PreSync`, `hook-delete-policy: BeforeHookCreation`, sync-wave `-1`), cùng image digest, lệnh `<svc> migrate up`, role `<svc>_migrator`; `lock_timeout = 5s` (D-27); chạy lại an toàn.
- Config: env `BG_<SERVICE>_<KEY>`; key mới thêm vào `.env.example`. `OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability.svc:4317` trên kind. Telemetry chỉ OTLP (AD-13).
- Secret: chỉ `deploy/secrets/kind/*.sealed.yaml` trong Git; plaintext ở `deploy/secrets/kind.env` (git-ignored, 0600); key controller ở `~/.config/banking-go/` (ngoài repo). Không có `kind: Secret` thường trong `deploy/`.
- Observability: alert rule Prometheus-format trong `observability/alerts/` (nhãn `severity`, `service`, `runbook_url`), dashboard JSON Grafana 12.4 trong `observability/dashboards/` với datasource uid cố định `prom`, `traces`; Alertmanager → Telegram cho `critical` + `Watchdog`.
- Hands off: `services/*/internal/**` (chỉ được thêm `cmd/*` phần `migrate` và wiring version), `docs/foundation/**`, `infra/**`, `pkg/gen/**`, `services/*/api/openapi/**`. `deploy/releases/*.yaml` chỉ do bot `bg-release-bot` ghi — không task nào sửa tay (hook chặn).
- S1/S2 cài add-on/app bằng `helm`/`kubectl` trực tiếp là **đường tạm chỉ cho kind** (chưa có GitHub); S3 thay bằng Argo CD. Không áp dụng cách này cho môi trường khác.
- Tool k8s chỉ nằm trong `./bin` (pin + kiểm sha256 hoặc `go tool` trong `tools/go.mod`); không cài global. Mọi lệnh trong plan gọi `bin/<tool>` hoặc qua `make`.
- Commit: Conventional Commits scope `platform` (`feat(platform): …`, `test(platform): …`, `ci(platform): …`, `docs(platform): …`), mỗi task 1 commit; văn xuôi tiếng Việt, code/identifier tiếng Anh.

## Bố cục file (khóa quyết định phân rã)

| Đường dẫn | Trách nhiệm | Task |
|---|---|---|
| `tools/go.mod`, `tools/k8s-tools.lock`, `scripts/install-k8s-tools.sh`, `scripts/check-k8s-tools.sh` | Pin + cài CLI k8s/devops vào `./bin` | T1 |
| `pkg/migrate/`, `services/{core,public-api,admin-api}/migrations/embed.go`, `services/*/cmd/*/migrate.go` | `migrate up` (goose embed) | T2 |
| `deploy/docker/go.Dockerfile`, `.dockerignore`, `deploy/deployables.tsv`, `scripts/image-smoke.sh` | Image Go + bảng deployable → image/command/port (nguồn duy nhất cho script) | T3 |
| `deploy/docker/spa.Dockerfile`, `deploy/docker/nginx/*`, `packages/runtime-config/` | Image SPA + `config.js` runtime | T4 |
| `deploy/helm/_lib/` | Library chart (template K8s duy nhất) | T5, T6 |
| `deploy/helm/_libtest/` | Chart fixture cho helm-unittest của lib (không deploy) | T5, T6 |
| `deploy/helm/<deployable>/` × 10 | Chart mỏng: `values.yaml`, `values-kind.yaml`, `templates/all.yaml` (1 dòng include) | T7 |
| `deploy/kind/` | `kind-config.yaml`, `bootstrap.sh`, `sealed-key.sh`, `check-cluster.sh`, `check-platform.sh`, `root.yaml`, `wait-argocd.sh` | T8–T13, T21 |
| `deploy/argocd/kind/values.yaml` | Catalog add-on + app của env kind (chart, version, values, wave) — đọc bởi script (S1/S2) và chart app-of-apps (S3) | T9→T21 |
| `deploy/argocd/kind/{Chart.yaml,templates/}` | Chart app-of-apps | T21 |
| `deploy/platform/<addon>/values-kind.yaml`, `deploy/platform/<addon>/*.yaml` (vendored, khóa sha256 trong `deploy/platform/vendor.lock`) | Add-on platform | T9, T10, T13 |
| `deploy/messaging/` | Topology RabbitMQ (CR Messaging Topology Operator) | T10 |
| `deploy/secrets/kind/*.sealed.yaml`, `deploy/secrets/kind.env.example`, `scripts/seal-kind.sh` | Secret kind | T10, T16, T21 |
| `deploy/collector/kind.yaml` | Values chart Collector (config đầy đủ trong `alternateConfig`) | T13 |
| `observability/alerts/`, `observability/dashboards/`, `observability/alertmanager/`, `observability/runbooks/` | Observability as code | T14–T17 |
| `deploy/platform/observability/kind/` | `PrometheusRule`/ConfigMap dashboard **sinh ra** + scrape config viết tay | T14, T15 |
| `scripts/kind-platform.sh`, `scripts/kind-apps.sh`, `scripts/kind-smoke.sh`, `scripts/kind-watch.sh`, `scripts/lib/kind.sh` | Vận hành kind | T8–T17 |
| `.github/workflows/{ci,main,rollback}.yml`, `scripts/release-bump.sh`, `scripts/rollback-check.sh` | Pipeline | T18–T20 |

Quy ước tên trên cluster:

| Thứ | Giá trị |
|---|---|
| Cluster / context | `banking-go` / `kind-banking-go` |
| Namespace | `banking` (app), `banking-data` (pg, rmq, seaweedfs, topology), `observability` (collector, jaeger), `monitoring` (kube-prometheus-stack), `argocd`, `cert-manager`, `traefik`, `cnpg-system`, `rabbitmq-system`, `kube-system` (sealed-secrets) |
| Gateway | `traefik/traefik-gateway`, listener `websecure` (8443, `*.kind.localhost`, secret `wildcard-kind-localhost-tls`), `web` (8000) |
| ClusterIssuer | `selfsigned`, `kind-ca` (CA cho `*.kind.localhost`), `bg-internal-ca` (CA nội bộ mTLS) |
| DNS dịch vụ | `pg-rw.banking-data.svc:5432`, `rmq.banking-data.svc:5672` (vhost `banking`), `otel-collector.observability.svc:4317`, `jaeger.observability.svc:{4317,16686}`, `kube-prometheus-stack-prometheus.monitoring.svc:9090`, `kube-prometheus-stack-grafana.monitoring.svc:80`, `kube-prometheus-stack-alertmanager.monitoring.svc:9093` |
| Image local (S1/S2) | `banking-go/<image>:local` |

## Danh sách task

Sprint S1 — "Image + chart chạy trên kind (cài bằng helm trực tiếp, chưa cần GitHub)"
- [ ] T1: Pin CLI k8s/devops vào `./bin` (`make tools-k8s`)
- [ ] T2: Subcommand `migrate up` (goose, migration embed) cho core/public-api/admin-api
- [ ] T3: Dockerfile Go (core + core-worker, public-api, admin-api, mocks × 4) + `make images` + `make image-smoke`
- [ ] T4: Dockerfile SPA + nginx + `config.js` runtime (`@banking-go/runtime-config`)
- [ ] T5: Library chart phần 1 (Deployment, Service, ServiceAccount, ConfigMap) + helm-unittest
- [ ] T6: Library chart phần 2 (HTTPRoute, PDB, migration PreSync Job, Certificate mTLS) + helm-unittest
- [ ] T7: 10 chart mỏng + `values-kind.yaml` + `make helm-lint helm-test` (kubeconform k8s 1.36 + CRD catalog)
- [ ] T8: kind config + `bootstrap.sh` (idempotent, khôi phục key Sealed Secrets, Argo CD) + `make kind-up kind-down`
- [ ] T9: Add-on wave -30/-20/-19/-18 (Gateway API, cert-manager + ClusterIssuer, Sealed Secrets, Traefik, CNPG op, RabbitMQ ops) + catalog + `make kind-platform kind-ca`
- [ ] T10: Data wave -15/-14 (CNPG `Cluster pg`, `RabbitmqCluster`, topology, SeaweedFS + bucket) + Sealed Secrets + `make seal`
- [ ] T11: `make kind-load kind-apps` — 10 chart chạy trên kind, Job migration Completed
- [ ] T12: `make kind-smoke` (4 host qua Traefik, Job migration, digest vs `deploy/releases/kind.yaml`)

Sprint S2 — "Observability as code trên kind"
- [ ] T13: kube-prometheus-stack + Jaeger v2 + OTel Collector (`deploy/collector/kind.yaml`) + route vận hành + smoke telemetry
- [ ] T14: Alert rule v1 + recording rule SLI + promtool unit test + `PrometheusRule` sinh ra
- [ ] T15: Dashboard `service-overview` + `platform` + scrape CNPG/RabbitMQ/Argo CD + test
- [ ] T16: Alertmanager → Telegram (critical + Watchdog) từ Sealed Secret + `amtool` test
- [ ] T17: Runbook + `make kind-watch`

Sprint S3 — "GitOps + pipeline thật (cần repo GitHub; owner làm các bước tay trước)"
- [ ] T18: `ci.yml`: build 6 image (không push), deploy lint/test, observability test, actionlint
- [ ] T19: `main.yml`: build → Trivy → push → SBOM + cosign → bot bump `deploy/releases/kind.yaml`
- [ ] T20: `rollback.yml` (env=kind, revert_sha)
- [ ] T21: Argo CD app-of-apps `deploy/argocd/kind/` + bootstrap GitOps + nghiệm thu tiêu chí 1–6

---

# Sprint S1 — Image + chart chạy trên kind (cài bằng helm trực tiếp, chưa cần GitHub)

**Sprint goal:** từ máy sạch, `make tools-k8s images image-smoke helm-lint helm-test kind-up kind-platform seal kind-load kind-apps kind-smoke` cho cluster kind 1.36 có add-on platform + data và 10 deployable Ready, 4 host trả 200 qua Traefik. **Demo:** `curl -k https://api.kind.localhost/v1/ping` → `{"status":"ok"}`, mở `https://app.kind.localhost`.

### T1: Pin CLI k8s/devops vào `./bin` (`make tools-k8s`)

**Files:**
- Modify: `tools/go.mod`, `tools/go.sum` (qua `go get -tool`, không sửa tay)
- Create: `tools/k8s-tools.lock`, `scripts/install-k8s-tools.sh`, `scripts/check-k8s-tools.sh`
- Modify: `Makefile` (biến tool, `TOOL_STAMP`, target `tools-k8s`)

**Interfaces:**
- Consumes: target `tools` hiện có (`$(TOOL_STAMP)`), biến `BIN`.
- Produces: binary `bin/{kind,kubectl,helm,kubeconform,yq,promtool,amtool,kubeseal,actionlint,cosign,gh}`, plugin `bin/helm-plugins/unittest`; biến Makefile `KIND KUBECTL HELM KUBECONFORM YQ PROMTOOL AMTOOL KUBESEAL ACTIONLINT COSIGN GH`, `export HELM_PLUGINS := $(BIN)/helm-plugins`; target `make tools-k8s`. Mọi script sau dùng `export PATH="$ROOT/bin:$PATH"`.

Version đã kiểm ngày 2026-10-06 (`https://github.com/<org>/<repo>/releases/latest`, Docker Hub, proxy.golang.org): kind v0.33.0, kubectl v1.36.5 (`dl.k8s.io/release/stable-1.36.txt`), helm v4.3.0, kubeconform v0.8.0, helm-unittest v1.2.1, yq v4.54.1, prometheus v3.15.0 (promtool), alertmanager v0.34.1 (amtool), sealed-secrets v0.40.0 (kubeseal), actionlint v1.7.12, cosign v3.1.3 và gh v2.102.0 (cho nghiệm thu S3: `cosign verify`, `gh run watch`; máy dev chưa có `gh`). `go tool` cho tool thuần Go nhẹ (kind, kubeconform, actionlint, yq); tải + sha256 cho tool kéo client-go/Prometheus nặng hoặc phát hành dạng binary (kubectl, helm, promtool, amtool, kubeseal, cosign, gh) và plugin helm-unittest.

- [ ] **Step 1: Viết check thất bại** — `scripts/check-k8s-tools.sh`

```bash
#!/usr/bin/env bash
# Asserts every pinned k8s/devops CLI in ./bin has the expected version (platform v1 T1).
set -euo pipefail
B=${1:-bin}
fail() { echo "FAIL: $*" >&2; exit 1; }
expect() { # expect <regex> <cmd...>
  local want=$1 out; shift
  out=$("$@" 2>&1) || fail "$* did not run: $out"
  grep -Eq -- "$want" <<<"$out" || fail "$*: want /$want/ in: $out"
  echo "ok   $1 → $want"
}
expect 'kind v0\.33\.0'                       "$B/kind" version
expect 'Client Version: v1\.36\.5'            "$B/kubectl" version --client
expect '^v4\.3\.0'                            "$B/helm" version --short
expect 'kubeconform[[:space:]]+v0\.8\.0'      go version -m "$B/kubeconform"
expect 'version v?4\.54\.1'                   "$B/yq" --version
expect 'promtool, version 3\.15\.0'           "$B/promtool" --version
expect 'amtool, version 0\.34\.1'             "$B/amtool" --version
expect '0\.40\.0'                             "$B/kubeseal" --version
expect '1\.7\.12'                             "$B/actionlint" -version
expect 'unittest[[:space:]]+1\.2\.1'          env HELM_PLUGINS="$B/helm-plugins" "$B/helm" plugin list
expect 'v3\.1\.3'                             "$B/cosign" version
expect 'gh version 2\.102\.0'                 "$B/gh" --version
echo "all k8s tools pinned"
```

- [ ] **Step 2: Chạy để thấy fail**

Run: `chmod +x scripts/check-k8s-tools.sh && scripts/check-k8s-tools.sh`
Expected: `FAIL: bin/kind version did not run: …No such file or directory` (exit 1).

- [ ] **Step 3: Thêm tool Go vào `tools/go.mod`**

Run:
```bash
cd tools && GOWORK=off go get -tool sigs.k8s.io/kind@v0.33.0 github.com/yannh/kubeconform/cmd/kubeconform@v0.8.0 \
  github.com/rhysd/actionlint/cmd/actionlint@v1.7.12 github.com/mikefarah/yq/v4@v4.54.1 && GOWORK=off go mod tidy
```
Expected: khối `tool (…)` có thêm 4 dòng; `go.sum` cập nhật.

- [ ] **Step 4: Tạo `tools/k8s-tools.lock`**

```text
# Pinned k8s/devops CLIs downloaded into ./bin by scripts/install-k8s-tools.sh (linux-amd64 only).
# name         version  sha256                                                            url
kubectl        v1.36.5  33bc88a24c3b09cf55bfd59e6ca977881b61fc3f25ab65bc80c65b430248648e  https://dl.k8s.io/release/v1.36.5/bin/linux/amd64/kubectl
helm           v4.3.0   86584a54def73570558f66f5111cc53dfed56689637ae32c1201205d494f54fb  https://get.helm.sh/helm-v4.3.0-linux-amd64.tar.gz
helm-unittest  v1.2.1   48e86ecc1467b009630e5954375e5d8494139f73b466df5fe8c04fa45b634939  https://github.com/helm-unittest/helm-unittest/releases/download/v1.2.1/helm-unittest-linux-amd64-1.2.1.tgz
promtool       v3.15.0  2a542df32eac02ee17b9d844fb2aa1de00dafa5476579ba8a3ba862e9d572ea0  https://github.com/prometheus/prometheus/releases/download/v3.15.0/prometheus-3.15.0.linux-amd64.tar.gz
amtool         v0.34.1  265b9d1e55ef0d5306a436018af6d2b686c2ce051f03d968f7464ecb1372a7e8  https://github.com/prometheus/alertmanager/releases/download/v0.34.1/alertmanager-0.34.1.linux-amd64.tar.gz
kubeseal       v0.40.0  9314c35916646e9d59c8f06b1314574b4e79c4d76f079433607ed7b697bb5eb7  https://github.com/bitnami/sealed-secrets/releases/download/v0.40.0/kubeseal-0.40.0-linux-amd64.tar.gz
cosign         v3.1.3   4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71  https://github.com/sigstore/cosign/releases/download/v3.1.3/cosign-linux-amd64
gh             v2.102.0 bb766f710eef8ede859c18578c72c327597cd4c8a85b06001b1f3843c6019386  https://github.com/cli/cli/releases/download/v2.102.0/gh_2.102.0_linux_amd64.tar.gz
```

- [ ] **Step 5: Tạo `scripts/install-k8s-tools.sh`**

```bash
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
    cosign)   install -m 0755 "$file" "$BIN/cosign" ;;
    gh)       tar -xzf "$file" -C "$TMP" "gh_${v}_linux_amd64/bin/gh" && install -m 0755 "$TMP/gh_${v}_linux_amd64/bin/gh" "$BIN/gh" ;;
    *) echo "install-k8s-tools: unknown tool $name" >&2; exit 1 ;;
  esac
  echo "installed $name $version"
done < "$LOCK"
```

- [ ] **Step 6: Sửa `Makefile`** — thay khối `TOOL_STAMP` hiện có và thêm biến/target ngay dưới `.PHONY: tools`:

```make
TOOL_STAMP := $(BIN)/.tools-stamp
$(TOOL_STAMP): tools/go.mod tools/go.sum
	cd tools && GOWORK=off go build -o $(BIN)/ \
		github.com/bufbuild/buf/cmd/buf \
		github.com/sqlc-dev/sqlc/cmd/sqlc \
		github.com/pressly/goose/v3/cmd/goose \
		google.golang.org/protobuf/cmd/protoc-gen-go \
		google.golang.org/grpc/cmd/protoc-gen-go-grpc \
		sigs.k8s.io/kind \
		github.com/yannh/kubeconform/cmd/kubeconform \
		github.com/rhysd/actionlint/cmd/actionlint \
		github.com/mikefarah/yq/v4
	@touch $@

.PHONY: tools
tools: $(TOOL_STAMP) ## Build pinned Go tools into ./bin

# k8s/devops CLIs (platform v1): Go tools above + checksum-verified downloads (tools/k8s-tools.lock).
KIND        := $(BIN)/kind
KUBECTL     := $(BIN)/kubectl
HELM        := $(BIN)/helm
KUBECONFORM := $(BIN)/kubeconform
YQ          := $(BIN)/yq
PROMTOOL    := $(BIN)/promtool
AMTOOL      := $(BIN)/amtool
KUBESEAL    := $(BIN)/kubeseal
ACTIONLINT  := $(BIN)/actionlint
COSIGN      := $(BIN)/cosign
GH          := $(BIN)/gh
export HELM_PLUGINS := $(BIN)/helm-plugins

K8S_TOOLS_STAMP := $(BIN)/.k8s-tools-stamp
$(K8S_TOOLS_STAMP): tools/k8s-tools.lock scripts/install-k8s-tools.sh
	scripts/install-k8s-tools.sh $(BIN)
	@touch $@

.PHONY: tools-k8s
tools-k8s: $(TOOL_STAMP) $(K8S_TOOLS_STAMP) ## Pinned kind/kubectl/helm(+unittest)/kubeconform/yq/promtool/amtool/kubeseal/actionlint/cosign/gh in ./bin
```

- [ ] **Step 7: Chạy để thấy pass**

Run: `chmod +x scripts/install-k8s-tools.sh && make tools-k8s && scripts/check-k8s-tools.sh`
Expected: 12 dòng `ok …`, cuối `all k8s tools pinned`.

- [ ] **Step 8: Kiểm tool cũ không đổi hành vi**

Run: `make lint-proto && make gen && git diff --exit-code -- pkg/gen services/public-api/api/openapi services/admin-api/api/openapi`
Expected: exit 0 (MVS có thể nâng dep chung trong `tools/go.mod`, code sinh ra không đổi).

- [ ] **Step 9: Commit**

```bash
git add tools/go.mod tools/go.sum tools/k8s-tools.lock scripts/install-k8s-tools.sh scripts/check-k8s-tools.sh Makefile
git commit -m "feat(platform): pin k8s/devops CLIs into ./bin via make tools-k8s"
```

**Lệnh kiểm chứng:** `make tools-k8s && scripts/check-k8s-tools.sh`

---

### T2: Subcommand `migrate up` (goose, migration embed)

**Files:**
- Create: `pkg/migrate/migrate.go`, `pkg/migrate/migrate_test.go`, `pkg/migrate/migrate_integration_test.go`
- Create: `services/core/migrations/embed.go`, `services/public-api/migrations/embed.go`, `services/admin-api/migrations/embed.go`
- Create: `services/core/cmd/core/migrate.go`, `services/core/cmd/core/migrate_test.go`, `services/public-api/cmd/public-api/migrate.go`, `services/public-api/cmd/public-api/migrate_test.go`, `services/admin-api/cmd/admin-api/migrate.go`, `services/admin-api/cmd/admin-api/migrate_test.go`
- Modify: `services/core/cmd/core/main.go`, `services/public-api/cmd/public-api/main.go`, `services/admin-api/cmd/admin-api/main.go` (dispatch `migrate`)
- Modify: `pkg/go.mod`, `pkg/go.sum`, `services/*/go.mod`, `services/*/go.sum` (qua `go get` / `go mod tidy`)
- Modify: `.env.example`

**Interfaces:**
- Consumes: `config.Load[T](service string, cfg T) (T, error)` (`pkg/config`), `buildinfo.Version`.
- Produces: `func migrate.Up(ctx context.Context, dsn string, fsys fs.FS, log *slog.Logger) error`; `const migrate.LockTimeout = "5s"`; `var migrations.FS embed.FS` trong `banking-go/services/{core,public-api,admin-api}/migrations`; CLI `<svc> migrate up` đọc `BG_CORE_MIGRATOR_DSN` / `BG_PUBLIC_API_MIGRATOR_DSN` / `BG_ADMIN_API_MIGRATOR_DSN` (bắt buộc, không rỗng). Lib chart (T6) gọi `[<command[0]>, "migrate", "up"]` và đặt env `BG_<SVC>_MIGRATOR_DSN`.

- [ ] **Step 1: Thêm dependency**

Run:
```bash
cd pkg && go get github.com/pressly/goose/v3@v3.28.0 github.com/jackc/pgx/v5@v5.11.0 \
  github.com/testcontainers/testcontainers-go@v0.44.0 github.com/testcontainers/testcontainers-go/modules/postgres@v0.44.0
```
Expected: `pkg/go.mod` có 4 require mới.

- [ ] **Step 2: Viết unit test thất bại** — `pkg/migrate/migrate_test.go`

```go
package migrate

import (
	"log/slog"
	"strings"
	"testing"
	"testing/fstest"
)

// unreachableDSN points at a closed port: a no-op Up must never dial it.
const unreachableDSN = "postgres://core_migrator:x@127.0.0.1:1/core?connect_timeout=1"

func TestUpWithoutMigrationFilesIsNoop(t *testing.T) {
	fsys := fstest.MapFS{
		"embed.go": {Data: []byte("package migrations\n")},
		".gitkeep": {Data: nil},
	}
	if err := Up(t.Context(), unreachableDSN, fsys, slog.New(slog.DiscardHandler)); err != nil {
		t.Fatalf("Up with no migrations = %v, want nil", err)
	}
}

func TestUpRejectsEmptyDSN(t *testing.T) {
	err := Up(t.Context(), "  ", fstest.MapFS{}, slog.New(slog.DiscardHandler))
	if err == nil || !strings.Contains(err.Error(), "empty DSN") {
		t.Fatalf("Up(empty DSN) = %v, want empty DSN error", err)
	}
}

func TestUpRejectsMalformedDSN(t *testing.T) {
	err := Up(t.Context(), "postgres://%zz", fstest.MapFS{}, slog.New(slog.DiscardHandler))
	if err == nil || !strings.Contains(err.Error(), "parse DSN") {
		t.Fatalf("Up(malformed DSN) = %v, want parse DSN error", err)
	}
}
```

- [ ] **Step 3: Viết integration test** — `pkg/migrate/migrate_integration_test.go`

```go
//go:build integration

package migrate

import (
	"log/slog"
	"testing"
	"testing/fstest"

	"github.com/jackc/pgx/v5"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
)

func TestUpAppliesOnceAndIsSafeToRerun(t *testing.T) {
	ctx := t.Context()
	pg, err := postgres.Run(ctx, "postgres:18.6",
		postgres.WithDatabase("core"), postgres.WithUsername("core_migrator"), postgres.WithPassword("pw"),
		postgres.BasicWaitStrategies())
	testcontainers.CleanupContainer(t, pg)
	if err != nil {
		t.Fatal(err)
	}
	dsn, err := pg.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	fsys := fstest.MapFS{"00001_create_probe.sql": {Data: []byte(
		"-- +goose Up\nCREATE TABLE probe (id int PRIMARY KEY);\n\n-- +goose Down\nDROP TABLE probe;\n")}}

	for run := 1; run <= 2; run++ {
		if err := Up(ctx, dsn, fsys, slog.New(slog.DiscardHandler)); err != nil {
			t.Fatalf("run %d: %v", run, err)
		}
	}

	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close(ctx)
	var applied int
	if err := conn.QueryRow(ctx, "SELECT count(*) FROM goose_db_version WHERE version_id = 1").Scan(&applied); err != nil {
		t.Fatal(err)
	}
	if applied != 1 {
		t.Fatalf("version 1 recorded %d times, want 1", applied)
	}
}
```

- [ ] **Step 4: Chạy để thấy fail**

Run: `make test-one PKG=./pkg/migrate`
Expected: FAIL — `undefined: Up`.

- [ ] **Step 5: Implement** — `pkg/migrate/migrate.go`

```go
// Package migrate applies a service's embedded goose migrations with the migrator role (AD-26).
// It is the body of `<svc> migrate up`, which the Argo CD PreSync Job runs (deployment.md D-25).
package migrate

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/pressly/goose/v3/lock"
)

// LockTimeout bounds how long a migration statement waits for a lock (deployment.md D-27).
const LockTimeout = "5s"

// Up applies every pending migration in fsys (<version>_<name>.sql files at its root).
// No migration file is a successful no-op that never connects. Concurrent runs are serialized by a
// Postgres advisory lock and applied versions are skipped, so re-running is safe.
func Up(ctx context.Context, dsn string, fsys fs.FS, log *slog.Logger) error {
	if strings.TrimSpace(dsn) == "" {
		return errors.New("migrate: empty DSN")
	}
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		return fmt.Errorf("migrate: parse DSN: %w", err)
	}
	cfg.RuntimeParams["lock_timeout"] = LockTimeout
	db := stdlib.OpenDB(*cfg)
	defer db.Close()

	locker, err := lock.NewPostgresSessionLocker()
	if err != nil {
		return fmt.Errorf("migrate: session locker: %w", err)
	}
	p, err := goose.NewProvider(goose.DialectPostgres, db, fsys,
		goose.WithExcludeNames([]string{"embed.go"}),
		goose.WithDisableGlobalRegistry(true),
		goose.WithSessionLocker(locker),
	)
	if errors.Is(err, goose.ErrNoMigrations) {
		log.InfoContext(ctx, "migrate: no migrations, nothing to do")
		return nil
	}
	if err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	results, err := p.Up(ctx)
	for _, r := range results {
		log.InfoContext(ctx, "migrate: applied", slog.Int64("version", r.Source.Version), slog.Duration("duration", r.Duration))
	}
	if err != nil {
		return fmt.Errorf("migrate: up: %w", err)
	}
	log.InfoContext(ctx, "migrate: done", slog.Int("applied", len(results)))
	return nil
}
```

- [ ] **Step 6: Chạy unit + integration test pkg**

Run: `make test-one PKG=./pkg/migrate && go test -tags integration -count=1 -run TestUpAppliesOnceAndIsSafeToRerun ./pkg/migrate`
Expected: `ok banking-go/pkg/migrate` cả hai (integration cần Docker).

- [ ] **Step 7: Package embed migration** (3 file, khác nhau ở comment)

`services/core/migrations/embed.go`:
```go
// Package migrations embeds core's goose SQL migrations (schema per module, AD-3). Empty until the
// first feature adds <version>_<name>.sql here; `core migrate up` is then a no-op.
package migrations

import "embed"

// FS holds this directory; migrate.Up reads only *.sql at its root.
//
//go:embed *
var FS embed.FS
```

`services/public-api/migrations/embed.go`:
```go
// Package migrations embeds public-api's goose SQL migrations (database "public", AD-3). Empty until
// the first feature adds <version>_<name>.sql here; `public-api migrate up` is then a no-op.
package migrations

import "embed"

// FS holds this directory; migrate.Up reads only *.sql at its root.
//
//go:embed *
var FS embed.FS
```

`services/admin-api/migrations/embed.go`:
```go
// Package migrations embeds admin-api's goose SQL migrations (database "admin", AD-3). Empty until
// the first feature adds <version>_<name>.sql here; `admin-api migrate up` is then a no-op.
package migrations

import "embed"

// FS holds this directory; migrate.Up reads only *.sql at its root.
//
//go:embed *
var FS embed.FS
```

- [ ] **Step 8: Viết test CLI thất bại** — `services/core/cmd/core/migrate_test.go`

```go
package main

import (
	"strings"
	"testing"
)

func TestMigrateRequiresUp(t *testing.T) {
	err := migrateMain([]string{"down"})
	if err == nil || !strings.Contains(err.Error(), "usage: core migrate up") {
		t.Fatalf("migrateMain(down) = %v, want usage error", err)
	}
}

func TestMigrateRequiresMigratorDSN(t *testing.T) {
	t.Setenv("BG_CORE_MIGRATOR_DSN", "")
	if err := migrateMain([]string{"up"}); err == nil || !strings.Contains(err.Error(), "MIGRATOR_DSN") {
		t.Fatalf("migrateMain(up) without DSN = %v, want MIGRATOR_DSN error", err)
	}
}

func TestMigrateUpWithoutMigrationsIsNoop(t *testing.T) {
	t.Setenv("BG_CORE_MIGRATOR_DSN", "postgres://core_migrator:x@127.0.0.1:1/core?connect_timeout=1")
	if err := migrateMain([]string{"up"}); err != nil {
		t.Fatalf("core migrate up = %v, want nil (no migrations yet)", err)
	}
}
```

`services/public-api/cmd/public-api/migrate_test.go`:
```go
package main

import (
	"strings"
	"testing"
)

func TestMigrateRequiresUp(t *testing.T) {
	err := migrateMain([]string{"status"})
	if err == nil || !strings.Contains(err.Error(), "usage: public-api migrate up") {
		t.Fatalf("migrateMain(status) = %v, want usage error", err)
	}
}

func TestMigrateRequiresMigratorDSN(t *testing.T) {
	t.Setenv("BG_PUBLIC_API_MIGRATOR_DSN", "")
	if err := migrateMain([]string{"up"}); err == nil || !strings.Contains(err.Error(), "MIGRATOR_DSN") {
		t.Fatalf("migrateMain(up) without DSN = %v, want MIGRATOR_DSN error", err)
	}
}

func TestMigrateUpWithoutMigrationsIsNoop(t *testing.T) {
	t.Setenv("BG_PUBLIC_API_MIGRATOR_DSN", "postgres://public_migrator:x@127.0.0.1:1/public?connect_timeout=1")
	if err := migrateMain([]string{"up"}); err != nil {
		t.Fatalf("public-api migrate up = %v, want nil (no migrations yet)", err)
	}
}
```

`services/admin-api/cmd/admin-api/migrate_test.go`:
```go
package main

import (
	"strings"
	"testing"
)

func TestMigrateRequiresUp(t *testing.T) {
	err := migrateMain(nil)
	if err == nil || !strings.Contains(err.Error(), "usage: admin-api migrate up") {
		t.Fatalf("migrateMain(nil) = %v, want usage error", err)
	}
}

func TestMigrateRequiresMigratorDSN(t *testing.T) {
	t.Setenv("BG_ADMIN_API_MIGRATOR_DSN", "")
	if err := migrateMain([]string{"up"}); err == nil || !strings.Contains(err.Error(), "MIGRATOR_DSN") {
		t.Fatalf("migrateMain(up) without DSN = %v, want MIGRATOR_DSN error", err)
	}
}

func TestMigrateUpWithoutMigrationsIsNoop(t *testing.T) {
	t.Setenv("BG_ADMIN_API_MIGRATOR_DSN", "postgres://admin_migrator:x@127.0.0.1:1/admin?connect_timeout=1")
	if err := migrateMain([]string{"up"}); err != nil {
		t.Fatalf("admin-api migrate up = %v, want nil (no migrations yet)", err)
	}
}
```

- [ ] **Step 9: Chạy để thấy fail**

Run: `make test-one PKG=./services/core/cmd/core RUN=TestMigrate`
Expected: FAIL — `undefined: migrateMain`.

- [ ] **Step 10: Implement CLI** — `services/core/cmd/core/migrate.go`

```go
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"banking-go/pkg/buildinfo"
	"banking-go/pkg/config"
	"banking-go/pkg/migrate"
	"banking-go/services/core/migrations"
)

// MigrateConfig is read from BG_CORE_* by `core migrate up`; only the PreSync Job sets it (AD-26).
type MigrateConfig struct {
	MigratorDSN string `env:"MIGRATOR_DSN,notEmpty"`
}

// migrateMain runs `core migrate up` against the embedded migrations (deployment.md D-25).
func migrateMain(args []string) error {
	if len(args) != 1 || args[0] != "up" {
		return fmt.Errorf("usage: %s migrate up", serviceName)
	}
	cfg, err := config.Load(serviceName, MigrateConfig{})
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service", serviceName, "version", buildinfo.Version)
	return migrate.Up(ctx, cfg.MigratorDSN, migrations.FS, log)
}
```

`services/public-api/cmd/public-api/migrate.go`:
```go
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"banking-go/pkg/buildinfo"
	"banking-go/pkg/config"
	"banking-go/pkg/migrate"
	"banking-go/services/public-api/migrations"
)

// MigrateConfig is read from BG_PUBLIC_API_* by `public-api migrate up`; only the PreSync Job sets it (AD-26).
type MigrateConfig struct {
	MigratorDSN string `env:"MIGRATOR_DSN,notEmpty"`
}

// migrateMain runs `public-api migrate up` against the embedded migrations (deployment.md D-25).
func migrateMain(args []string) error {
	if len(args) != 1 || args[0] != "up" {
		return fmt.Errorf("usage: %s migrate up", serviceName)
	}
	cfg, err := config.Load(serviceName, MigrateConfig{})
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service", serviceName, "version", buildinfo.Version)
	return migrate.Up(ctx, cfg.MigratorDSN, migrations.FS, log)
}
```

`services/admin-api/cmd/admin-api/migrate.go`:
```go
package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"banking-go/pkg/buildinfo"
	"banking-go/pkg/config"
	"banking-go/pkg/migrate"
	"banking-go/services/admin-api/migrations"
)

// MigrateConfig is read from BG_ADMIN_API_* by `admin-api migrate up`; only the PreSync Job sets it (AD-26).
type MigrateConfig struct {
	MigratorDSN string `env:"MIGRATOR_DSN,notEmpty"`
}

// migrateMain runs `admin-api migrate up` against the embedded migrations (deployment.md D-25).
func migrateMain(args []string) error {
	if len(args) != 1 || args[0] != "up" {
		return fmt.Errorf("usage: %s migrate up", serviceName)
	}
	cfg, err := config.Load(serviceName, MigrateConfig{})
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service", serviceName, "version", buildinfo.Version)
	return migrate.Up(ctx, cfg.MigratorDSN, migrations.FS, log)
}
```

- [ ] **Step 11: Dispatch trong `main()`** — chèn ở đầu `func main()` của `services/core/cmd/core/main.go` (trước `signal.NotifyContext`):

```go
	if len(os.Args) > 1 && os.Args[1] == "migrate" {
		if err := migrateMain(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
```

Trong `services/public-api/cmd/public-api/main.go` và `services/admin-api/cmd/admin-api/main.go`, chèn đúng khối trên ngay sau khối `if len(os.Args) > 1 && os.Args[1] == "openapi" { … }`. Cập nhật doc comment đầu file public-api/admin-api thêm dòng:

```go
//	public-api migrate up  apply embedded migrations with BG_PUBLIC_API_MIGRATOR_DSN (PreSync Job)
```
(admin-api: `admin-api migrate up  apply embedded migrations with BG_ADMIN_API_MIGRATOR_DSN (PreSync Job)`).

- [ ] **Step 12: Đồng bộ go.mod các service**

Run: `for m in services/core services/public-api services/admin-api services/mocks; do (cd $m && go mod tidy); done`
Expected: `goose`/`pgx` xuất hiện dạng `// indirect` trong go.mod các service dùng `pkg/migrate`.

- [ ] **Step 13: `.env.example`** — thêm sau `BG_CORE_SHUTDOWN_TIMEOUT=30s`, `BG_PUBLIC_API_SHUTDOWN_TIMEOUT=30s`, `BG_ADMIN_API_SHUTDOWN_TIMEOUT=30s` tương ứng:

```dotenv
# Migrator DSN, read only by `core migrate up` (PreSync Job, role core_migrator, AD-26). Compose value:
BG_CORE_MIGRATOR_DSN=postgres://core_migrator:core_migrator@localhost:5432/core?sslmode=disable
```
```dotenv
# Migrator DSN, read only by `public-api migrate up` (PreSync Job, role public_migrator, AD-26). Compose value:
BG_PUBLIC_API_MIGRATOR_DSN=postgres://public_migrator:public_migrator@localhost:5432/public?sslmode=disable
```
```dotenv
# Migrator DSN, read only by `admin-api migrate up` (PreSync Job, role admin_migrator, AD-26). Compose value:
BG_ADMIN_API_MIGRATOR_DSN=postgres://admin_migrator:admin_migrator@localhost:5432/admin?sslmode=disable
```

- [ ] **Step 14: Chạy test + lint**

Run: `make test-one PKG=./services/core/cmd/core RUN=TestMigrate && make test-one PKG=./services/public-api/cmd/public-api RUN=TestMigrate && make test-one PKG=./services/admin-api/cmd/admin-api RUN=TestMigrate && make test && make lint`
Expected: tất cả PASS, lint exit 0.

- [ ] **Step 15: Thử thật với compose**

Run: `make up && set -a && . ./.env.example && set +a && go run ./services/core/cmd/core migrate up`
Expected: log JSON `"msg":"migrate: no migrations, nothing to do"`, exit 0.

- [ ] **Step 16: Commit**

```bash
git add pkg/migrate pkg/go.mod pkg/go.sum services/core services/public-api services/admin-api services/mocks/go.mod services/mocks/go.sum .env.example
git commit -m "feat(platform): add 'migrate up' subcommand with embedded goose migrations"
```

**Lệnh kiểm chứng:** `make test-one PKG=./pkg/migrate && go test -tags integration -count=1 ./pkg/migrate && make test && make lint`

---

### T3: Dockerfile Go + `make images` + `make image-smoke`

**Files:**
- Create: `deploy/docker/go.Dockerfile`, `.dockerignore`, `deploy/deployables.tsv`, `scripts/image-smoke.sh`
- Modify: `pkg/buildinfo/buildinfo.go` (thêm `Commit`), `Makefile` (target `images`, `images-go`, `image-smoke`)

**Interfaces:**
- Consumes: `migrate up` (T2), `buildinfo.Version`.
- Produces: image `banking-go/{core,public-api,admin-api,mocks}:local` với binary ở `/usr/local/bin/<cmd>`, user `65532:65532`; build-arg `SERVICE`, `VERSION`, `COMMIT`; `deploy/deployables.tsv` (cột `deployable image command app_port admin_port`) — nguồn duy nhất cho `image-smoke`, `kind-apps` (T11), `kind-smoke` (T12), `release-bump` (T19); biến Makefile `IMAGE_PREFIX ?= banking-go`, `IMAGE_TAG ?= local`, `VERSION`, `GIT_SHA`, `GO_IMAGES`, `IMAGES`; `var buildinfo.Commit`.

- [ ] **Step 1: Tạo `deploy/deployables.tsv`**

```text
# deployable    image         command                      app_port  admin_port   (AD-1, D-23: core-worker shares the core image)
core            core          /usr/local/bin/core          8090      9190
core-worker     core          /usr/local/bin/core-worker   -         9191
public-api      public-api    /usr/local/bin/public-api    8081      9181
admin-api       admin-api     /usr/local/bin/admin-api     8082      9182
mock-napas      mocks         /usr/local/bin/mock-napas    8101      9201
mock-ekyc       mocks         /usr/local/bin/mock-ekyc     8102      9202
mock-otp        mocks         /usr/local/bin/mock-otp      8103      9203
mock-gateway    mocks         /usr/local/bin/mock-gateway  8104      9204
web-customer    web-customer  -                            8080      -
web-admin       web-admin     -                            8080      -
```

- [ ] **Step 2: Viết smoke thất bại** — `scripts/image-smoke.sh`

```bash
#!/usr/bin/env bash
# Runs every locally built image and probes it (platform v1 T3/T4). Needs Docker + curl.
#   scripts/image-smoke.sh [prefix] [tag]      (defaults: banking-go local; VERSION env = expected version)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PREFIX=${1:-banking-go}
TAG=${2:-local}
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }
CIDS=()
cleanup() { [[ ${#CIDS[@]} -eq 0 ]] || docker rm -f "${CIDS[@]}" >/dev/null 2>&1 || true; }
trap cleanup EXIT

host_port() { docker port "$1" "$2/tcp" | head -1 | sed 's/.*://'; }
wait_http() { # wait_http <url> → body
  for _ in $(seq 40); do curl -fsS --max-time 2 "$1" 2>/dev/null && return 0; sleep 0.25; done
  return 1
}

go_check() { # go_check <deployable> <image> <command> <admin_port>
  local name=$1 image=$2 cmd=$3 admin=$4 ref="$PREFIX/$2:$TAG" cid port body
  [[ $(docker inspect -f '{{.Config.User}}' "$ref") == 65532:65532 ]] || fail "$ref must run as 65532:65532"
  cid=$(docker run -d -p "127.0.0.1::$admin" --entrypoint "$cmd" "$ref"); CIDS+=("$cid")
  port=$(host_port "$cid" "$admin")
  body=$(wait_http "http://127.0.0.1:$port/livez") || { docker logs "$cid" >&2; fail "$name: /livez not ready"; }
  [[ $body == '{"status":"ok"}' ]] || fail "$name: /livez body $body"
  if [[ -n ${VERSION:-} ]]; then
    docker logs "$cid" 2>&1 | grep -q "\"version\":\"$VERSION\"" || fail "$name: logs lack version $VERSION"
  fi
  docker rm -f "$cid" >/dev/null
  ok "$name ($ref $cmd) /livez"
}

migrate_check() { # migrate_check <image> <command> <env-prefix>
  docker run --rm --entrypoint "$2" -e "$3_MIGRATOR_DSN=postgres://m:x@127.0.0.1:1/db?connect_timeout=1" \
    "$PREFIX/$1:$TAG" migrate up >/dev/null || fail "$2 migrate up (no migrations) must exit 0"
  ok "$2 migrate up → no-op"
}

while read -r name image cmd _app admin; do
  [[ -z $name || $name == \#* ]] && continue
  if [[ $cmd != - ]]; then go_check "$name" "$image" "$cmd" "$admin"; fi
done < "$ROOT/deploy/deployables.tsv"

migrate_check core /usr/local/bin/core BG_CORE
migrate_check public-api /usr/local/bin/public-api BG_PUBLIC_API
migrate_check admin-api /usr/local/bin/admin-api BG_ADMIN_API
echo "image-smoke: all images passed"
```

- [ ] **Step 3: Chạy để thấy fail**

Run: `chmod +x scripts/image-smoke.sh && scripts/image-smoke.sh`
Expected: `Error: No such object: banking-go/core:local` (exit ≠ 0).

- [ ] **Step 4: `pkg/buildinfo/buildinfo.go`** — thay toàn bộ file:

```go
// Package buildinfo holds build-time metadata injected with -ldflags (deploy/docker/go.Dockerfile).
//
//	go build -ldflags "-X banking-go/pkg/buildinfo.Version=sha-$(git rev-parse --short HEAD) -X banking-go/pkg/buildinfo.Commit=$(git rev-parse HEAD)"
package buildinfo

// Version is the release tag (vX.Y.Z) or sha-<gitsha>; "dev" for local builds.
var Version = "dev"

// Commit is the full git SHA the binary was built from; "unknown" for local builds.
var Commit = "unknown"
```

- [ ] **Step 5: `deploy/docker/go.Dockerfile`**

```dockerfile
# syntax=docker/dockerfile:1
# Go deployables (spec platform v1 §1): one image per Go module, every ./cmd/* binary in /usr/local/bin.
#   docker buildx build --load -f deploy/docker/go.Dockerfile --build-arg SERVICE=core -t banking-go/core:local .
# SERVICE = module dir under services/: core (core, core-worker) | public-api | admin-api | mocks (4 mocks).
ARG GO_IMAGE=golang:1.27.1-trixie
ARG RUNTIME_IMAGE=gcr.io/distroless/static-debian12:nonroot

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS build
ARG SERVICE
ARG VERSION=dev
ARG COMMIT=unknown
ARG TARGETOS
ARG TARGETARCH
ENV GOTOOLCHAIN=local CGO_ENABLED=0
WORKDIR /src
COPY go.work go.work.sum ./
COPY pkg/go.mod pkg/go.sum pkg/
COPY services/core/go.mod services/core/go.sum services/core/
COPY services/public-api/go.mod services/public-api/go.sum services/public-api/
COPY services/admin-api/go.mod services/admin-api/go.sum services/admin-api/
COPY services/mocks/go.mod services/mocks/go.sum services/mocks/
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY pkg/ pkg/
COPY services/ services/
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    test -n "$SERVICE" && \
    GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath \
      -ldflags "-s -w -X banking-go/pkg/buildinfo.Version=${VERSION} -X banking-go/pkg/buildinfo.Commit=${COMMIT}" \
      -o /out/ ./services/${SERVICE}/cmd/...

FROM ${RUNTIME_IMAGE}
ARG VERSION=dev
ARG COMMIT=unknown
LABEL org.opencontainers.image.version="${VERSION}" org.opencontainers.image.revision="${COMMIT}"
COPY --from=build /out/ /usr/local/bin/
USER 65532:65532
```

- [ ] **Step 6: `.dockerignore`**

```text
# Build context = repo root; only what the Go/SPA Dockerfiles copy.
**
!go.work
!go.work.sum
!pkg/
!services/
!apps/
!packages/
!package.json
!pnpm-lock.yaml
!pnpm-workspace.yaml
!tsconfig.base.json
!deploy/docker/
**/node_modules
**/dist
**/coverage
**/*_test.go
```

- [ ] **Step 7: `Makefile`** — thêm khối mới sau khối `gen-check`:

```make
# ---------------------------------------------------------------------------------------------
# Images (platform v1). Local tags banking-go/<image>:local; CI/main.yml pushes ghcr.io/<owner>/banking-go/<image>.
GIT_SHA      := $(shell git rev-parse HEAD 2>/dev/null || echo unknown)
VERSION      ?= sha-$(shell git rev-parse --short=7 HEAD 2>/dev/null || echo dev)
IMAGE_PREFIX ?= banking-go
IMAGE_TAG    ?= local
GO_IMAGES    := core public-api admin-api mocks
IMAGES       := $(GO_IMAGES)

.PHONY: images images-go image-smoke
images: images-go ## Build the deployable images as $(IMAGE_PREFIX)/<image>:$(IMAGE_TAG) (needs Docker buildx)
images-go:
	@for i in $(GO_IMAGES); do \
		echo "== image $$i"; \
		docker buildx build --load -f deploy/docker/go.Dockerfile \
			--build-arg SERVICE=$$i --build-arg VERSION=$(VERSION) --build-arg COMMIT=$(GIT_SHA) \
			-t $(IMAGE_PREFIX)/$$i:$(IMAGE_TAG) . ; \
	done
image-smoke: ## Run every local image and probe it (make images first)
	VERSION=$(VERSION) scripts/image-smoke.sh $(IMAGE_PREFIX) $(IMAGE_TAG)
```

- [ ] **Step 8: Build + smoke**

Run: `make images && make image-smoke`
Expected: 8 dòng `ok   <deployable> … /livez`, 3 dòng `migrate up → no-op`, cuối `image-smoke: all images passed`. `docker image ls banking-go/core:local` < 40 MB.

- [ ] **Step 9: Commit**

```bash
git add deploy/docker/go.Dockerfile .dockerignore deploy/deployables.tsv scripts/image-smoke.sh pkg/buildinfo/buildinfo.go Makefile
git commit -m "feat(platform): distroless Go images for core, public-api, admin-api, mocks with image smoke"
```

**Lệnh kiểm chứng:** `make images && make image-smoke`

---

### T4: Dockerfile SPA + nginx + `config.js` runtime

**Files:**
- Create: `packages/runtime-config/package.json`, `packages/runtime-config/tsconfig.json`, `packages/runtime-config/src/index.ts`, `packages/runtime-config/src/index.test.ts`
- Create: `apps/web-customer/public/config.js`, `apps/web-admin/public/config.js`
- Modify: `apps/web-customer/index.html`, `apps/web-admin/index.html`, `apps/web-customer/src/main.tsx`, `apps/web-admin/src/main.tsx`, `apps/web-customer/package.json`, `apps/web-admin/package.json`, `pnpm-lock.yaml` (qua `pnpm install`)
- Create: `deploy/docker/spa.Dockerfile`, `deploy/docker/nginx/nginx.conf`, `deploy/docker/nginx/default.conf.template`, `deploy/docker/nginx/security-headers.inc.template`
- Modify: `scripts/image-smoke.sh` (thêm `spa_check`), `Makefile` (`SPA_IMAGES`, `images-spa`)

**Interfaces:**
- Consumes: `deploy/deployables.tsv`, `scripts/image-smoke.sh`, biến `IMAGE_PREFIX`/`IMAGE_TAG` (T3).
- Produces: `getRuntimeConfig(source?: Partial<RuntimeConfig>): RuntimeConfig` với `RuntimeConfig = { apiBaseUrl: string; env: string; release: string }` từ `@banking-go/runtime-config`; `window.__BG_CONFIG__`; image `banking-go/{web-customer,web-admin}:local` (nginx uid 101, port 8080, `/healthz`, `/config.js` no-cache, `/assets/*` immutable, SPA fallback); file mount `/usr/share/nginx/html/config.js` (chart T7 dùng `configFiles`); env `BG_API_ORIGIN` → CSP `connect-src`; nginx chỉ ghi vào `/tmp` (chạy được với `readOnlyRootFilesystem`).

- [ ] **Step 1: Viết test thất bại** — `packages/runtime-config/src/index.test.ts`

```ts
import { describe, expect, it } from 'vitest'

import { getRuntimeConfig } from './index'

describe('getRuntimeConfig', () => {
  it('returns local defaults when /config.js did not run', () => {
    expect(getRuntimeConfig({})).toEqual({ apiBaseUrl: '', env: 'local', release: 'dev' })
  })

  it('overrides defaults with the values injected by /config.js', () => {
    expect(getRuntimeConfig({ apiBaseUrl: 'https://api.kind.localhost', env: 'kind' })).toEqual({
      apiBaseUrl: 'https://api.kind.localhost',
      env: 'kind',
      release: 'dev',
    })
  })

  it('rejects a non-string apiBaseUrl', () => {
    expect(() => getRuntimeConfig({ apiBaseUrl: 42 as unknown as string })).toThrow(/apiBaseUrl/)
  })
})
```

`packages/runtime-config/package.json`:
```json
{
  "name": "@banking-go/runtime-config",
  "version": "0.0.0",
  "private": true,
  "type": "module",
  "exports": {
    ".": "./src/index.ts"
  },
  "scripts": {
    "lint": "eslint . && prettier --check src package.json tsconfig.json",
    "typecheck": "tsc --noEmit -p tsconfig.json",
    "test": "vitest run"
  },
  "devDependencies": {
    "vitest": "5.0.3"
  }
}
```

`packages/runtime-config/tsconfig.json`:
```json
{
  "extends": "../../tsconfig.base.json",
  "compilerOptions": {
    "types": []
  },
  "include": ["src"]
}
```

- [ ] **Step 2: Chạy để thấy fail**

Run: `npx -y pnpm@12.9.1 install && make test-one WEB=@banking-go/runtime-config`
Expected: FAIL — `Failed to resolve import "./index"`.

- [ ] **Step 3: Implement** — `packages/runtime-config/src/index.ts`

```ts
/** Runtime configuration of a SPA, injected by /config.js (ConfigMap on Kubernetes, public/config.js in dev). */
export interface RuntimeConfig {
  apiBaseUrl: string
  env: string
  release: string
}

declare global {
  interface Window {
    __BG_CONFIG__?: Partial<RuntimeConfig>
  }
}

const defaults: RuntimeConfig = { apiBaseUrl: '', env: 'local', release: 'dev' }

/** Merges window.__BG_CONFIG__ (or an explicit source) over local defaults; never bakes URLs into the bundle. */
export function getRuntimeConfig(
  source: Partial<RuntimeConfig> = globalThis.window?.__BG_CONFIG__ ?? {},
): RuntimeConfig {
  const config = { ...defaults, ...source }
  if (typeof config.apiBaseUrl !== 'string') {
    throw new Error('runtime config: apiBaseUrl must be a string')
  }
  return config
}
```

- [ ] **Step 4: Chạy test pass**

Run: `make test-one WEB=@banking-go/runtime-config`
Expected: 3 passed.

- [ ] **Step 5: Nối vào 2 SPA**

`apps/web-customer/public/config.js`:
```js
// Runtime config for `vite dev` / `vite preview`. On Kubernetes this file is replaced by a ConfigMap mount.
window.__BG_CONFIG__ = { apiBaseUrl: 'http://localhost:8081', env: 'local', release: 'dev' }
```
`apps/web-admin/public/config.js`:
```js
// Runtime config for `vite dev` / `vite preview`. On Kubernetes this file is replaced by a ConfigMap mount.
window.__BG_CONFIG__ = { apiBaseUrl: 'http://localhost:8082', env: 'local', release: 'dev' }
```
Trong `apps/web-customer/index.html` và `apps/web-admin/index.html`, thêm ngay trước `</head>`:
```html
    <script src="/config.js"></script>
```
Trong `apps/web-customer/src/main.tsx` và `apps/web-admin/src/main.tsx`, thêm import và một dòng trước `createRoot(...)`:
```tsx
import { getRuntimeConfig } from '@banking-go/runtime-config'
```
```tsx
document.documentElement.dataset.env = getRuntimeConfig().env
```
Trong `dependencies` của `apps/web-customer/package.json` và `apps/web-admin/package.json` thêm `"@banking-go/runtime-config": "workspace:*"`, rồi chạy `npx -y pnpm@12.9.1 install` (cập nhật lockfile bằng lệnh, không sửa tay).

- [ ] **Step 6: nginx config**

`deploy/docker/nginx/nginx.conf`:
```nginx
# SPA images: nginx-unprivileged (uid 101), read-only root fs; only /tmp is writable (emptyDir on Kubernetes).
worker_processes auto;
pid /tmp/nginx.pid;
error_log /dev/stderr warn;

events {
  worker_connections 1024;
}

http {
  include /etc/nginx/mime.types;
  default_type application/octet-stream;
  access_log /dev/stdout;
  sendfile on;
  server_tokens off;
  client_body_temp_path /tmp/client_temp;
  proxy_temp_path /tmp/proxy_temp;
  fastcgi_temp_path /tmp/fastcgi_temp;
  uwsgi_temp_path /tmp/uwsgi_temp;
  scgi_temp_path /tmp/scgi_temp;
  # Rendered at start by the image entrypoint (envsubst of /etc/nginx/templates/*.template, NGINX_ENVSUBST_OUTPUT_DIR=/tmp).
  include /tmp/*.conf;
}
```

`deploy/docker/nginx/security-headers.inc.template`:
```nginx
add_header X-Content-Type-Options "nosniff" always;
add_header Referrer-Policy "strict-origin-when-cross-origin" always;
add_header Content-Security-Policy "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self' ${BG_API_ORIGIN}; frame-ancestors 'none'; base-uri 'self'" always;
```

`deploy/docker/nginx/default.conf.template`:
```nginx
# deployment.md § SPA: index.html + config.js no-cache, hashed assets immutable, SPA fallback, /healthz for probes.
server {
  listen 8080;
  root /usr/share/nginx/html;

  location = /healthz {
    access_log off;
    default_type text/plain;
    return 200 "ok\n";
  }

  location = /config.js {
    include /tmp/security-headers.inc;
    add_header Cache-Control "no-cache" always;
  }

  location /assets/ {
    include /tmp/security-headers.inc;
    add_header Cache-Control "public, max-age=31536000, immutable" always;
    try_files $uri =404;
  }

  location / {
    include /tmp/security-headers.inc;
    add_header Cache-Control "no-cache" always;
    try_files $uri $uri/ /index.html;
  }
}
```

- [ ] **Step 7: `deploy/docker/spa.Dockerfile`**

```dockerfile
# syntax=docker/dockerfile:1
# SPA deployables (spec platform v1 §1): Vite build → nginx-unprivileged. /config.js comes from a ConfigMap.
#   docker buildx build --load -f deploy/docker/spa.Dockerfile --build-arg APP=web-customer -t banking-go/web-customer:local .
ARG NODE_IMAGE=node:24.19.0-trixie-slim
ARG NGINX_IMAGE=nginxinc/nginx-unprivileged:1.30.5-alpine

FROM ${NODE_IMAGE} AS build
ARG APP
ENV CI=true
WORKDIR /src
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml tsconfig.base.json ./
COPY packages/ packages/
COPY apps/ apps/
RUN --mount=type=cache,target=/root/.local/share/pnpm/store \
    test -n "$APP" && \
    npx -y pnpm@12.9.1 install --frozen-lockfile --filter "@banking-go/${APP}..." && \
    npx -y pnpm@12.9.1 --filter "@banking-go/${APP}" build

FROM ${NGINX_IMAGE}
ARG APP
USER root
RUN rm -f /etc/nginx/conf.d/default.conf
COPY deploy/docker/nginx/nginx.conf /etc/nginx/nginx.conf
COPY deploy/docker/nginx/default.conf.template deploy/docker/nginx/security-headers.inc.template /etc/nginx/templates/
COPY --from=build /src/apps/${APP}/dist/ /usr/share/nginx/html/
ENV NGINX_ENVSUBST_OUTPUT_DIR=/tmp NGINX_ENVSUBST_TEMPLATE_SUFFIX=.template BG_API_ORIGIN=http://localhost:8081
USER 101
EXPOSE 8080
```

- [ ] **Step 8: Viết smoke SPA thất bại** — trong `scripts/image-smoke.sh` thêm hàm sau `migrate_check`:

```bash
spa_check() { # spa_check <deployable> <image>
  local name=$1 ref="$PREFIX/$2:$TAG" dir cid port base asset
  [[ $(docker inspect -f '{{.Config.User}}' "$ref") == 101 ]] || fail "$ref must run as uid 101"
  dir=$(mktemp -d)
  printf "window.__BG_CONFIG__ = { apiBaseUrl: 'https://api.smoke.test', env: 'smoke', release: 'smoke' }\n" > "$dir/config.js"
  chmod 644 "$dir/config.js"
  cid=$(docker run -d --read-only --tmpfs /tmp:rw,mode=1777 -e BG_API_ORIGIN=https://api.smoke.test \
    -v "$dir/config.js:/usr/share/nginx/html/config.js:ro" -p 127.0.0.1::8080 "$ref"); CIDS+=("$cid")
  port=$(host_port "$cid" 8080); base="http://127.0.0.1:$port"
  wait_http "$base/healthz" >/dev/null || { docker logs "$cid" >&2; fail "$name: /healthz not ready"; }
  curl -fsS "$base/" | grep -q '<div id="root">' || fail "$name: / is not the SPA"
  curl -fsS "$base/" | grep -q 'src="/config.js"' || fail "$name: index.html does not load /config.js"
  curl -fsS "$base/accounts/123" | grep -q '<div id="root">' || fail "$name: no SPA fallback"
  curl -fsS "$base/config.js" | grep -q 'api.smoke.test' || fail "$name: /config.js is not the mounted file"
  curl -fsSI "$base/config.js" | grep -qi '^cache-control: no-cache' || fail "$name: /config.js must be no-cache"
  asset=$(curl -fsS "$base/" | grep -o '/assets/[^"]*\.js' | head -1)
  curl -fsSI "$base$asset" | grep -qi '^cache-control: .*immutable' || fail "$name: $asset must be immutable"
  curl -fsSI "$base/" | grep -qi "^content-security-policy: .*connect-src 'self' https://api.smoke.test" || fail "$name: CSP connect-src"
  docker rm -f "$cid" >/dev/null; rm -rf "$dir"
  ok "$name ($ref) nginx: SPA, config.js, cache headers, CSP"
}
```
và đổi dòng trong vòng lặp `while read …` thành:
```bash
  if [[ $cmd != - ]]; then go_check "$name" "$image" "$cmd" "$admin"; else spa_check "$name" "$image"; fi
```

Run: `scripts/image-smoke.sh`
Expected: FAIL — `Error: No such object: banking-go/web-customer:local`.

- [ ] **Step 9: `Makefile`** — đổi `IMAGES := $(GO_IMAGES)` thành hai dòng và thêm target:

```make
SPA_IMAGES   := web-customer web-admin
IMAGES       := $(GO_IMAGES) $(SPA_IMAGES)
```
```make
.PHONY: images-spa
images: images-go images-spa ## Build the 6 images as $(IMAGE_PREFIX)/<image>:$(IMAGE_TAG) (needs Docker buildx)
images-spa:
	@for i in $(SPA_IMAGES); do \
		echo "== image $$i"; \
		docker buildx build --load -f deploy/docker/spa.Dockerfile --build-arg APP=$$i -t $(IMAGE_PREFIX)/$$i:$(IMAGE_TAG) . ; \
	done
```
(xóa dòng `images: images-go ## …` cũ của T3).

- [ ] **Step 10: Build + smoke + test web**

Run: `make images && make image-smoke && make test-web && make lint-web && make e2e`
Expected: thêm 2 dòng `ok   web-… nginx: SPA, config.js, cache headers, CSP`; vitest/lint/e2e pass.

- [ ] **Step 11: Commit**

```bash
git add packages/runtime-config apps/web-customer apps/web-admin pnpm-lock.yaml deploy/docker scripts/image-smoke.sh Makefile
git commit -m "feat(platform): nginx-unprivileged SPA images with runtime config.js"
```

**Lệnh kiểm chứng:** `make images && make image-smoke && make test-web`

---

### T5: Library chart phần 1 (Deployment, Service, ServiceAccount, ConfigMap) + helm-unittest

**Files:**
- Create: `deploy/helm/_lib/Chart.yaml`, `deploy/helm/_lib/templates/_helpers.tpl`, `_deployment.tpl`, `_service.tpl`, `_serviceaccount.tpl`, `_configmap.tpl`, `_all.tpl`
- Create: `deploy/helm/_libtest/Chart.yaml`, `deploy/helm/_libtest/values.yaml`, `deploy/helm/_libtest/templates/all.yaml`, `deploy/helm/_libtest/tests/deployment_test.yaml`, `deploy/helm/_libtest/tests/service_test.yaml`
- Modify: `.gitignore` (`deploy/helm/*/charts/`, `deploy/helm/*/Chart.lock`), `Makefile` (`helm-test`)

**Interfaces:**
- Consumes: `bin/helm` + plugin unittest (T1); `/usr/local/bin/<cmd>`, port, `/livez` `/readyz`, `/healthz` (T3/T4).
- Produces: library chart `lib` 0.1.0 (`file://../_lib`), template `lib.all` (thin chart chỉ cần `{{ include "lib.all" . }}`), helper `lib.name`, `lib.labels`, `lib.selectorLabels`, `lib.envPrefix` (`BG_<SVC>_`), `lib.image`; values đọc: `global.{ghOwner,imagePullSecrets,otelEndpoint,gateway}`, `image.{repository,digest,tag,pullPolicy}`, `command`, `ports.{app,admin}`, `replicas`, `resources`, `env` (map), `envFromSecrets` (list tên Secret), `configFiles` (map `<file>: {mountPath, content}`), `secretsRevision`, `shutdownTimeoutSeconds`; key `<deployable>: {image, digest}` từ file releases. Thứ tự image: releases file → `image.digest` → `image.tag`.

- [ ] **Step 1: Fixture chart + test thất bại**

`deploy/helm/_libtest/Chart.yaml`:
```yaml
apiVersion: v2
name: libtest
description: Test fixture for the lib library chart (helm-unittest only, never deployed).
type: application
version: 0.1.0
dependencies:
  - name: lib
    version: 0.1.0
    repository: file://../_lib
```

`deploy/helm/_libtest/templates/all.yaml`:
```yaml
{{ include "lib.all" . }}
```

`deploy/helm/_libtest/values.yaml`:
```yaml
# Fixture shaped like a Go service chart; tests override keys with `set`.
global:
  ghOwner: acme
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/libtest"
  digest: ""
  tag: local
  pullPolicy: IfNotPresent
command: ["/usr/local/bin/libtest"]
ports: {app: 8081, admin: 9181}
replicas: 1
resources:
  requests: {cpu: 10m, memory: 32Mi}
  limits: {memory: 128Mi}
env:
  BG_LIBTEST_ENVIRONMENT: test
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: false, host: "", pathPrefix: /}
migration: {enabled: false, dsnSecret: ""}
mtls: {enabled: false}
shutdownTimeoutSeconds: 30
```

`deploy/helm/_libtest/tests/deployment_test.yaml`:
```yaml
suite: lib deployment
templates:
  - templates/all.yaml
tests:
  - it: takes image and digest from the releases file entry keyed by deployable name
    set:
      libtest:
        image: ghcr.io/acme/banking-go/core
        digest: sha256:1111111111111111111111111111111111111111111111111111111111111111
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal:
          path: spec.template.spec.containers[0].image
          value: ghcr.io/acme/banking-go/core@sha256:1111111111111111111111111111111111111111111111111111111111111111
  - it: falls back to image.digest on the templated repository
    set:
      image.digest: sha256:2222222222222222222222222222222222222222222222222222222222222222
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal:
          path: spec.template.spec.containers[0].image
          value: ghcr.io/acme/banking-go/libtest@sha256:2222222222222222222222222222222222222222222222222222222222222222
  - it: uses repository:tag for images loaded into kind
    set:
      image.repository: banking-go/libtest
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal: {path: spec.template.spec.containers[0].image, value: "banking-go/libtest:local"}
  - it: fails without a digest or a tag
    set:
      image.tag: ""
    asserts:
      - failedTemplate: {errorPattern: "no digest"}
  - it: fails when global.ghOwner is empty
    set:
      global.ghOwner: ""
    asserts:
      - failedTemplate: {errorPattern: "global.ghOwner is empty"}
  - it: rolls out with zero unavailable and drains within the grace period (AD-26)
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal: {path: spec.strategy.rollingUpdate.maxUnavailable, value: 0}
      - equal: {path: spec.strategy.rollingUpdate.maxSurge, value: 1}
      - equal: {path: spec.minReadySeconds, value: 10}
      - equal: {path: spec.progressDeadlineSeconds, value: 300}
      - equal: {path: spec.template.spec.terminationGracePeriodSeconds, value: 45}
      - equal: {path: spec.template.spec.containers[0].lifecycle.preStop.sleep.seconds, value: 5}
      - contains:
          path: spec.template.spec.containers[0].env
          content: {name: BG_LIBTEST_SHUTDOWN_TIMEOUT, value: "30s"}
  - it: probes /livez and /readyz on the admin port
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal: {path: spec.template.spec.containers[0].livenessProbe.httpGet.path, value: /livez}
      - equal: {path: spec.template.spec.containers[0].livenessProbe.httpGet.port, value: admin}
      - equal: {path: spec.template.spec.containers[0].readinessProbe.httpGet.path, value: /readyz}
  - it: probes /healthz on the app port when there is no admin port (SPA)
    set:
      ports.admin: null
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal: {path: spec.template.spec.containers[0].readinessProbe.httpGet.path, value: /healthz}
      - equal: {path: spec.template.spec.containers[0].readinessProbe.httpGet.port, value: app}
  - it: runs non-root with a read-only root filesystem and a writable /tmp
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal: {path: spec.template.spec.securityContext.runAsNonRoot, value: true}
      - equal: {path: spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem, value: true}
      - equal: {path: spec.template.spec.containers[0].securityContext.allowPrivilegeEscalation, value: false}
      - equal: {path: spec.template.spec.containers[0].securityContext.capabilities.drop, value: [ALL]}
      - contains:
          path: spec.template.spec.containers[0].volumeMounts
          content: {name: tmp, mountPath: /tmp}
  - it: injects env, envFromSecrets, the OTLP endpoint and pull secrets
    set:
      envFromSecrets: [libtest-env]
      global.otelEndpoint: http://otel-collector.observability.svc:4317
      global.imagePullSecrets: [ghcr-pull]
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - contains:
          path: spec.template.spec.containers[0].env
          content: {name: BG_LIBTEST_ENVIRONMENT, value: test}
      - contains:
          path: spec.template.spec.containers[0].env
          content: {name: OTEL_EXPORTER_OTLP_ENDPOINT, value: "http://otel-collector.observability.svc:4317"}
      - equal: {path: "spec.template.spec.containers[0].envFrom[0].secretRef.name", value: libtest-env}
      - equal: {path: "spec.template.spec.imagePullSecrets[0].name", value: ghcr-pull}
  - it: uses the command and both container ports
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal: {path: spec.template.spec.containers[0].command, value: [/usr/local/bin/libtest]}
      - contains:
          path: spec.template.spec.containers[0].ports
          content: {name: app, containerPort: 8081}
      - contains:
          path: spec.template.spec.containers[0].ports
          content: {name: admin, containerPort: 9181}
  - it: mounts configFiles from the ConfigMap and restarts pods on change
    set:
      configFiles:
        config.js:
          mountPath: /usr/share/nginx/html/config.js
          content: "window.__BG_CONFIG__ = {}"
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - contains:
          path: spec.template.spec.containers[0].volumeMounts
          content: {name: config, mountPath: /usr/share/nginx/html/config.js, subPath: config.js, readOnly: true}
      - exists: {path: "spec.template.metadata.annotations[\"checksum/config\"]"}
```

`deploy/helm/_libtest/tests/service_test.yaml`:
```yaml
suite: lib service, serviceaccount, configmap
templates:
  - templates/all.yaml
tests:
  - it: renders ServiceAccount, Service and Deployment by default
    asserts:
      - hasDocuments: {count: 3}
  - it: exposes app and admin ports by name
    documentSelector: {path: kind, value: Service}
    asserts:
      - equal: {path: spec.type, value: ClusterIP}
      - contains: {path: spec.ports, content: {name: app, port: 8081, targetPort: app}}
      - contains: {path: spec.ports, content: {name: admin, port: 9181, targetPort: admin}}
      - equal: {path: "spec.selector[\"app.kubernetes.io/name\"]", value: libtest}
  - it: does not automount the ServiceAccount token
    documentSelector: {path: kind, value: ServiceAccount}
    asserts:
      - equal: {path: automountServiceAccountToken, value: false}
  - it: renders configFiles into a ConfigMap
    set:
      configFiles:
        config.js:
          mountPath: /usr/share/nginx/html/config.js
          content: "window.__BG_CONFIG__ = { env: 'kind' }"
    documentSelector: {path: kind, value: ConfigMap}
    asserts:
      - equal: {path: "data[\"config.js\"]", value: "window.__BG_CONFIG__ = { env: 'kind' }"}
```

- [ ] **Step 2: Makefile + .gitignore** — thêm vào `.gitignore`:

```text
# Helm dependency build output (lib chart is a file:// dependency)
deploy/helm/*/charts/
deploy/helm/*/Chart.lock
```
Thêm vào `Makefile` sau khối Images:
```make
# ---------------------------------------------------------------------------------------------
# Helm (platform v1): deploy/helm/_lib is the only place with Kubernetes templates.
.PHONY: helm-test
helm-test: tools-k8s ## helm-unittest: lib fixture chart + every chart with tests/
	@for c in deploy/helm/_libtest $(filter-out deploy/helm/_%,$(wildcard deploy/helm/*)); do \
		if [ -d $$c/tests ]; then echo "== $$c"; $(HELM) dependency build $$c >/dev/null && $(HELM) unittest $$c; fi; \
	done
```

- [ ] **Step 3: Chạy để thấy fail**

Run: `make helm-test`
Expected: FAIL — `directory ../_lib not found` (lib chưa có).

- [ ] **Step 4: Implement lib**

`deploy/helm/_lib/Chart.yaml`:
```yaml
apiVersion: v2
name: lib
description: The only Kubernetes templates of banking-go deployables (spec platform v1 §6). Thin charts include "lib.all".
type: library
version: 0.1.0
```

`deploy/helm/_lib/templates/_helpers.tpl`:
```yaml
{{/* Deployable name = name of the thin chart (AD-1). */}}
{{- define "lib.name" -}}
{{- .Chart.Name -}}
{{- end -}}

{{- define "lib.selectorLabels" -}}
app.kubernetes.io/name: {{ include "lib.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "lib.labels" -}}
{{ include "lib.selectorLabels" . }}
app.kubernetes.io/part-of: banking-go
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{/* BG_<SERVICE>_ prefix, same rule as pkg/config.Prefix. */}}
{{- define "lib.envPrefix" -}}
{{- printf "BG_%s_" (include "lib.name" . | upper | replace "-" "_") -}}
{{- end -}}

{{/*
Image reference, by precedence:
  1. deploy/releases/<env>.yaml entry keyed by deployable: {image, digest} (Argo CD multi-source, spec "Thiết kế")
  2. image.digest on image.repository
  3. image.tag on image.repository (local images loaded into kind)
image.repository goes through tpl so it can reference .Values.global.ghOwner.
*/}}
{{- define "lib.image" -}}
{{- $name := include "lib.name" . -}}
{{- $rel := index .Values $name | default dict -}}
{{- if and (kindIs "map" $rel) (get $rel "digest") -}}
{{- printf "%s@%s" (get $rel "image" | required (printf "%s.image is required in the releases file" $name)) (get $rel "digest") -}}
{{- else -}}
{{- $repo := tpl (required "image.repository is required" .Values.image.repository) . -}}
{{- if contains "//" $repo -}}
{{- fail "global.ghOwner is empty (set GH_OWNER / Argo CD parameter global.ghOwner)" -}}
{{- end -}}
{{- if .Values.image.digest -}}
{{- printf "%s@%s" $repo .Values.image.digest -}}
{{- else if .Values.image.tag -}}
{{- printf "%s:%s" $repo .Values.image.tag -}}
{{- else -}}
{{- fail (printf "%s: no digest (deploy/releases/<env>.yaml or image.digest) and no image.tag" $name) -}}
{{- end -}}
{{- end -}}
{{- end -}}
```

`deploy/helm/_lib/templates/_serviceaccount.tpl`:
```yaml
{{- define "lib.serviceaccount" -}}
apiVersion: v1
kind: ServiceAccount
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
automountServiceAccountToken: false
{{- end -}}
```

`deploy/helm/_lib/templates/_service.tpl`:
```yaml
{{- define "lib.service" -}}
apiVersion: v1
kind: Service
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
spec:
  type: ClusterIP
  selector:
    {{- include "lib.selectorLabels" . | nindent 4 }}
  ports:
    {{- if .Values.ports.app }}
    - name: app
      port: {{ .Values.ports.app }}
      targetPort: app
    {{- end }}
    {{- if .Values.ports.admin }}
    - name: admin
      port: {{ .Values.ports.admin }}
      targetPort: admin
    {{- end }}
{{- end -}}
```

`deploy/helm/_lib/templates/_configmap.tpl`:
```yaml
{{- define "lib.configmap" -}}
{{- if .Values.configFiles }}
apiVersion: v1
kind: ConfigMap
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
data:
  {{- range $file, $cfg := .Values.configFiles }}
  {{ $file }}: {{ $cfg.content | quote }}
  {{- end }}
{{- end }}
{{- end -}}
```

`deploy/helm/_lib/templates/_deployment.tpl`:
```yaml
{{- define "lib.deployment" -}}
{{- $prefix := include "lib.envPrefix" . -}}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicas }}
  revisionHistoryLimit: 3
  minReadySeconds: 10
  progressDeadlineSeconds: 300
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0
      maxSurge: 1
  selector:
    matchLabels:
      {{- include "lib.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "lib.selectorLabels" . | nindent 8 }}
      annotations:
        checksum/config: {{ toJson (.Values.configFiles | default dict) | sha256sum }}
        banking-go/secrets-revision: {{ .Values.secretsRevision | default "0" | quote }}
    spec:
      serviceAccountName: {{ include "lib.name" . }}
      automountServiceAccountToken: false
      terminationGracePeriodSeconds: {{ add (int .Values.shutdownTimeoutSeconds) 15 }}
      {{- with .Values.global.imagePullSecrets }}
      imagePullSecrets:
        {{- range . }}
        - name: {{ . }}
        {{- end }}
      {{- end }}
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: {{ include "lib.name" . }}
          image: {{ include "lib.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          {{- with .Values.command }}
          command:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          ports:
            {{- if .Values.ports.app }}
            - name: app
              containerPort: {{ .Values.ports.app }}
            {{- end }}
            {{- if .Values.ports.admin }}
            - name: admin
              containerPort: {{ .Values.ports.admin }}
            {{- end }}
          env:
            - name: {{ $prefix }}SHUTDOWN_TIMEOUT
              value: {{ printf "%ds" (int .Values.shutdownTimeoutSeconds) | quote }}
            {{- with .Values.global.otelEndpoint }}
            - name: OTEL_EXPORTER_OTLP_ENDPOINT
              value: {{ . | quote }}
            - name: OTEL_EXPORTER_OTLP_INSECURE
              value: "true"
            {{- end }}
            {{- range $k, $v := .Values.env }}
            - name: {{ $k }}
              value: {{ $v | toString | quote }}
            {{- end }}
          {{- with .Values.envFromSecrets }}
          envFrom:
            {{- range . }}
            - secretRef:
                name: {{ . }}
            {{- end }}
          {{- end }}
          {{- if .Values.ports.admin }}
          livenessProbe:
            httpGet: {path: /livez, port: admin}
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet: {path: /readyz, port: admin}
            periodSeconds: 5
            failureThreshold: 2
          {{- else }}
          livenessProbe:
            httpGet: {path: /healthz, port: app}
            periodSeconds: 10
            failureThreshold: 3
          readinessProbe:
            httpGet: {path: /healthz, port: app}
            periodSeconds: 5
            failureThreshold: 2
          {{- end }}
          lifecycle:
            preStop:
              sleep:
                seconds: 5
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
            {{- range $file, $cfg := .Values.configFiles }}
            - name: config
              mountPath: {{ $cfg.mountPath }}
              subPath: {{ $file }}
              readOnly: true
            {{- end }}
      volumes:
        - name: tmp
          emptyDir: {}
        {{- if .Values.configFiles }}
        - name: config
          configMap:
            name: {{ include "lib.name" . }}
        {{- end }}
{{- end -}}
```

`deploy/helm/_lib/templates/_all.tpl`:
```yaml
{{/* Every object of a deployable; empty documents are skipped. Thin charts: {{ include "lib.all" . }} */}}
{{- define "lib.all" -}}
{{- $docs := list
    (include "lib.serviceaccount" .)
    (include "lib.service" .)
    (include "lib.configmap" .)
    (include "lib.deployment" .) -}}
{{- range $docs }}
{{- if trim . }}
---
{{ trim . }}
{{- end }}
{{- end }}
{{- end -}}
```

- [ ] **Step 5: Chạy test pass**

Run: `make helm-test`
Expected: `Charts: 1 passed, 1 total`, `Test Suites: 2 passed`, `Tests: 16 passed`.

- [ ] **Step 6: Commit**

```bash
git add deploy/helm/_lib deploy/helm/_libtest .gitignore Makefile
git commit -m "feat(platform): helm library chart with deployment, service, serviceaccount, configmap"
```

**Lệnh kiểm chứng:** `make helm-test`

---

### T6: Library chart phần 2 (HTTPRoute, PDB, migration PreSync Job, Certificate mTLS) + helm-unittest

**Files:**
- Create: `deploy/helm/_lib/templates/_httproute.tpl`, `_pdb.tpl`, `_migration.tpl`, `_certificate.tpl`
- Modify: `deploy/helm/_lib/templates/_all.tpl`, `deploy/helm/_lib/templates/_deployment.tpl` (mount mTLS)
- Create: `deploy/helm/_libtest/tests/httproute_test.yaml`, `pdb_test.yaml`, `migration_test.yaml`, `certificate_test.yaml`

**Interfaces:**
- Consumes: `lib.name`, `lib.labels`, `lib.selectorLabels`, `lib.envPrefix`, `lib.image` (T5); CLI `<cmd> migrate up` + env `BG_<SVC>_MIGRATOR_DSN` (T2).
- Produces: values `route.{enabled,host,pathPrefix}`, `global.gateway.{name,namespace,sectionName}` (mặc định `traefik-gateway`/`traefik`/`websecure`), `migration.{enabled,dsnSecret}` (Secret có key `dsn`), `mtls.enabled` (+ `mtls.issuer`, mặc định ClusterIssuer `bg-internal-ca`); Job `<name>-migrate` (label `app.kubernetes.io/name: <name>-migrate`, không bị Service chọn); Certificate + Secret `<name>-mtls` mount tại `/etc/bg/mtls`; PDB `minAvailable: 1` khi `replicas > 1`.

- [ ] **Step 1: Viết test thất bại**

`deploy/helm/_libtest/tests/migration_test.yaml`:
```yaml
suite: lib migration PreSync Job (AD-26)
templates:
  - templates/all.yaml
tests:
  - it: renders no Job when migration is disabled
    asserts:
      - hasDocuments: {count: 3}
  - it: runs '<command> migrate up' as an Argo CD PreSync hook before the rollout
    set:
      migration: {enabled: true, dsnSecret: libtest-migrator-dsn}
    documentSelector: {path: kind, value: Job}
    asserts:
      - equal: {path: metadata.name, value: libtest-migrate}
      - equal: {path: "metadata.annotations[\"argocd.argoproj.io/hook\"]", value: PreSync}
      - equal: {path: "metadata.annotations[\"argocd.argoproj.io/hook-delete-policy\"]", value: BeforeHookCreation}
      - equal: {path: "metadata.annotations[\"argocd.argoproj.io/sync-wave\"]", value: "-1"}
      - equal: {path: "metadata.annotations[\"helm.sh/hook\"]", value: "pre-install,pre-upgrade"}
      - equal: {path: spec.template.spec.containers[0].command, value: [/usr/local/bin/libtest, migrate, up]}
      - equal: {path: spec.template.spec.containers[0].image, value: "ghcr.io/acme/banking-go/libtest:local"}
      - contains:
          path: spec.template.spec.containers[0].env
          content:
            name: BG_LIBTEST_MIGRATOR_DSN
            valueFrom: {secretKeyRef: {name: libtest-migrator-dsn, key: dsn}}
      - equal: {path: spec.template.spec.restartPolicy, value: Never}
      - equal: {path: "spec.template.metadata.labels[\"app.kubernetes.io/name\"]", value: libtest-migrate}
      - equal: {path: spec.template.spec.containers[0].securityContext.readOnlyRootFilesystem, value: true}
  - it: uses the same digest as the Deployment
    set:
      migration: {enabled: true, dsnSecret: libtest-migrator-dsn}
      libtest: {image: ghcr.io/acme/banking-go/core, digest: "sha256:3333333333333333333333333333333333333333333333333333333333333333"}
    documentSelector: {path: kind, value: Job}
    asserts:
      - equal:
          path: spec.template.spec.containers[0].image
          value: ghcr.io/acme/banking-go/core@sha256:3333333333333333333333333333333333333333333333333333333333333333
  - it: requires migration.dsnSecret
    set:
      migration: {enabled: true, dsnSecret: ""}
    asserts:
      - failedTemplate: {errorPattern: "migration.dsnSecret is required"}
```

`deploy/helm/_libtest/tests/httproute_test.yaml`:
```yaml
suite: lib HTTPRoute (Gateway API v1.6)
templates:
  - templates/all.yaml
tests:
  - it: attaches route.host to the Traefik websecure listener
    set:
      route: {enabled: true, host: api.kind.localhost, pathPrefix: /}
    documentSelector: {path: kind, value: HTTPRoute}
    asserts:
      - equal: {path: apiVersion, value: gateway.networking.k8s.io/v1}
      - equal: {path: spec.parentRefs[0], value: {name: traefik-gateway, namespace: traefik, sectionName: websecure}}
      - equal: {path: spec.hostnames, value: [api.kind.localhost]}
      - equal: {path: spec.rules[0].matches[0].path, value: {type: PathPrefix, value: /}}
      - equal: {path: spec.rules[0].backendRefs[0], value: {name: libtest, port: 8081}}
  - it: requires route.host when enabled
    set:
      route: {enabled: true, host: "", pathPrefix: /}
    asserts:
      - failedTemplate: {errorPattern: "route.host is required"}
```

`deploy/helm/_libtest/tests/pdb_test.yaml`:
```yaml
suite: lib PodDisruptionBudget
templates:
  - templates/all.yaml
tests:
  - it: keeps one pod available when there are at least 2 replicas
    set:
      replicas: 2
    documentSelector: {path: kind, value: PodDisruptionBudget}
    asserts:
      - equal: {path: spec.minAvailable, value: 1}
      - equal: {path: "spec.selector.matchLabels[\"app.kubernetes.io/name\"]", value: libtest}
  - it: renders no PDB for a single replica (kind)
    asserts:
      - hasDocuments: {count: 3}
```

`deploy/helm/_libtest/tests/certificate_test.yaml`:
```yaml
suite: lib internal mTLS certificate
templates:
  - templates/all.yaml
tests:
  - it: issues a client+server certificate from the internal CA and mounts it
    release:
      namespace: banking
    set:
      mtls: {enabled: true}
    asserts:
      - hasDocuments: {count: 4}
      - equal: {path: spec.issuerRef, value: {group: cert-manager.io, kind: ClusterIssuer, name: bg-internal-ca}}
        documentSelector: {path: kind, value: Certificate}
      - equal: {path: spec.secretName, value: libtest-mtls}
        documentSelector: {path: kind, value: Certificate}
      - equal: {path: spec.usages, value: [server auth, client auth]}
        documentSelector: {path: kind, value: Certificate}
      - contains:
          path: spec.dnsNames
          content: libtest.banking.svc
        documentSelector: {path: kind, value: Certificate}
      - contains:
          path: spec.template.spec.containers[0].volumeMounts
          content: {name: mtls, mountPath: /etc/bg/mtls, readOnly: true}
        documentSelector: {path: kind, value: Deployment}
```

- [ ] **Step 2: Chạy để thấy fail**

Run: `make helm-test`
Expected: FAIL — các suite mới báo `document not found`/`hasDocuments` sai.

- [ ] **Step 3: Implement template**

`deploy/helm/_lib/templates/_httproute.tpl`:
```yaml
{{- define "lib.httproute" -}}
{{- if .Values.route.enabled }}
{{- $gw := .Values.global.gateway | default dict }}
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
spec:
  parentRefs:
    - name: {{ $gw.name | default "traefik-gateway" }}
      namespace: {{ $gw.namespace | default "traefik" }}
      sectionName: {{ $gw.sectionName | default "websecure" }}
  hostnames:
    - {{ required "route.host is required when route.enabled" .Values.route.host | quote }}
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: {{ .Values.route.pathPrefix | default "/" }}
      backendRefs:
        - name: {{ include "lib.name" . }}
          port: {{ required "ports.app is required when route.enabled" .Values.ports.app }}
{{- end }}
{{- end -}}
```

`deploy/helm/_lib/templates/_pdb.tpl`:
```yaml
{{- define "lib.pdb" -}}
{{- if gt (int .Values.replicas) 1 }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "lib.name" . }}
  labels:
    {{- include "lib.labels" . | nindent 4 }}
spec:
  minAvailable: 1
  selector:
    matchLabels:
      {{- include "lib.selectorLabels" . | nindent 6 }}
{{- end }}
{{- end -}}
```

`deploy/helm/_lib/templates/_migration.tpl`:
```yaml
{{/* PreSync migration Job (AD-26, deployment.md § Migration): same digest, migrator role, re-runnable. */}}
{{- define "lib.migration" -}}
{{- if .Values.migration.enabled }}
{{- $cmd := required "command is required when migration.enabled" .Values.command }}
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "lib.name" . }}-migrate
  labels:
    {{- include "lib.labels" . | nindent 4 }}
    app.kubernetes.io/component: migration
  annotations:
    # Argo CD: PreSync hook, recreated on every sync; a failure stops the sync and the old version keeps running.
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation
    argocd.argoproj.io/sync-wave: "-1"
    # Plain helm (make kind-apps before GitOps): same ordering through Helm hooks; Argo CD prefers its own annotations.
    helm.sh/hook: pre-install,pre-upgrade
    helm.sh/hook-delete-policy: before-hook-creation
    helm.sh/hook-weight: "-1"
spec:
  backoffLimit: 2
  activeDeadlineSeconds: 600
  template:
    metadata:
      labels:
        app.kubernetes.io/name: {{ include "lib.name" . }}-migrate
        app.kubernetes.io/part-of: banking-go
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      {{- with .Values.global.imagePullSecrets }}
      imagePullSecrets:
        {{- range . }}
        - name: {{ . }}
        {{- end }}
      {{- end }}
      securityContext:
        runAsNonRoot: true
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: migrate
          image: {{ include "lib.image" . }}
          imagePullPolicy: {{ .Values.image.pullPolicy | default "IfNotPresent" }}
          command: [{{ first $cmd | quote }}, "migrate", "up"]
          env:
            - name: {{ include "lib.envPrefix" . }}MIGRATOR_DSN
              valueFrom:
                secretKeyRef:
                  name: {{ required "migration.dsnSecret is required when migration.enabled" .Values.migration.dsnSecret }}
                  key: dsn
          resources:
            requests: {cpu: 10m, memory: 32Mi}
            limits: {memory: 128Mi}
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop: [ALL]
          volumeMounts:
            - name: tmp
              mountPath: /tmp
      volumes:
        - name: tmp
          emptyDir: {}
{{- end }}
{{- end -}}
```

`deploy/helm/_lib/templates/_certificate.tpl`:
```yaml
{{/* Internal mTLS leaf (AD-10, deployment.md § Domain & TLS): 90 days, auto-renewed by cert-manager. */}}
{{- define "lib.certificate" -}}
{{- if .Values.mtls.enabled }}
{{- $name := include "lib.name" . }}
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: {{ $name }}-mtls
  labels:
    {{- include "lib.labels" . | nindent 4 }}
spec:
  secretName: {{ $name }}-mtls
  issuerRef:
    group: cert-manager.io
    kind: ClusterIssuer
    name: {{ .Values.mtls.issuer | default "bg-internal-ca" }}
  commonName: {{ $name }}
  duration: 2160h
  renewBefore: 360h
  privateKey:
    algorithm: ECDSA
    size: 256
    rotationPolicy: Always
  usages: [server auth, client auth]
  dnsNames:
    - {{ $name }}
    - {{ printf "%s.%s.svc" $name .Release.Namespace }}
    - {{ printf "%s.%s.svc.cluster.local" $name .Release.Namespace }}
{{- end }}
{{- end -}}
```

`deploy/helm/_lib/templates/_all.tpl` — thay khối `$docs`:
```yaml
{{- $docs := list
    (include "lib.serviceaccount" .)
    (include "lib.service" .)
    (include "lib.configmap" .)
    (include "lib.deployment" .)
    (include "lib.pdb" .)
    (include "lib.httproute" .)
    (include "lib.migration" .)
    (include "lib.certificate" .) -}}
```

`deploy/helm/_lib/templates/_deployment.tpl` — ngay sau khối `{{- range $file, $cfg := .Values.configFiles }} … {{- end }}` trong `volumeMounts`, thêm:
```yaml
            {{- if .Values.mtls.enabled }}
            - name: mtls
              mountPath: /etc/bg/mtls
              readOnly: true
            {{- end }}
```
và ngay sau khối `{{- if .Values.configFiles }} … {{- end }}` trong `volumes`, thêm:
```yaml
        {{- if .Values.mtls.enabled }}
        - name: mtls
          secret:
            secretName: {{ include "lib.name" . }}-mtls
        {{- end }}
```

- [ ] **Step 4: Chạy test pass**

Run: `make helm-test`
Expected: `Test Suites: 6 passed`, không test fail.

- [ ] **Step 5: Commit**

```bash
git add deploy/helm/_lib deploy/helm/_libtest
git commit -m "feat(platform): lib chart httproute, pdb, presync migration job, mtls certificate"
```

**Lệnh kiểm chứng:** `make helm-test`

---

### T7: 10 chart mỏng + `values-kind.yaml` + `make helm-lint helm-test`

**Files:**
- Create (× 10, `<d>` ∈ core, core-worker, public-api, admin-api, mock-napas, mock-ekyc, mock-otp, mock-gateway, web-customer, web-admin): `deploy/helm/<d>/Chart.yaml`, `deploy/helm/<d>/templates/all.yaml`, `deploy/helm/<d>/values.yaml`, `deploy/helm/<d>/values-kind.yaml`
- Create: `deploy/helm/public-api/tests/public-api_test.yaml`, `deploy/helm/core-worker/tests/core-worker_test.yaml`, `deploy/helm/web-customer/tests/web-customer_test.yaml`
- Modify: `Makefile` (`HELM_CHARTS`, `KUBECONFORM_FLAGS`, `helm-deps`, `helm-lint`)

**Interfaces:**
- Consumes: `lib.all` + values interface (T5, T6); `deploy/deployables.tsv` (T3); command/port của image (T3, T4).
- Produces: 10 chart `deploy/helm/<deployable>` (tên chart = tên deployable = khóa trong `deploy/releases/kind.yaml`); Secret tên cố định mà T10 phải tạo: `core-migrator-dsn`, `public-api-migrator-dsn`, `admin-api-migrator-dsn` (key `dsn`), `core-env`, `core-worker-env`, `public-api-env`, `admin-api-env` (namespace `banking`); host `api.kind.localhost` (public-api), `admin-api.kind.localhost` (admin-api), `app.kind.localhost` (web-customer), `admin.kind.localhost` (web-admin); target `make helm-lint`, `make helm-test`, `make helm-deps`.

- [ ] **Step 1: Viết test thất bại**

`deploy/helm/public-api/tests/public-api_test.yaml`:
```yaml
suite: public-api chart (env kind)
templates:
  - templates/all.yaml
values:
  - ../values-kind.yaml
release:
  name: public-api
  namespace: banking
tests:
  - it: takes the digest from deploy/releases/kind.yaml
    set:
      public-api: {image: ghcr.io/acme/banking-go/public-api, digest: "sha256:4444444444444444444444444444444444444444444444444444444444444444"}
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal:
          path: spec.template.spec.containers[0].image
          value: ghcr.io/acme/banking-go/public-api@sha256:4444444444444444444444444444444444444444444444444444444444444444
      - equal: {path: spec.replicas, value: 1}
      - contains:
          path: spec.template.spec.containers[0].env
          content: {name: BG_PUBLIC_API_ENVIRONMENT, value: kind}
      - equal: {path: "spec.template.spec.containers[0].envFrom[0].secretRef.name", value: public-api-env}
  - it: routes api.kind.localhost to the HTTP port
    set:
      image.tag: local
    documentSelector: {path: kind, value: HTTPRoute}
    asserts:
      - equal: {path: spec.hostnames, value: [api.kind.localhost]}
      - equal: {path: spec.rules[0].backendRefs[0].port, value: 8081}
  - it: migrates with public-api migrate up and the migrator DSN secret
    set:
      image.tag: local
    documentSelector: {path: kind, value: Job}
    asserts:
      - equal: {path: spec.template.spec.containers[0].command, value: [/usr/local/bin/public-api, migrate, up]}
      - equal: {path: spec.template.spec.containers[0].env[0].valueFrom.secretKeyRef.name, value: public-api-migrator-dsn}
```

`deploy/helm/core-worker/tests/core-worker_test.yaml`:
```yaml
suite: core-worker chart (env kind)
templates:
  - templates/all.yaml
values:
  - ../values-kind.yaml
tests:
  - it: runs the core image with the core-worker command (D-23)
    set:
      core-worker: {image: ghcr.io/acme/banking-go/core, digest: "sha256:5555555555555555555555555555555555555555555555555555555555555555"}
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal:
          path: spec.template.spec.containers[0].image
          value: ghcr.io/acme/banking-go/core@sha256:5555555555555555555555555555555555555555555555555555555555555555
      - equal: {path: spec.template.spec.containers[0].command, value: [/usr/local/bin/core-worker]}
      - equal: {path: spec.template.spec.containers[0].ports, value: [{name: admin, containerPort: 9191}]}
  - it: has no route and no migration (core migrates the shared database)
    set:
      image.tag: local
    asserts:
      - hasDocuments: {count: 3}
```

`deploy/helm/web-customer/tests/web-customer_test.yaml`:
```yaml
suite: web-customer chart (env kind)
templates:
  - templates/all.yaml
values:
  - ../values-kind.yaml
tests:
  - it: mounts config.js pointing at api.kind.localhost
    set:
      image.tag: local
    documentSelector: {path: kind, value: ConfigMap}
    asserts:
      - matchRegex: {path: "data[\"config.js\"]", pattern: "apiBaseUrl: 'https://api.kind.localhost'"}
  - it: serves app.kind.localhost on nginx port 8080 with /healthz probes and CSP origin
    set:
      image.tag: local
    documentSelector: {path: kind, value: Deployment}
    asserts:
      - equal: {path: spec.template.spec.containers[0].readinessProbe.httpGet.path, value: /healthz}
      - notExists: {path: spec.template.spec.containers[0].command}
      - contains:
          path: spec.template.spec.containers[0].env
          content: {name: BG_API_ORIGIN, value: "https://api.kind.localhost"}
  - it: routes app.kind.localhost
    set:
      image.tag: local
    documentSelector: {path: kind, value: HTTPRoute}
    asserts:
      - equal: {path: spec.hostnames, value: [app.kind.localhost]}
```

Run: `make helm-test`
Expected: FAIL — `Chart.yaml file is missing` cho `deploy/helm/public-api`.

- [ ] **Step 2: Tạo Chart.yaml + templates cho 10 chart** (sinh từ `deploy/deployables.tsv`)

```bash
while read -r name _rest; do
  [[ -z $name || $name == \#* ]] && continue
  mkdir -p "deploy/helm/$name/templates"
  cat > "deploy/helm/$name/Chart.yaml" <<EOF
apiVersion: v2
name: $name
description: banking-go deployable $name (AD-1). Values only; templates come from the lib library chart.
type: application
version: 0.1.0
appVersion: "0.1.0"
dependencies:
  - name: lib
    version: 0.1.0
    repository: file://../_lib
EOF
  printf '{{ include "lib.all" . }}\n' > "deploy/helm/$name/templates/all.yaml"
done < deploy/deployables.tsv
```

- [ ] **Step 3: `values.yaml` (giá trị chung mọi env)**

`deploy/helm/core/values.yaml`:
```yaml
# core: gRPC (AD-1). Values interface: spec platform v1 "Thiết kế"; templates: deploy/helm/_lib.
global:
  ghOwner: ""
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/core"
  digest: ""
  tag: ""
  pullPolicy: IfNotPresent
command: ["/usr/local/bin/core"]
ports: {app: 8090, admin: 9190}
replicas: 2
resources:
  requests: {cpu: 50m, memory: 64Mi}
  limits: {memory: 256Mi}
env: {}
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: false, host: "", pathPrefix: /}
migration: {enabled: true, dsnSecret: core-migrator-dsn}
mtls: {enabled: false}
shutdownTimeoutSeconds: 30
```

`deploy/helm/core-worker/values.yaml`:
```yaml
# core-worker: relay, consumers, jobs, webhook listener (AD-1); same image as core (D-23).
global:
  ghOwner: ""
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/core"
  digest: ""
  tag: ""
  pullPolicy: IfNotPresent
command: ["/usr/local/bin/core-worker"]
ports: {app: null, admin: 9191}
replicas: 2
resources:
  requests: {cpu: 50m, memory: 64Mi}
  limits: {memory: 256Mi}
env: {}
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: false, host: "", pathPrefix: /}
migration: {enabled: false, dsnSecret: ""}
mtls: {enabled: false}
shutdownTimeoutSeconds: 30
```

`deploy/helm/public-api/values.yaml`:
```yaml
# public-api: customer REST edge (AD-1).
global:
  ghOwner: ""
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/public-api"
  digest: ""
  tag: ""
  pullPolicy: IfNotPresent
command: ["/usr/local/bin/public-api"]
ports: {app: 8081, admin: 9181}
replicas: 2
resources:
  requests: {cpu: 50m, memory: 64Mi}
  limits: {memory: 256Mi}
env: {}
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: true, host: "", pathPrefix: /}
migration: {enabled: true, dsnSecret: public-api-migrator-dsn}
mtls: {enabled: false}
shutdownTimeoutSeconds: 30
```

`deploy/helm/admin-api/values.yaml`:
```yaml
# admin-api: back-office REST edge (AD-1).
global:
  ghOwner: ""
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/admin-api"
  digest: ""
  tag: ""
  pullPolicy: IfNotPresent
command: ["/usr/local/bin/admin-api"]
ports: {app: 8082, admin: 9182}
replicas: 2
resources:
  requests: {cpu: 50m, memory: 64Mi}
  limits: {memory: 256Mi}
env: {}
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: true, host: "", pathPrefix: /}
migration: {enabled: true, dsnSecret: admin-api-migrator-dsn}
mtls: {enabled: false}
shutdownTimeoutSeconds: 30
```

`deploy/helm/mock-napas/values.yaml`:
```yaml
# mock-napas: NAPAS partner mock (AD-12); mocks image.
global:
  ghOwner: ""
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/mocks"
  digest: ""
  tag: ""
  pullPolicy: IfNotPresent
command: ["/usr/local/bin/mock-napas"]
ports: {app: 8101, admin: 9201}
replicas: 1
resources:
  requests: {cpu: 10m, memory: 32Mi}
  limits: {memory: 128Mi}
env: {}
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: false, host: "", pathPrefix: /}
migration: {enabled: false, dsnSecret: ""}
mtls: {enabled: false}
shutdownTimeoutSeconds: 30
```

`deploy/helm/mock-ekyc/values.yaml`:
```yaml
# mock-ekyc: eKYC partner mock (AD-12); mocks image.
global:
  ghOwner: ""
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/mocks"
  digest: ""
  tag: ""
  pullPolicy: IfNotPresent
command: ["/usr/local/bin/mock-ekyc"]
ports: {app: 8102, admin: 9202}
replicas: 1
resources:
  requests: {cpu: 10m, memory: 32Mi}
  limits: {memory: 128Mi}
env: {}
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: false, host: "", pathPrefix: /}
migration: {enabled: false, dsnSecret: ""}
mtls: {enabled: false}
shutdownTimeoutSeconds: 30
```

`deploy/helm/mock-otp/values.yaml`:
```yaml
# mock-otp: OTP/SMS partner mock (AD-12); mocks image.
global:
  ghOwner: ""
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/mocks"
  digest: ""
  tag: ""
  pullPolicy: IfNotPresent
command: ["/usr/local/bin/mock-otp"]
ports: {app: 8103, admin: 9203}
replicas: 1
resources:
  requests: {cpu: 10m, memory: 32Mi}
  limits: {memory: 128Mi}
env: {}
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: false, host: "", pathPrefix: /}
migration: {enabled: false, dsnSecret: ""}
mtls: {enabled: false}
shutdownTimeoutSeconds: 30
```

`deploy/helm/mock-gateway/values.yaml`:
```yaml
# mock-gateway: payment gateway partner mock (AD-12); mocks image.
global:
  ghOwner: ""
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/mocks"
  digest: ""
  tag: ""
  pullPolicy: IfNotPresent
command: ["/usr/local/bin/mock-gateway"]
ports: {app: 8104, admin: 9204}
replicas: 1
resources:
  requests: {cpu: 10m, memory: 32Mi}
  limits: {memory: 128Mi}
env: {}
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: false, host: "", pathPrefix: /}
migration: {enabled: false, dsnSecret: ""}
mtls: {enabled: false}
shutdownTimeoutSeconds: 30
```

`deploy/helm/web-customer/values.yaml`:
```yaml
# web-customer: customer SPA on nginx-unprivileged (AD-14); config.js is mounted from configFiles.
global:
  ghOwner: ""
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/web-customer"
  digest: ""
  tag: ""
  pullPolicy: IfNotPresent
command: []
ports: {app: 8080, admin: null}
replicas: 2
resources:
  requests: {cpu: 10m, memory: 16Mi}
  limits: {memory: 64Mi}
env: {}
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: true, host: "", pathPrefix: /}
migration: {enabled: false, dsnSecret: ""}
mtls: {enabled: false}
shutdownTimeoutSeconds: 10
```

`deploy/helm/web-admin/values.yaml`:
```yaml
# web-admin: back-office SPA on nginx-unprivileged (AD-14); config.js is mounted from configFiles.
global:
  ghOwner: ""
  imagePullSecrets: []
  otelEndpoint: ""
  gateway: {name: traefik-gateway, namespace: traefik, sectionName: websecure}
image:
  repository: "ghcr.io/{{ .Values.global.ghOwner }}/banking-go/web-admin"
  digest: ""
  tag: ""
  pullPolicy: IfNotPresent
command: []
ports: {app: 8080, admin: null}
replicas: 2
resources:
  requests: {cpu: 10m, memory: 16Mi}
  limits: {memory: 64Mi}
env: {}
envFromSecrets: []
configFiles: {}
secretsRevision: "0"
route: {enabled: true, host: "", pathPrefix: /}
migration: {enabled: false, dsnSecret: ""}
mtls: {enabled: false}
shutdownTimeoutSeconds: 10
```

- [ ] **Step 4: `values-kind.yaml`** (digest đến từ `deploy/releases/kind.yaml` qua Argo CD; S1/S2 dùng `image.tag=local` do `kind-apps` truyền)

`deploy/helm/core/values-kind.yaml`:
```yaml
# env kind (ADR 0011): 1 replica, low requests.
replicas: 1
resources:
  requests: {cpu: 10m, memory: 32Mi}
  limits: {memory: 128Mi}
env:
  BG_CORE_ENVIRONMENT: kind
envFromSecrets: [core-env]
```
`deploy/helm/core-worker/values-kind.yaml`:
```yaml
# env kind (ADR 0011): 1 replica, low requests.
replicas: 1
resources:
  requests: {cpu: 10m, memory: 32Mi}
  limits: {memory: 128Mi}
env:
  BG_CORE_WORKER_ENVIRONMENT: kind
envFromSecrets: [core-worker-env]
```
`deploy/helm/public-api/values-kind.yaml`:
```yaml
# env kind (ADR 0011): 1 replica, low requests, https://api.kind.localhost.
replicas: 1
resources:
  requests: {cpu: 10m, memory: 32Mi}
  limits: {memory: 128Mi}
env:
  BG_PUBLIC_API_ENVIRONMENT: kind
envFromSecrets: [public-api-env]
route: {enabled: true, host: api.kind.localhost, pathPrefix: /}
```
`deploy/helm/admin-api/values-kind.yaml`:
```yaml
# env kind (ADR 0011): 1 replica, low requests, https://admin-api.kind.localhost.
replicas: 1
resources:
  requests: {cpu: 10m, memory: 32Mi}
  limits: {memory: 128Mi}
env:
  BG_ADMIN_API_ENVIRONMENT: kind
envFromSecrets: [admin-api-env]
route: {enabled: true, host: admin-api.kind.localhost, pathPrefix: /}
```
`deploy/helm/mock-napas/values-kind.yaml`:
```yaml
# env kind (ADR 0011).
env:
  BG_MOCK_NAPAS_ENVIRONMENT: kind
```
`deploy/helm/mock-ekyc/values-kind.yaml`:
```yaml
# env kind (ADR 0011).
env:
  BG_MOCK_EKYC_ENVIRONMENT: kind
```
`deploy/helm/mock-otp/values-kind.yaml`:
```yaml
# env kind (ADR 0011).
env:
  BG_MOCK_OTP_ENVIRONMENT: kind
```
`deploy/helm/mock-gateway/values-kind.yaml`:
```yaml
# env kind (ADR 0011).
env:
  BG_MOCK_GATEWAY_ENVIRONMENT: kind
```
`deploy/helm/web-customer/values-kind.yaml`:
```yaml
# env kind (ADR 0011): https://app.kind.localhost → API https://api.kind.localhost.
replicas: 1
env:
  BG_API_ORIGIN: https://api.kind.localhost
route: {enabled: true, host: app.kind.localhost, pathPrefix: /}
configFiles:
  config.js:
    mountPath: /usr/share/nginx/html/config.js
    content: |
      window.__BG_CONFIG__ = { apiBaseUrl: 'https://api.kind.localhost', env: 'kind', release: 'kind' }
```
`deploy/helm/web-admin/values-kind.yaml`:
```yaml
# env kind (ADR 0011): https://admin.kind.localhost → API https://admin-api.kind.localhost.
replicas: 1
env:
  BG_API_ORIGIN: https://admin-api.kind.localhost
route: {enabled: true, host: admin.kind.localhost, pathPrefix: /}
configFiles:
  config.js:
    mountPath: /usr/share/nginx/html/config.js
    content: |
      window.__BG_CONFIG__ = { apiBaseUrl: 'https://admin-api.kind.localhost', env: 'kind', release: 'kind' }
```

- [ ] **Step 5: `Makefile`** — thay khối `helm-test` của T5 bằng:

```make
HELM_CHARTS := $(sort $(filter-out deploy/helm/_%,$(wildcard deploy/helm/*)))
KUBECONFORM_FLAGS := -strict -summary -kubernetes-version 1.36.0 -schema-location default \
	-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

.PHONY: helm-deps helm-lint helm-test
helm-deps: tools-k8s
	@for c in deploy/helm/_libtest $(HELM_CHARTS); do $(HELM) dependency build $$c >/dev/null; done
helm-lint: helm-deps ## helm lint --strict + kubeconform (k8s 1.36 + CRD catalog) of every chart with values-kind.yaml
	@for c in $(HELM_CHARTS); do \
		n=$$(basename $$c); echo "== $$n"; \
		$(HELM) lint --strict $$c -f $$c/values-kind.yaml --set global.ghOwner=lint-owner --set image.tag=lint; \
		$(HELM) template $$n $$c -n banking -f $$c/values-kind.yaml --set global.ghOwner=lint-owner --set image.tag=lint \
			| $(KUBECONFORM) $(KUBECONFORM_FLAGS); \
	done
helm-test: helm-deps ## helm-unittest: lib fixture chart + every chart with tests/
	@for c in deploy/helm/_libtest $(HELM_CHARTS); do \
		if [ -d $$c/tests ]; then echo "== $$c"; $(HELM) unittest $$c; fi; \
	done
```

- [ ] **Step 6: Chạy lint + test**

Run: `make helm-lint helm-test`
Expected: mỗi chart `1 chart(s) linted, 0 chart(s) failed` và kubeconform `Summary: N resources found … Valid: N, Invalid: 0, Errors: 0`; helm-unittest 4 chart pass.

- [ ] **Step 7: Commit**

```bash
git add deploy/helm Makefile
git commit -m "feat(platform): thin helm charts for the 10 deployables with kind values"
```

**Lệnh kiểm chứng:** `make helm-lint helm-test`

---

### T8: kind config + `bootstrap.sh` + `make kind-up kind-down`

**Files:**
- Create: `deploy/kind/kind-config.yaml`, `deploy/kind/bootstrap.sh`, `deploy/kind/sealed-key.sh`, `deploy/kind/check-cluster.sh`, `deploy/platform/argocd/values-kind.yaml`, `scripts/lib/kind.sh`
- Modify: `Makefile` (`KIND_CLUSTER`, `kind-up`, `kind-down`)

**Interfaces:**
- Consumes: `bin/{kind,kubectl,helm,kubeseal,yq}` (T1).
- Produces: cluster `banking-go` (context `kind-banking-go`, 3 node v1.36.4, control-plane label `ingress-ready=true`, host 80/443 → control-plane); `deploy/kind/sealed-key.sh restore|backup` (file `~/.config/banking-go/sealed-secrets-key.yaml` + `sealed-secrets-cert.pem`, ghi đè thư mục bằng `BG_CONFIG_DIR`); `scripts/lib/kind.sh` hàm `require_kind_context`; Argo CD release `argocd` (ns `argocd`, chart argo-cd 10.9.6 = app v3.5.3); target `make kind-up`, `make kind-down`.

- [ ] **Step 1: Viết check thất bại**

`scripts/lib/kind.sh`:
```bash
# Shared helpers for kind scripts (source me after putting ./bin on PATH).
KIND_CLUSTER=${KIND_CLUSTER:-banking-go}
KIND_CONTEXT="kind-$KIND_CLUSTER"

# require_kind_context exits unless kubectl points at the kind cluster (never touch another cluster).
require_kind_context() {
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null || true)
  [[ $ctx == "$KIND_CONTEXT" ]] || { echo "kubectl context is '$ctx', want $KIND_CONTEXT (run make kind-up)" >&2; exit 1; }
}
```

`deploy/kind/check-cluster.sh`:
```bash
#!/usr/bin/env bash
# Asserts the kind cluster matches spec §7: k8s 1.36, 1 control-plane + 2 workers, host 80/443, Argo CD running.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
require_kind_context
[[ $(kubectl get nodes --no-headers | wc -l) -eq 3 ]] || fail "want 3 nodes"
[[ $(kubectl get nodes -l node-role.kubernetes.io/control-plane --no-headers | wc -l) -eq 1 ]] || fail "want 1 control-plane"
versions=$(kubectl get nodes -o jsonpath='{range .items[*]}{.status.nodeInfo.kubeletVersion}{"\n"}{end}' | sort -u)
[[ $versions == v1.36.4 ]] || fail "kubelet versions: $versions (want v1.36.4)"
[[ $(kubectl get nodes -l ingress-ready=true -o name) == "node/$KIND_CLUSTER-control-plane" ]] || fail "control-plane must carry ingress-ready=true"
ports=$(docker inspect "$KIND_CLUSTER-control-plane" --format '{{json .HostConfig.PortBindings}}')
[[ $ports == *'"80/tcp"'* && $ports == *'"443/tcp"'* ]] || fail "host ports 80/443 not mapped: $ports"
kubectl -n argocd rollout status deploy/argocd-server --timeout=180s >/dev/null || fail "argocd-server not available"
echo "ok   kind cluster $KIND_CLUSTER: 3 nodes v1.36.4, 80/443 on control-plane, Argo CD running"
```

Run: `chmod +x deploy/kind/check-cluster.sh && deploy/kind/check-cluster.sh`
Expected: `FAIL`/exit 1 — `kubectl context is '…', want kind-banking-go`.

- [ ] **Step 2: `deploy/kind/kind-config.yaml`**

```yaml
# kind env (ADR 0011, spec §7): Kubernetes 1.36, 1 control-plane + 2 workers, Traefik hostPort 80/443 on the control-plane.
# kindest/node v1.36.4 is the image published with kind v0.33.0 (pinned by digest).
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: banking-go
nodes:
  - role: control-plane
    image: kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
    labels:
      ingress-ready: "true"
    extraPortMappings:
      - {containerPort: 80, hostPort: 80, protocol: TCP}
      - {containerPort: 443, hostPort: 443, protocol: TCP}
  - role: worker
    image: kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
  - role: worker
    image: kindest/node:v1.36.4@sha256:099e049362a1526b2db71494e1947aae99bd16290d7c895f2b7ea312e3cbfaed
```

- [ ] **Step 3: `deploy/kind/sealed-key.sh`**

```bash
#!/usr/bin/env bash
# Backup/restore of the kind Sealed Secrets controller key outside the repo (spec §9, ADR 0011).
#   sealed-key.sh restore   apply the saved key into kube-system before the controller starts (no-op without a backup)
#   sealed-key.sh backup    save the controller key(s) + public cert to $BG_CONFIG_DIR (default ~/.config/banking-go), 0600
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
DIR=${BG_CONFIG_DIR:-$HOME/.config/banking-go}
KEY="$DIR/sealed-secrets-key.yaml"
CERT="$DIR/sealed-secrets-cert.pem"
NS=kube-system
LABEL=sealedsecrets.bitnami.com/sealed-secrets-key

case "${1:-}" in
  restore)
    if [[ -s "$KEY" ]]; then
      kubectl -n "$NS" apply -f "$KEY" >/dev/null
      echo "[sealed-key] restored controller key from $KEY"
    else
      echo "[sealed-key] no backup at $KEY: the controller will create a new key; re-run 'make seal' and commit"
    fi ;;
  backup)
    kubectl -n "$NS" get secret -l "$LABEL" -o name | grep -q . || { echo "[sealed-key] no controller key in $NS yet" >&2; exit 1; }
    mkdir -p "$DIR" && chmod 700 "$DIR"
    umask 077
    kubectl -n "$NS" get secret -l "$LABEL" -o yaml \
      | yq 'del(.items[].metadata.resourceVersion, .items[].metadata.uid, .items[].metadata.creationTimestamp, .items[].metadata.managedFields, .metadata)' \
      > "$KEY.tmp"
    mv "$KEY.tmp" "$KEY"
    kubeseal --controller-namespace "$NS" --controller-name sealed-secrets-controller --fetch-cert > "$CERT.tmp"
    mv "$CERT.tmp" "$CERT"
    echo "[sealed-key] backed up to $KEY and $CERT" ;;
  *) echo "usage: $0 restore|backup" >&2; exit 2 ;;
esac
```

- [ ] **Step 4: `deploy/platform/argocd/values-kind.yaml`**

```yaml
# Argo CD v3.5 on kind (chart argo-cd 10.9.6): single replicas, no Dex/notifications, TLS terminated at Traefik.
global:
  domain: argocd.kind.localhost
configs:
  params:
    server.insecure: true
  cm:
    timeout.reconciliation: 60s
dex:
  enabled: false
notifications:
  enabled: false
controller:
  resources:
    requests: {cpu: 100m, memory: 256Mi}
    limits: {memory: 768Mi}
server:
  resources:
    requests: {cpu: 20m, memory: 64Mi}
    limits: {memory: 256Mi}
repoServer:
  resources:
    requests: {cpu: 20m, memory: 128Mi}
    limits: {memory: 512Mi}
applicationSet:
  resources:
    requests: {cpu: 10m, memory: 32Mi}
    limits: {memory: 128Mi}
redis:
  resources:
    requests: {cpu: 10m, memory: 32Mi}
    limits: {memory: 128Mi}
```

- [ ] **Step 5: `deploy/kind/bootstrap.sh`**

```bash
#!/usr/bin/env bash
# Idempotent bootstrap of the kind env (ADR 0011, spec §7):
#   1. create kind cluster banking-go (k8s 1.36.4, 1 CP + 2 workers, host 80/443) if missing
#   2. restore the Sealed Secrets controller key from ~/.config/banking-go (before any controller starts)
#   3. install/upgrade Argo CD (chart pinned); the app-of-apps root is applied from T21 on
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
ARGOCD_CHART_VERSION=10.9.6
log() { printf '[bootstrap] %s\n' "$*"; }

if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
  log "cluster $KIND_CLUSTER exists"
else
  log "creating cluster $KIND_CLUSTER"
  kind create cluster --config "$ROOT/deploy/kind/kind-config.yaml" --wait 180s
fi
kubectl config use-context "$KIND_CONTEXT" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=180s >/dev/null

"$ROOT/deploy/kind/sealed-key.sh" restore

log "installing Argo CD (chart argo-cd $ARGOCD_CHART_VERSION)"
helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd --create-namespace -f "$ROOT/deploy/platform/argocd/values-kind.yaml" --wait --timeout 10m
log "done: $(kubectl get nodes --no-headers | wc -l) nodes, context $KIND_CONTEXT"
```

- [ ] **Step 6: `Makefile`** — thêm khối sau Helm:

```make
# ---------------------------------------------------------------------------------------------
# kind env (ADR 0011). Never points at another cluster: scripts check the kubectl context.
KIND_CLUSTER := banking-go
GH_OWNER ?=

.PHONY: kind-up kind-down
kind-up: tools-k8s ## Create/refresh the kind cluster (idempotent): k8s 1.36, restore Sealed Secrets key, Argo CD
	deploy/kind/bootstrap.sh
	deploy/kind/check-cluster.sh
kind-down: tools-k8s ## Back up the Sealed Secrets key (if any), then delete the kind cluster
	-deploy/kind/sealed-key.sh backup
	$(KIND) delete cluster --name $(KIND_CLUSTER)
```

- [ ] **Step 7: Chạy 2 lần (idempotent) + check**

Run: `chmod +x deploy/kind/*.sh && make kind-up && make kind-up`
Expected: lần 1 `creating cluster banking-go` … `ok   kind cluster banking-go: 3 nodes v1.36.4, …`; lần 2 `cluster banking-go exists`, exit 0.

Run: `make kind-down && make kind-up`
Expected: kind-down in `[sealed-key] no controller key in kube-system yet` (chưa cài controller ở T8, được bỏ qua nhờ `-`), xóa cluster; kind-up dựng lại, exit 0.

- [ ] **Step 8: Commit**

```bash
git add deploy/kind deploy/platform/argocd scripts/lib/kind.sh Makefile
git commit -m "feat(platform): kind 1.36 cluster bootstrap with Argo CD and sealed key restore"
```

**Lệnh kiểm chứng:** `make kind-up && deploy/kind/check-cluster.sh`

---

### T9: Add-on wave -30/-20/-19/-18 + catalog + `make kind-platform kind-ca`

**Files:**
- Create: `deploy/argocd/kind/values.yaml` (catalog), `scripts/kind-platform.sh`, `scripts/vendor-manifests.sh`, `deploy/platform/vendor.lock`
- Create (vendored bằng script, không sửa tay): `deploy/platform/gateway-api/standard-install.yaml`, `deploy/platform/rabbitmq-operators/cluster-operator/cluster-operator.yml`, `deploy/platform/rabbitmq-operators/topology-operator/messaging-topology-operator-with-certmanager.yaml`
- Create: `deploy/platform/cert-manager/values-kind.yaml`, `deploy/platform/cert-manager-issuers/kind/issuers.yaml`, `deploy/platform/sealed-secrets/values-kind.yaml`, `deploy/platform/traefik/values-kind.yaml`, `deploy/platform/cloudnative-pg/values-kind.yaml`
- Create: `deploy/kind/check-platform.sh`
- Modify: `Makefile` (`kind-platform`, `kind-ca`)

**Interfaces:**
- Consumes: cluster + `require_kind_context` (T8), `sealed-key.sh backup` (T8).
- Produces: catalog `deploy/argocd/kind/values.yaml` với khóa `repoURL`, `targetRevision`, `ghOwner`, `addons[]` (`name`, `wave`, `namespace`, `chart.{repo,name,version}` + `values[]` + `releaseName` **hoặc** `path`; `wait` = đối số `kubectl wait`; `post` = lệnh chạy sau khi cài, chỉ script dùng); `scripts/kind-platform.sh [--max-wave N] [name…]`; Gateway `traefik/traefik-gateway` (listener `websecure`/`web`), ClusterIssuer `selfsigned`, `kind-ca`, `bg-internal-ca`; Secret TLS `traefik/wildcard-kind-localhost-tls`; controller `kube-system/sealed-secrets-controller`; CRD Gateway API v1.6.2, CNPG, RabbitMQ; target `make kind-platform`, `make kind-ca` (ghi `~/.config/banking-go/kind-ca.crt`).

- [ ] **Step 1: Viết check thất bại** — `deploy/kind/check-platform.sh`

```bash
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
v=$(kubectl get crd gateways.gateway.networking.k8s.io -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}')
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
[[ -s ${BG_CONFIG_DIR:-$HOME/.config/banking-go}/sealed-secrets-key.yaml ]] || fail "Sealed Secrets key not backed up"
ok "Sealed Secrets key backed up"
```

Run: `chmod +x deploy/kind/check-platform.sh && deploy/kind/check-platform.sh`
Expected: `FAIL: Gateway API CRDs bundle-version= (want v1.6.2)` (CRD chưa có → lỗi NotFound).

- [ ] **Step 2: Vendor manifest có khóa sha256**

`deploy/platform/vendor.lock`:
```text
# Upstream manifests vendored for Argo CD directory sources and `kubectl apply` (scripts/vendor-manifests.sh).
# dest                                                                                           sha256                                                            url
deploy/platform/gateway-api/standard-install.yaml                                               faede450fa178126aba41337737b97d351ebe87d93c910237ce1e072d1ca40d9  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.2/standard-install.yaml
deploy/platform/rabbitmq-operators/cluster-operator/cluster-operator.yml                         e99f04f46ecbf796b63c0f0e295bbae3d2aee3742897944cd1810cfcc44856ce  https://github.com/rabbitmq/cluster-operator/releases/download/v2.23.0/cluster-operator.yml
deploy/platform/rabbitmq-operators/topology-operator/messaging-topology-operator-with-certmanager.yaml 73a45a423b3abb9dddfa84248e60699f69a4dbcf3456830b9af62ef496e1e549  https://github.com/rabbitmq/messaging-topology-operator/releases/download/v1.20.3/messaging-topology-operator-with-certmanager.yaml
```

`scripts/vendor-manifests.sh`:
```bash
#!/usr/bin/env bash
# Downloads (default) or verifies (--check) the upstream manifests pinned in deploy/platform/vendor.lock.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
MODE=${1:-download}
status=0
while read -r dest sha url; do
  [[ -z "$dest" || "$dest" == \#* ]] && continue
  if [[ $MODE == download ]]; then
    mkdir -p "$ROOT/$(dirname "$dest")"
    curl -fsSL --retry 3 -o "$ROOT/$dest.tmp" "$url"
    echo "$sha  $ROOT/$dest.tmp" | sha256sum -c --quiet - || { rm -f "$ROOT/$dest.tmp"; echo "checksum mismatch: $url" >&2; exit 1; }
    mv "$ROOT/$dest.tmp" "$ROOT/$dest"; echo "vendored $dest"
  else
    if echo "$sha  $ROOT/$dest" | sha256sum -c --quiet - 2>/dev/null; then echo "ok   $dest"; else echo "FAIL: $dest differs from vendor.lock" >&2; status=1; fi
  fi
done < "$ROOT/deploy/platform/vendor.lock"
exit $status
```

Run: `chmod +x scripts/vendor-manifests.sh && scripts/vendor-manifests.sh && scripts/vendor-manifests.sh --check`
Expected: 3 dòng `vendored …` rồi 3 dòng `ok   …`.

- [ ] **Step 3: Values add-on**

`deploy/platform/cert-manager/values-kind.yaml`:
```yaml
# cert-manager v1.21.2 on kind (chart jetstack/cert-manager).
crds:
  enabled: true
replicaCount: 1
resources:
  requests: {cpu: 10m, memory: 64Mi}
  limits: {memory: 192Mi}
webhook:
  resources:
    requests: {cpu: 10m, memory: 32Mi}
    limits: {memory: 96Mi}
cainjector:
  resources:
    requests: {cpu: 10m, memory: 64Mi}
    limits: {memory: 192Mi}
prometheus:
  enabled: true
  servicemonitor:
    enabled: false   # T13 turns it on once the ServiceMonitor CRD exists
```

`deploy/platform/sealed-secrets/values-kind.yaml`:
```yaml
# Sealed Secrets controller v0.40.0 (chart sealed-secrets 2.20.0, project repo — D-8 exception to AD-14).
# Name + namespace match kubeseal defaults (kube-system/sealed-secrets-controller).
fullnameOverride: sealed-secrets-controller
resources:
  requests: {cpu: 10m, memory: 32Mi}
  limits: {memory: 128Mi}
```

`deploy/platform/traefik/values-kind.yaml`:
```yaml
# Traefik v3.7.13 (chart 41.6.1) as Gateway API v1.6 provider on kind: hostPort 80/443 on the ingress-ready control-plane.
deployment:
  replicas: 1
nodeSelector:
  ingress-ready: "true"
tolerations:
  - {key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule}
service:
  type: ClusterIP
ports:
  web:
    hostPort: 80
  websecure:
    hostPort: 443
providers:
  kubernetesIngress:
    enabled: false
  kubernetesGateway:
    enabled: true
gateway:
  name: traefik-gateway
  listeners:
    web:
      port: 8000
      protocol: HTTP
      namespacePolicy:
        from: All
    websecure:
      port: 8443
      protocol: HTTPS
      hostname: "*.kind.localhost"
      namespacePolicy:
        from: All
      certificateRefs:
        - name: wildcard-kind-localhost-tls
      mode: Terminate
resources:
  requests: {cpu: 20m, memory: 64Mi}
  limits: {memory: 256Mi}
```

`deploy/platform/cloudnative-pg/values-kind.yaml`:
```yaml
# CloudNativePG operator 1.30.1 (chart cloudnative-pg 0.29.1) on kind.
replicaCount: 1
resources:
  requests: {cpu: 20m, memory: 64Mi}
  limits: {memory: 256Mi}
```

`deploy/platform/cert-manager-issuers/kind/issuers.yaml`:
```yaml
# kind CAs (spec §8): self-signed CA for *.kind.localhost (Traefik TLS) + internal CA for service mTLS (AD-10).
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: selfsigned
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: kind-root-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: banking-go kind root CA
  secretName: kind-root-ca
  duration: 87600h
  privateKey: {algorithm: ECDSA, size: 256}
  issuerRef: {group: cert-manager.io, kind: ClusterIssuer, name: selfsigned}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: kind-ca
spec:
  ca:
    secretName: kind-root-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: bg-internal-root-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: banking-go internal mTLS CA (kind)
  secretName: bg-internal-root-ca
  duration: 87600h
  privateKey: {algorithm: ECDSA, size: 256}
  issuerRef: {group: cert-manager.io, kind: ClusterIssuer, name: selfsigned}
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: bg-internal-ca
spec:
  ca:
    secretName: bg-internal-root-ca
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: wildcard-kind-localhost
  namespace: traefik
spec:
  secretName: wildcard-kind-localhost-tls
  dnsNames: ["*.kind.localhost", "kind.localhost"]
  duration: 2160h
  renewBefore: 360h
  privateKey: {algorithm: ECDSA, size: 256}
  issuerRef: {group: cert-manager.io, kind: ClusterIssuer, name: kind-ca}
```

- [ ] **Step 4: Catalog** — `deploy/argocd/kind/values.yaml`

```yaml
# Single source of truth for the kind env (ADR 0011): add-ons with chart/version/values/sync-wave.
# Read by scripts/kind-platform.sh (helm/kubectl, S1–S2, before GitOps) and by the app-of-apps templates (T21).
# Fields: chart {repo,name,version} + values[] (+ releaseName) OR path (directory of manifests);
#         wait = `kubectl wait` arguments; post = command run by the script after install (Argo CD ignores it).
repoURL: ""          # git@github.com:<GH_OWNER>/banking-go.git, set by deploy/kind/bootstrap.sh (T21)
targetRevision: main
ghOwner: ""
addons:
  - name: gateway-api-crds
    wave: -30
    path: deploy/platform/gateway-api
    wait: "--for=condition=Established crd/gateways.gateway.networking.k8s.io crd/httproutes.gateway.networking.k8s.io --timeout=120s"
  - name: cert-manager
    wave: -20
    namespace: cert-manager
    chart: {repo: https://charts.jetstack.io, name: cert-manager, version: v1.21.2}
    values: [deploy/platform/cert-manager/values-kind.yaml]
  - name: sealed-secrets
    wave: -20
    namespace: kube-system
    chart: {repo: https://bitnami.github.io/sealed-secrets, name: sealed-secrets, version: 2.20.0}
    values: [deploy/platform/sealed-secrets/values-kind.yaml]
    post: deploy/kind/sealed-key.sh backup
  - name: traefik
    wave: -20
    namespace: traefik
    chart: {repo: https://traefik.github.io/charts, name: traefik, version: 41.6.1}
    values: [deploy/platform/traefik/values-kind.yaml]
  - name: cloudnative-pg
    wave: -20
    namespace: cnpg-system
    chart: {repo: https://cloudnative-pg.github.io/charts, name: cloudnative-pg, version: 0.29.1}
    values: [deploy/platform/cloudnative-pg/values-kind.yaml]
  - name: rabbitmq-cluster-operator
    wave: -19
    namespace: rabbitmq-system
    path: deploy/platform/rabbitmq-operators/cluster-operator
    wait: "-n rabbitmq-system --for=condition=Available deploy/rabbitmq-cluster-operator --timeout=300s"
  - name: rabbitmq-topology-operator
    wave: -19
    namespace: rabbitmq-system
    path: deploy/platform/rabbitmq-operators/topology-operator
    wait: "-n rabbitmq-system --for=condition=Available deploy/messaging-topology-operator --timeout=300s"
  - name: cluster-issuers
    wave: -18
    path: deploy/platform/cert-manager-issuers/kind
    wait: "--for=condition=Ready clusterissuer/kind-ca clusterissuer/bg-internal-ca --timeout=180s"
```

- [ ] **Step 5: `scripts/kind-platform.sh`**

```bash
#!/usr/bin/env bash
# Installs the kind add-ons of deploy/argocd/kind/values.yaml in sync-wave order with helm/kubectl directly.
# Temporary path for S1/S2 (no GitHub yet), kind only; T21 hands the same catalog to Argo CD.
#   scripts/kind-platform.sh [--max-wave N] [name ...]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
CATALOG="$ROOT/deploy/argocd/kind/values.yaml"
MAX_WAVE=1000
ONLY=()
while [[ $# -gt 0 ]]; do
  case $1 in
    --max-wave) MAX_WAVE=$2; shift 2 ;;
    *) ONLY+=("$1"); shift ;;
  esac
done
require_kind_context

# fd 3 keeps helm/kubectl/post commands from reading the catalog stream; the loop runs in this shell (set -e applies).
while IFS= read -r a <&3; do
  get() { jq -r "$1 // empty" <<<"$a"; }
  name=$(get .name); wave=$(get .wave); ns=$(get .namespace)
  (( wave <= MAX_WAVE )) || continue
  [[ ${#ONLY[@]} -eq 0 || " ${ONLY[*]} " == *" $name "* ]] || continue
  echo "== wave $wave: $name"
  if [[ -n $(get .chart.name) ]]; then
    args=(upgrade --install "$(get '.releaseName // .name')" "$(get .chart.name)" --repo "$(get .chart.repo)"
          --version "$(get .chart.version)" --namespace "$ns" --create-namespace --wait --timeout 10m)
    while IFS= read -r v; do [[ -n $v ]] && args+=(-f "$ROOT/$v"); done < <(jq -r '.values[]? // empty' <<<"$a")
    helm "${args[@]}"
  else
    dir="$ROOT/$(get .path)"
    if ! find "$dir" -name '*.yaml' -o -name '*.yml' | grep -q .; then echo "   (no manifests in $(get .path), skipped)"; continue; fi
    [[ -z $ns ]] || kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
    kubectl apply --server-side --force-conflicts -R -f "$dir"
  fi
  w=$(get .wait); [[ -z $w ]] || eval "kubectl wait $w"
  p=$(get .post); [[ -z $p ]] || (cd "$ROOT" && eval "$p")
done 3< <(yq -o=json -I=0 '.addons | sort_by(.wave) | .[]' "$CATALOG")
echo "kind-platform: done"
```

- [ ] **Step 6: `Makefile`** — thêm vào khối kind:

```make
.PHONY: kind-platform kind-ca
kind-platform: tools-k8s ## Install kind add-ons from deploy/argocd/kind/values.yaml with helm/kubectl (before GitOps; MAX_WAVE=N to stop early)
	scripts/kind-platform.sh $(if $(MAX_WAVE),--max-wave $(MAX_WAVE))
	deploy/kind/check-platform.sh
kind-ca: tools-k8s ## Export the kind root CA to ~/.config/banking-go/kind-ca.crt (curl --cacert / trust store)
	@mkdir -p $(HOME)/.config/banking-go
	$(KUBECTL) -n cert-manager get secret kind-root-ca -o jsonpath='{.data.ca\.crt}' | base64 -d > $(HOME)/.config/banking-go/kind-ca.crt
	@echo "CA: $(HOME)/.config/banking-go/kind-ca.crt — e.g. curl --cacert $(HOME)/.config/banking-go/kind-ca.crt https://api.kind.localhost/v1/ping"
```

- [ ] **Step 7: Cài + check**

Run: `chmod +x scripts/kind-platform.sh && make kind-platform && make kind-ca && openssl x509 -in ~/.config/banking-go/kind-ca.crt -noout -subject`
Expected: các dòng `== wave -30 … -18`, `kind-platform: done`, check in `ok …` cho mọi mục; `subject=CN = banking-go kind root CA`.

Run lần 2 (idempotent): `make kind-platform`
Expected: exit 0, không lỗi conflict.

- [ ] **Step 8: Commit**

```bash
git add deploy/argocd/kind/values.yaml deploy/platform scripts/kind-platform.sh scripts/vendor-manifests.sh deploy/kind/check-platform.sh Makefile
git commit -m "feat(platform): kind add-ons (gateway api, cert-manager, sealed secrets, traefik, cnpg, rabbitmq operators)"
```

**Lệnh kiểm chứng:** `make kind-platform && scripts/vendor-manifests.sh --check`

---

### T10: Data wave -15/-14 + Sealed Secrets + `make seal`

**Files:**
- Create: `deploy/platform/namespaces/kind/namespaces.yaml`, `deploy/platform/data/kind/postgres/cluster.yaml`, `deploy/platform/data/kind/postgres/databases.yaml`, `deploy/platform/data/kind/rabbitmq/cluster.yaml`, `deploy/platform/seaweedfs/values-kind.yaml`
- Create: `deploy/messaging/vhost.yaml`, `deploy/messaging/exchanges.yaml`, `deploy/messaging/retry.yaml`, `deploy/messaging/users.yaml`
- Create: `scripts/seal-kind.sh`, `scripts/check-no-plain-secrets.sh`, `deploy/secrets/kind.env.example`, `deploy/secrets/kind/*.sealed.yaml` (sinh bởi `make seal`)
- Modify: `deploy/argocd/kind/values.yaml` (addon `namespaces`, `kind-secrets`, `postgres`, `rabbitmq`, `seaweedfs`, `messaging`), `deploy/kind/check-platform.sh` (mục data), `.gitignore` (`deploy/secrets/*.env`), `.env.example`, `Makefile` (`seal`)

**Interfaces:**
- Consumes: catalog + `kind-platform.sh` (T9); controller cert `~/.config/banking-go/sealed-secrets-cert.pem` (T8/T9); tên Secret do chart dùng (T7).
- Produces: namespace `banking`, `banking-data`; CNPG `banking-data/pg` (service `pg-rw`), database `core`/`public`/`admin` (owner `<db>_migrator`), 6 role `{core,public,admin}_{migrator,app}`; `banking-data/rmq` (service `rmq`, vhost `banking`), exchange `banking.events` (topic), `banking.commands` (direct), `banking.dlx` (direct), `banking.retry.{1,2,3}` (fanout → queue TTL 10 s / 60 s / 600 s, dead-letter về default exchange), user `core`, `public-api`, `admin-api`; SeaweedFS S3 `seaweedfs-s3.banking-data.svc:8333` (tên service kiểm ở Step 9), bucket `banking-kind`; Secret (sealed): `banking/{core,public-api,admin-api}-migrator-dsn` (key `dsn`), `banking/{core,core-worker,public-api,admin-api}-env` (key `BG_<SVC>_DB_DSN`, `BG_<SVC>_AMQP_URL`, `BG_<SVC>_S3_ACCESS_KEY_ID`, `BG_<SVC>_S3_SECRET_ACCESS_KEY`), `banking-data/pg-<db>-<role>`, `banking-data/rmq-user-<svc>`, `banking-data/seaweedfs-s3-config`; target `make seal`; `scripts/check-no-plain-secrets.sh`.

- [ ] **Step 1: Viết check thất bại** — thêm cuối `deploy/kind/check-platform.sh`:

```bash
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
```

`scripts/check-no-plain-secrets.sh`:
```bash
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
```

Run: `chmod +x scripts/check-no-plain-secrets.sh && deploy/kind/check-platform.sh`
Expected: mục cũ `ok …`, sau đó `FAIL` (CRD/cluster `pg` chưa có: `clusters.postgresql.cnpg.io "pg" not found`).

- [ ] **Step 2: Namespace + data manifest**

`deploy/platform/namespaces/kind/namespaces.yaml`:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: banking
  labels: {app.kubernetes.io/part-of: banking-go}
---
apiVersion: v1
kind: Namespace
metadata:
  name: banking-data
  labels: {app.kubernetes.io/part-of: banking-go}
```

`deploy/platform/data/kind/postgres/cluster.yaml`:
```yaml
# CNPG Cluster pg on kind (spec §8): 1 instance (no HA on kind), PostgreSQL 18.6, 6 managed roles (AD-26).
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: pg
  namespace: banking-data
spec:
  instances: 1
  imageName: ghcr.io/cloudnative-pg/postgresql:18.6-standard-trixie
  storage:
    size: 2Gi
  resources:
    requests: {cpu: 50m, memory: 256Mi}
    limits: {memory: 512Mi}
  managed:
    roles:
      - {name: core_migrator, ensure: present, login: true, passwordSecret: {name: pg-core-migrator}}
      - {name: core_app, ensure: present, login: true, passwordSecret: {name: pg-core-app}}
      - {name: public_migrator, ensure: present, login: true, passwordSecret: {name: pg-public-migrator}}
      - {name: public_app, ensure: present, login: true, passwordSecret: {name: pg-public-app}}
      - {name: admin_migrator, ensure: present, login: true, passwordSecret: {name: pg-admin-migrator}}
      - {name: admin_app, ensure: present, login: true, passwordSecret: {name: pg-admin-app}}
```

`deploy/platform/data/kind/postgres/databases.yaml`:
```yaml
# One database per service, owned by its migrator role (AD-3, AD-26). Grants to <svc>_app come with each service's first migration.
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: pg-core
  namespace: banking-data
spec:
  cluster: {name: pg}
  name: core
  owner: core_migrator
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: pg-public
  namespace: banking-data
spec:
  cluster: {name: pg}
  name: public
  owner: public_migrator
---
apiVersion: postgresql.cnpg.io/v1
kind: Database
metadata:
  name: pg-admin
  namespace: banking-data
spec:
  cluster: {name: pg}
  name: admin
  owner: admin_migrator
```

`deploy/platform/data/kind/rabbitmq/cluster.yaml`:
```yaml
# RabbitmqCluster rmq on kind (spec §8): 1 node, RabbitMQ 4.3.6 (Cluster Operator v2.23.0).
apiVersion: rabbitmq.com/v1beta1
kind: RabbitmqCluster
metadata:
  name: rmq
  namespace: banking-data
spec:
  replicas: 1
  image: rabbitmq:4.3.6-management
  persistence:
    storage: 2Gi
  resources:
    requests: {cpu: 50m, memory: 512Mi}
    limits: {memory: 768Mi}
```

`deploy/platform/seaweedfs/values-kind.yaml`:
```yaml
# SeaweedFS 4.48 (official chart 4.48.0) all-in-one on kind: S3 with auth from Secret seaweedfs-s3-config,
# bucket banking-kind created by the chart's bucket hook Job (spec §8).
master: {enabled: false}
volume: {enabled: false}
filer: {enabled: false}
allInOne:
  enabled: true
  data:
    type: persistentVolumeClaim
    size: 5Gi
  s3:
    enabled: true
    enableAuth: true
    existingConfigSecret: seaweedfs-s3-config
    createBuckets:
      - name: banking-kind
        anonymousRead: false
  resources:
    requests: {cpu: 50m, memory: 128Mi}
    limits: {memory: 512Mi}
```

- [ ] **Step 3: Topology RabbitMQ** (`deploy/messaging/`, events.md § Topology)

`deploy/messaging/vhost.yaml`:
```yaml
apiVersion: rabbitmq.com/v1beta1
kind: Vhost
metadata:
  name: banking
  namespace: banking-data
spec:
  name: banking
  rabbitmqClusterReference: {name: rmq}
```

`deploy/messaging/exchanges.yaml`:
```yaml
# Exchanges declared once for every service (events.md § Topology). Services declare only their own queues.
apiVersion: rabbitmq.com/v1beta1
kind: Exchange
metadata: {name: banking-events, namespace: banking-data}
spec: {name: banking.events, vhost: banking, type: topic, durable: true, autoDelete: false, rabbitmqClusterReference: {name: rmq}}
---
apiVersion: rabbitmq.com/v1beta1
kind: Exchange
metadata: {name: banking-commands, namespace: banking-data}
spec: {name: banking.commands, vhost: banking, type: direct, durable: true, autoDelete: false, rabbitmqClusterReference: {name: rmq}}
---
# Dead-letter exchange: each service binds <queue>.dlq with routing key = <queue>.
apiVersion: rabbitmq.com/v1beta1
kind: Exchange
metadata: {name: banking-dlx, namespace: banking-data}
spec: {name: banking.dlx, vhost: banking, type: direct, durable: true, autoDelete: false, rabbitmqClusterReference: {name: rmq}}
```

`deploy/messaging/retry.yaml`:
```yaml
# Retry levels 1..3 (events.md A-52: 10 s, 1 min, 10 min). A consumer republishes a failed message to banking.retry.<n>
# with routing key = its own queue name; the delay queue's TTL expires it to the default exchange, back to that queue.
apiVersion: rabbitmq.com/v1beta1
kind: Exchange
metadata: {name: banking-retry-1, namespace: banking-data}
spec: {name: banking.retry.1, vhost: banking, type: fanout, durable: true, autoDelete: false, rabbitmqClusterReference: {name: rmq}}
---
apiVersion: rabbitmq.com/v1beta1
kind: Queue
metadata: {name: banking-retry-1, namespace: banking-data}
spec:
  name: banking.retry.1
  vhost: banking
  type: quorum
  durable: true
  autoDelete: false
  arguments: {x-message-ttl: 10000, x-dead-letter-exchange: ""}
  rabbitmqClusterReference: {name: rmq}
---
apiVersion: rabbitmq.com/v1beta1
kind: Binding
metadata: {name: banking-retry-1, namespace: banking-data}
spec: {vhost: banking, source: banking.retry.1, destination: banking.retry.1, destinationType: queue, rabbitmqClusterReference: {name: rmq}}
---
apiVersion: rabbitmq.com/v1beta1
kind: Exchange
metadata: {name: banking-retry-2, namespace: banking-data}
spec: {name: banking.retry.2, vhost: banking, type: fanout, durable: true, autoDelete: false, rabbitmqClusterReference: {name: rmq}}
---
apiVersion: rabbitmq.com/v1beta1
kind: Queue
metadata: {name: banking-retry-2, namespace: banking-data}
spec:
  name: banking.retry.2
  vhost: banking
  type: quorum
  durable: true
  autoDelete: false
  arguments: {x-message-ttl: 60000, x-dead-letter-exchange: ""}
  rabbitmqClusterReference: {name: rmq}
---
apiVersion: rabbitmq.com/v1beta1
kind: Binding
metadata: {name: banking-retry-2, namespace: banking-data}
spec: {vhost: banking, source: banking.retry.2, destination: banking.retry.2, destinationType: queue, rabbitmqClusterReference: {name: rmq}}
---
apiVersion: rabbitmq.com/v1beta1
kind: Exchange
metadata: {name: banking-retry-3, namespace: banking-data}
spec: {name: banking.retry.3, vhost: banking, type: fanout, durable: true, autoDelete: false, rabbitmqClusterReference: {name: rmq}}
---
apiVersion: rabbitmq.com/v1beta1
kind: Queue
metadata: {name: banking-retry-3, namespace: banking-data}
spec:
  name: banking.retry.3
  vhost: banking
  type: quorum
  durable: true
  autoDelete: false
  arguments: {x-message-ttl: 600000, x-dead-letter-exchange: ""}
  rabbitmqClusterReference: {name: rmq}
---
apiVersion: rabbitmq.com/v1beta1
kind: Binding
metadata: {name: banking-retry-3, namespace: banking-data}
spec: {vhost: banking, source: banking.retry.3, destination: banking.retry.3, destinationType: queue, rabbitmqClusterReference: {name: rmq}}
```

`deploy/messaging/users.yaml`:
```yaml
# One RabbitMQ user per service (deployment.md § Secrets); credentials from Sealed Secrets rmq-user-<svc>.
# core is shared by core and core-worker (same codebase, AD-1). Queues are named <service>.<purpose> or by command type.
apiVersion: rabbitmq.com/v1beta1
kind: User
metadata: {name: core, namespace: banking-data}
spec:
  importCredentialsSecret: {name: rmq-user-core}
  rabbitmqClusterReference: {name: rmq}
---
apiVersion: rabbitmq.com/v1beta1
kind: Permission
metadata: {name: core-banking, namespace: banking-data}
spec:
  vhost: banking
  userReference: {name: core}
  permissions:
    configure: '^(core-worker\..*|banking\.(customer|payment)\..*)$'
    write: '^(banking\.(events|commands|dlx|retry\.[1-3])|core-worker\..*|banking\.(customer|payment)\..*)$'
    read: '^(banking\.(events|commands|dlx)|core-worker\..*|banking\.(customer|payment)\..*)$'
  rabbitmqClusterReference: {name: rmq}
---
apiVersion: rabbitmq.com/v1beta1
kind: User
metadata: {name: public-api, namespace: banking-data}
spec:
  importCredentialsSecret: {name: rmq-user-public-api}
  rabbitmqClusterReference: {name: rmq}
---
apiVersion: rabbitmq.com/v1beta1
kind: Permission
metadata: {name: public-api-banking, namespace: banking-data}
spec:
  vhost: banking
  userReference: {name: public-api}
  permissions:
    configure: '^public-api\..*$'
    write: '^(banking\.(events|dlx|retry\.[1-3])|public-api\..*)$'
    read: '^(banking\.(events|dlx)|public-api\..*)$'
  rabbitmqClusterReference: {name: rmq}
---
apiVersion: rabbitmq.com/v1beta1
kind: User
metadata: {name: admin-api, namespace: banking-data}
spec:
  importCredentialsSecret: {name: rmq-user-admin-api}
  rabbitmqClusterReference: {name: rmq}
---
apiVersion: rabbitmq.com/v1beta1
kind: Permission
metadata: {name: admin-api-banking, namespace: banking-data}
spec:
  vhost: banking
  userReference: {name: admin-api}
  permissions:
    configure: '^admin-api\..*$'
    write: '^(banking\.events|admin-api\..*)$'
    read: '^admin-api\..*$'
  rabbitmqClusterReference: {name: rmq}
```

- [ ] **Step 4: Catalog** — thêm vào cuối `addons:` của `deploy/argocd/kind/values.yaml`, và chèn `namespaces` lên đầu danh sách:

```yaml
  - name: namespaces
    wave: -30
    path: deploy/platform/namespaces/kind
```
```yaml
  - name: kind-secrets
    wave: -18
    path: deploy/secrets/kind
  - name: postgres
    wave: -15
    path: deploy/platform/data/kind/postgres
    wait: "-n banking-data --for=condition=Ready cluster.postgresql.cnpg.io/pg --timeout=600s"
  - name: rabbitmq
    wave: -15
    path: deploy/platform/data/kind/rabbitmq
    wait: "-n banking-data --for=condition=AllReplicasReady rabbitmqcluster/rmq --timeout=600s"
  - name: seaweedfs
    wave: -15
    namespace: banking-data
    chart: {repo: https://seaweedfs.github.io/seaweedfs/helm, name: seaweedfs, version: 4.48.0}
    values: [deploy/platform/seaweedfs/values-kind.yaml]
  - name: messaging
    wave: -14
    path: deploy/messaging
    wait: "-n banking-data --for=condition=Ready exchanges.rabbitmq.com --all --timeout=300s"
```

- [ ] **Step 5: `make seal`**

`deploy/secrets/kind.env.example`:
```dotenv
# Plaintext inputs of `make seal` (copy is created automatically at deploy/secrets/kind.env, git-ignored, 0600).
# Empty values are generated randomly on the first `make seal`. TELEGRAM_* (T16) and GHCR_* (T21) are filled by the owner.
PG_CORE_MIGRATOR_PASSWORD=
PG_CORE_APP_PASSWORD=
PG_PUBLIC_MIGRATOR_PASSWORD=
PG_PUBLIC_APP_PASSWORD=
PG_ADMIN_MIGRATOR_PASSWORD=
PG_ADMIN_APP_PASSWORD=
RMQ_CORE_PASSWORD=
RMQ_PUBLIC_API_PASSWORD=
RMQ_ADMIN_API_PASSWORD=
S3_ADMIN_ACCESS_KEY=
S3_ADMIN_SECRET_KEY=
S3_CORE_ACCESS_KEY=
S3_CORE_SECRET_KEY=
S3_PUBLIC_API_ACCESS_KEY=
S3_PUBLIC_API_SECRET_KEY=
```

`scripts/seal-kind.sh`:
```bash
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
seal() { # seal <namespace> <name> <kubectl create secret generic args...>
  local ns=$1 name=$2; shift 2
  kubectl create secret generic "$name" --namespace "$ns" "$@" --dry-run=client -o yaml \
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
seal banking-data rmq-user-core --from-literal=username=core --from-literal=password="$RMQ_CORE_PASSWORD"
seal banking-data rmq-user-public-api --from-literal=username=public-api --from-literal=password="$RMQ_PUBLIC_API_PASSWORD"
seal banking-data rmq-user-admin-api --from-literal=username=admin-api --from-literal=password="$RMQ_ADMIN_API_PASSWORD"
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
"$ROOT/scripts/check-no-plain-secrets.sh"
```

`.gitignore` — thêm:
```text
# kind secret inputs (make seal); only deploy/secrets/kind/*.sealed.yaml is committed
deploy/secrets/*.env
```

`Makefile` — thêm vào khối kind:
```make
.PHONY: seal
seal: tools-k8s ## Seal kind secrets from deploy/secrets/kind.env (git-ignored) into deploy/secrets/kind/*.sealed.yaml
	scripts/seal-kind.sh
```

`.env.example` — thêm sau mỗi khối service tương ứng (giải thích key do Secret cấp trên kind, code chưa đọc):
```dotenv
# Injected on kind/staging from Secret core-env (platform v1); read once core gains DB/broker/S3 adapters.
# BG_CORE_DB_DSN=postgres://core_app:core_app@localhost:5432/core?sslmode=disable
# BG_CORE_AMQP_URL=amqp://banking:banking@localhost:5672/
# BG_CORE_S3_ACCESS_KEY_ID=
# BG_CORE_S3_SECRET_ACCESS_KEY=
```
```dotenv
# Injected on kind/staging from Secret core-worker-env (platform v1).
# BG_CORE_WORKER_DB_DSN=postgres://core_app:core_app@localhost:5432/core?sslmode=disable
# BG_CORE_WORKER_AMQP_URL=amqp://banking:banking@localhost:5672/
# BG_CORE_WORKER_S3_ACCESS_KEY_ID=
# BG_CORE_WORKER_S3_SECRET_ACCESS_KEY=
```
```dotenv
# Injected on kind/staging from Secret public-api-env (platform v1).
# BG_PUBLIC_API_DB_DSN=postgres://public_app:public_app@localhost:5432/public?sslmode=disable
# BG_PUBLIC_API_AMQP_URL=amqp://banking:banking@localhost:5672/
# BG_PUBLIC_API_S3_ACCESS_KEY_ID=
# BG_PUBLIC_API_S3_SECRET_ACCESS_KEY=
```
```dotenv
# Injected on kind/staging from Secret admin-api-env (platform v1).
# BG_ADMIN_API_DB_DSN=postgres://admin_app:admin_app@localhost:5432/admin?sslmode=disable
# BG_ADMIN_API_AMQP_URL=amqp://banking:banking@localhost:5672/
```

- [ ] **Step 6: Seal (cần controller + cert từ T9)**

Run: `chmod +x scripts/seal-kind.sh && make seal && ls deploy/secrets/kind | wc -l && stat -c %a deploy/secrets/kind.env`
Expected: 17 dòng `sealed …`, `ok   no plaintext Secret under deploy/`; `17`; `600`.

- [ ] **Step 7: Cài data + check**

Run: `make kind-platform`
Expected: thêm `== wave -30: namespaces`, `== wave -18: kind-secrets`, `== wave -15: postgres|rabbitmq|seaweedfs`, `== wave -14: messaging`; check in `ok   postgres pg: databases + 6 managed roles`, `ok   rabbitmq rmq: …`, `ok   seaweedfs bucket banking-kind`.

- [ ] **Step 8: Không lộ secret**

Run: `git status --porcelain deploy/secrets && git check-ignore deploy/secrets/kind.env && docker run --rm -v "$PWD:/repo" -w /repo zricethezav/gitleaks:v8.30.0 dir /repo/deploy --redact --exit-code 1`
Expected: chỉ `*.sealed.yaml` + `kind.env.example` là file mới; `deploy/secrets/kind.env` bị ignore; gitleaks `no leaks found`.

- [ ] **Step 9: Ghi tên service S3 thật** — Run: `kubectl -n banking-data get svc -l app.kubernetes.io/name=seaweedfs -o name`; nếu tên khác `seaweedfs-s3`, cập nhật dòng Interfaces "Produces" của task này trong plan (không đổi code — service chưa đọc S3 endpoint).

- [ ] **Step 10: Commit**

```bash
git add deploy/platform/namespaces deploy/platform/data deploy/platform/seaweedfs deploy/messaging deploy/secrets/kind deploy/secrets/kind.env.example \
  deploy/argocd/kind/values.yaml deploy/kind/check-platform.sh scripts/seal-kind.sh scripts/check-no-plain-secrets.sh .gitignore .env.example Makefile
git commit -m "feat(platform): kind data wave (cnpg, rabbitmq topology, seaweedfs) with sealed secrets"
```

**Lệnh kiểm chứng:** `make kind-platform && scripts/check-no-plain-secrets.sh`

---

### T11: `make kind-load kind-apps` — 10 chart chạy trên kind

**Files:**
- Create: `scripts/kind-apps.sh`, `deploy/kind/check-apps.sh`
- Modify: `Makefile` (`kind-load`, `kind-apps`)

**Interfaces:**
- Consumes: image `banking-go/<image>:local` + `IMAGES` (T3, T4), 10 chart (T7), `deploy/deployables.tsv` (T3), Secret + data (T10), `require_kind_context` (T8).
- Produces: release Helm `<deployable>` trong ns `banking` (image `banking-go/<image>:local`, `pullPolicy: Never`); Job `core-migrate`, `public-api-migrate`, `admin-api-migrate` Completed; target `make kind-load`, `make kind-apps`; `deploy/kind/check-apps.sh`.

- [ ] **Step 1: Viết check thất bại** — `deploy/kind/check-apps.sh`

```bash
#!/usr/bin/env bash
# Asserts the 10 deployables run on kind: Deployments available, migration Jobs Completed (spec §6, AD-26).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }
require_kind_context
while read -r name _rest; do
  [[ -z $name || $name == \#* ]] && continue
  kubectl -n banking rollout status "deploy/$name" --timeout=300s >/dev/null || fail "deployment banking/$name not available"
  echo "ok   deployment $name"
done < "$ROOT/deploy/deployables.tsv"
for j in core-migrate public-api-migrate admin-api-migrate; do
  [[ $(kubectl -n banking get job "$j" -o jsonpath='{.status.succeeded}') == 1 ]] || fail "job banking/$j not Completed"
  kubectl -n banking logs "job/$j" | grep -q 'migrate: no migrations, nothing to do\|migrate: done' || fail "job $j log lacks migrate result"
  echo "ok   job $j Completed"
done
```

Run: `chmod +x deploy/kind/check-apps.sh && deploy/kind/check-apps.sh`
Expected: `FAIL: deployment banking/core not available`.

- [ ] **Step 2: `scripts/kind-apps.sh`**

```bash
#!/usr/bin/env bash
# Deploys the 10 thin charts with helm directly using locally built images (S1/S2, before GitOps; kind only).
# Migration Jobs run first as Helm pre-install/pre-upgrade hooks (same Job is an Argo CD PreSync hook in S3).
#   IMAGE_PREFIX=banking-go IMAGE_TAG=local scripts/kind-apps.sh [deployable ...]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
PREFIX=${IMAGE_PREFIX:-banking-go}
TAG=${IMAGE_TAG:-local}
require_kind_context
while read -r name image _rest <&3; do
  [[ -z $name || $name == \#* ]] && continue
  [[ $# -eq 0 || " $* " == *" $name "* ]] || continue
  chart="$ROOT/deploy/helm/$name"
  echo "== $name ($PREFIX/$image:$TAG)"
  helm dependency build "$chart" >/dev/null
  helm upgrade --install "$name" "$chart" --namespace banking --create-namespace \
    -f "$chart/values-kind.yaml" \
    --set image.repository="$PREFIX/$image" --set image.tag="$TAG" --set image.pullPolicy=Never \
    --wait --timeout 5m
done 3< "$ROOT/deploy/deployables.tsv"
echo "kind-apps: done"
```

- [ ] **Step 3: `Makefile`** — thêm vào khối kind:

```make
.PHONY: kind-load kind-apps
kind-load: tools-k8s ## Load the locally built images ($(IMAGE_PREFIX)/<image>:$(IMAGE_TAG)) into the kind nodes
	@for i in $(IMAGES); do $(KIND) load docker-image $(IMAGE_PREFIX)/$$i:$(IMAGE_TAG) --name $(KIND_CLUSTER); done
kind-apps: tools-k8s ## helm upgrade --install the 10 charts with values-kind.yaml + local images (before GitOps)
	IMAGE_PREFIX=$(IMAGE_PREFIX) IMAGE_TAG=$(IMAGE_TAG) scripts/kind-apps.sh
	deploy/kind/check-apps.sh
```

- [ ] **Step 4: Chạy**

Run: `chmod +x scripts/kind-apps.sh && make images kind-load kind-apps`
Expected: 10 dòng `== <deployable> …`, `kind-apps: done`, check: 10 `ok   deployment …`, 3 `ok   job …-migrate Completed`.

- [ ] **Step 5: Chạy lại an toàn (migration re-run)**

Run: `make kind-apps && kubectl -n banking get jobs`
Expected: exit 0; 3 Job `COMPLETIONS 1/1` (Job được tạo lại mỗi lần upgrade, vẫn no-op).

- [ ] **Step 6: Commit**

```bash
git add scripts/kind-apps.sh deploy/kind/check-apps.sh Makefile
git commit -m "feat(platform): deploy the 10 charts on kind with local images and migration hooks"
```

**Lệnh kiểm chứng:** `make kind-load kind-apps`

---

### T12: `make kind-smoke`

**Files:**
- Create: `scripts/kind-smoke.sh`
- Modify: `Makefile` (`kind-smoke`), `CLAUDE.md` (mục Commands + Gotchas cho kind)

**Interfaces:**
- Consumes: host + route (T7, T9), app chạy (T11), `deploy/deployables.tsv`, `yq`.
- Produces: `scripts/kind-smoke.sh` (biến `RELEASES_FILE`, mặc định `deploy/releases/kind.yaml`; có hàm `check_json`, `check_html`, phần digest); target `make kind-smoke`. T13/T15/T16 thêm phần telemetry vào cùng script; T20/T21 dùng nó để kiểm rollback.

- [ ] **Step 1: Viết smoke** — `scripts/kind-smoke.sh`

```bash
#!/usr/bin/env bash
# make kind-smoke: end-to-end checks of the kind env through Traefik (spec criteria 3–5).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
RELEASES=${RELEASES_FILE:-$ROOT/deploy/releases/kind.yaml}
NS=banking
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok   $*"; }
require_kind_context

# 1. APIs through Traefik (-k: kind CA, see make kind-ca)
check_json() { # check_json <host> <path>
  local url="https://$1$2" code
  code=$(curl -sk --max-time 10 -o "$TMP/body" -w '%{http_code}' "$url") || fail "$url unreachable"
  [[ $code == 200 && $(tr -d '\n' < "$TMP/body") == '{"status":"ok"}' ]] || fail "$url → $code $(head -c 200 "$TMP/body")"
  ok "$url → 200 {\"status\":\"ok\"}"
}
# 2. SPAs: 200 HTML
check_html() { # check_html <host>
  local url="https://$1/" out
  out=$(curl -sk --max-time 10 -o "$TMP/body" -w '%{http_code} %{content_type}' "$url") || fail "$url unreachable"
  [[ $out == "200 text/html"* ]] && grep -q '<div id="root">' "$TMP/body" || fail "$url → $out"
  ok "$url → 200 HTML"
}
check_json api.kind.localhost /v1/ping
check_json admin-api.kind.localhost /v1/ping
check_html app.kind.localhost
check_html admin.kind.localhost

# 3. Migration Jobs Completed (PreSync / Helm hook)
for j in core-migrate public-api-migrate admin-api-migrate; do
  [[ $(kubectl -n $NS get job "$j" -o jsonpath='{.status.succeeded}') == 1 ]] || fail "job $j not Completed"
  ok "job $j Completed"
done

# 4. Running digests == deploy/releases/kind.yaml (written only by bg-release-bot)
if [[ -f $RELEASES ]]; then
  while read -r name _rest; do
    [[ -z $name || $name == \#* ]] && continue
    want=$(yq ".\"$name\".digest" "$RELEASES")
    [[ $want == sha256:* ]] || fail "$RELEASES has no digest for $name"
    got=$(kubectl -n $NS get pods -l "app.kubernetes.io/name=$name" --field-selector=status.phase=Running \
      -o jsonpath='{range .items[*]}{.status.containerStatuses[0].imageID}{"\n"}{end}' | sort -u)
    [[ -n $got ]] || fail "no running pod for $name"
    while read -r id; do [[ $id == *"@$want" ]] || fail "$name runs $id, want @$want"; done <<<"$got"
    ok "$name runs $want"
  done < "$ROOT/deploy/deployables.tsv"
else
  echo "skip digest check: $RELEASES not found (bg-release-bot writes it from main.yml, S3/T19)"
fi
echo "kind-smoke: all checks passed"
```

- [ ] **Step 2: Chạy khi chưa có target để thấy fail**

Run: `make kind-smoke`
Expected: `make: *** No rule to make target 'kind-smoke'`.

- [ ] **Step 3: `Makefile`**

```make
.PHONY: kind-smoke
kind-smoke: tools-k8s ## Smoke the kind env: 4 hosts via Traefik, migration Jobs, running digests vs deploy/releases/kind.yaml
	scripts/kind-smoke.sh
```

- [ ] **Step 4: Chạy pass + thử fail thật**

Run: `chmod +x scripts/kind-smoke.sh && make kind-smoke`
Expected: 4 dòng host `ok`, 3 dòng job `ok`, `skip digest check: … not found`, `kind-smoke: all checks passed`.

Run: `kubectl -n banking scale deploy/public-api --replicas=0 && sleep 5; make kind-smoke; kubectl -n banking scale deploy/public-api --replicas=1`
Expected: `FAIL: https://api.kind.localhost/v1/ping → 503 …` (exit ≠ 0), rồi khôi phục.

- [ ] **Step 5: `CLAUDE.md`** — thêm vào mục `## Commands`:

```markdown
- kind (platform v1): `make tools-k8s` → `make kind-up` → `make kind-platform` → `make seal` (lần đầu) → `make images kind-load kind-apps` → `make kind-smoke`; xóa: `make kind-down` (backup key Sealed Secrets ở ~/.config/banking-go/)
```
và vào `## Gotchas`:
```markdown
- kind cần cổng 80/443 trống trên host và ~6–7 GB RAM; `*.kind.localhost` tự trỏ 127.0.0.1 (curl/trình duyệt), CA: `make kind-ca`.
- S1/S2 cài kind bằng helm/kubectl trực tiếp (`kind-platform`, `kind-apps`) — đường tạm chỉ cho kind, S3 chuyển sang Argo CD.
```

- [ ] **Step 6: Commit**

```bash
git add scripts/kind-smoke.sh Makefile CLAUDE.md
git commit -m "feat(platform): kind smoke test through traefik with digest check"
```

**Lệnh kiểm chứng:** `make kind-smoke`

**Demo S1:** máy sạch → `make tools-k8s images image-smoke helm-lint helm-test kind-up kind-platform seal kind-platform kind-load kind-apps kind-smoke` (lần `kind-platform` đầu dừng ở `seal` vì chưa có cert → `make kind-platform MAX_WAVE=-19 && make seal && make kind-platform`).

---

# Sprint S2 — Observability as code trên kind

**Sprint goal:** gọi `https://api.kind.localhost/v1/ping` sinh trace trong Jaeger và metric RED trong Prometheus; alert v1 (đã unit-test bằng promtool) nạp vào Prometheus, `Watchdog` tới Telegram; dashboard `service-overview` + `platform` có trong Grafana 12.4; 7 runbook; `make kind-watch` chạy được. **Demo:** `make kind-smoke` in thêm 4 dòng telemetry; mở `https://grafana.kind.localhost` dashboard `banking-go / Service overview (RED)`.

### T13: kube-prometheus-stack + Jaeger v2 + OTel Collector + route vận hành

**Files:**
- Create: `deploy/platform/kube-prometheus-stack/values-kind.yaml`, `deploy/platform/jaeger/values-kind.yaml`, `deploy/collector/kind.yaml`, `deploy/platform/routes/kind/ops-routes.yaml`, `scripts/collector-validate.sh`
- Modify: `deploy/platform/namespaces/kind/namespaces.yaml` (+ `observability`, `monitoring`), `deploy/argocd/kind/values.yaml` (addon wave -10), `deploy/platform/cert-manager/values-kind.yaml` (bật ServiceMonitor), `deploy/helm/{core,core-worker,public-api,admin-api,mock-napas,mock-ekyc,mock-otp,mock-gateway}/values-kind.yaml` (`global.otelEndpoint`), `scripts/lib/kind.sh` (`svc_get`, `prom`, `prom_value`), `scripts/kind-smoke.sh` (telemetry), `deploy/kind/check-platform.sh` (mục observability), `Makefile` (`collector-validate`)

**Interfaces:**
- Consumes: catalog + `kind-platform.sh` (T9), Gateway + `kind-ca` (T9), `global.otelEndpoint` của lib (T5), app đang chạy (T11), smoke (T12).
- Produces: addon `prometheus-operator-crds` (chart 32.0.1, wave -30); Prometheus `monitoring/kube-prometheus-stack-prometheus:9090` (remote-write receiver, external label `env=kind`, chọn mọi `PrometheusRule`/`ServiceMonitor`/`PodMonitor`), Alertmanager `…-alertmanager:9093`, Grafana 12.4.12 `…-grafana:80` (datasource uid `prom`, Jaeger uid `traces`, sidecar dashboard label `grafana_dashboard: "1"`), Jaeger `observability/jaeger:{4317,16686}`, Collector `observability/otel-collector:4317` (job metric `otel-collector`); host `grafana.`, `jaeger.`, `argocd.`, `rabbitmq.kind.localhost`; hàm `svc_get <ns> <svc:port> <path>`, `prom <promql>`, `prom_value <promql>`; target `make collector-validate`.

- [ ] **Step 1: Viết test thất bại**

`scripts/collector-validate.sh`:
```bash
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
```

Thêm vào cuối `scripts/kind-smoke.sh`, ngay trước dòng `echo "kind-smoke: all checks passed"`:
```bash
# 5. Telemetry (spec criterion 5): traffic → trace in Jaeger + RED metric in Prometheus
for _ in $(seq 20); do curl -sk -o /dev/null --max-time 5 https://api.kind.localhost/v1/ping; done
start=$(date -u -d '-15 min' +%Y-%m-%dT%H:%M:%SZ); end=$(date -u -d '+1 min' +%Y-%m-%dT%H:%M:%SZ)
spans=0
for _ in $(seq 36); do
  spans=$(svc_get observability jaeger:16686 "/api/v3/traces?query.service_name=public-api&query.start_time_min=$start&query.start_time_max=$end" 2>/dev/null \
    | jq '[.. | objects | .spans? // empty | .[]] | length' 2>/dev/null || echo 0)
  [[ $spans -gt 0 ]] && break; sleep 5
done
[[ $spans -gt 0 ]] || fail "no public-api trace in Jaeger (/api/v3/traces)"
ok "Jaeger has $spans public-api span(s)"
rps=0
for _ in $(seq 36); do
  rps=$(prom_value 'sum(rate(http_server_request_duration_seconds_count{service_name="public-api"}[5m]))')
  awk -v v="$rps" 'BEGIN{exit !(v > 0)}' && break; sleep 5
done
awk -v v="$rps" 'BEGIN{exit !(v > 0)}' || fail "Prometheus RED rate for public-api is 0"
ok "Prometheus RED rate public-api = $rps req/s"
```

Thêm vào cuối `deploy/kind/check-platform.sh`:
```bash
# --- wave -10: observability
for d in monitoring/kube-prometheus-stack-grafana monitoring/kube-prometheus-stack-operator observability/jaeger observability/otel-collector; do
  kubectl -n "${d%%/*}" rollout status "deploy/${d#*/}" --timeout=300s >/dev/null || fail "deployment $d not available"
  ok "deployment $d"
done
[[ $(kubectl -n monitoring get prometheus kube-prometheus-stack-prometheus -o jsonpath='{.spec.enableRemoteWriteReceiver}') == true ]] \
  || fail "Prometheus remote-write receiver disabled"
gv=$(svc_get monitoring kube-prometheus-stack-grafana:80 /api/health | jq -r .version)
[[ $gv == 12.4.* ]] || fail "Grafana version $gv (want 12.4.x)"; ok "Grafana $gv"
for h in grafana jaeger argocd rabbitmq; do
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 10 "https://$h.kind.localhost/")
  [[ $code =~ ^(200|301|302)$ ]] || fail "https://$h.kind.localhost → $code"; ok "https://$h.kind.localhost → $code"
done
```

Run: `chmod +x scripts/collector-validate.sh && scripts/collector-validate.sh; make kind-smoke`
Expected: collector-validate lỗi `yq: … no such file deploy/collector/kind.yaml`; kind-smoke `svc_get: command not found` → FAIL.

- [ ] **Step 2: Helper** — thêm vào `scripts/lib/kind.sh`:

```bash
# svc_get <namespace> <service:port> <path?query>: GET through the API server service proxy (no port-forward).
svc_get() { kubectl get --raw "/api/v1/namespaces/$1/services/$2/proxy$3"; }

# prom <promql>: instant query against the kind Prometheus; prints the JSON response.
prom() { svc_get monitoring kube-prometheus-stack-prometheus:9090 "/api/v1/query?query=$(jq -rn --arg q "$1" '$q|@uri')"; }

# prom_value <promql>: first sample value, or 0 when the result is empty.
prom_value() { prom "$1" | jq -r '.data.result[0].value[1] // "0"'; }
```

- [ ] **Step 3: Values observability**

`deploy/platform/kube-prometheus-stack/values-kind.yaml`:
```yaml
# kube-prometheus-stack 91.9.0 on kind (observability.md § Pipeline): Prometheus remote-write receiver for the Collector,
# Grafana pinned 12.4.12 (AD-13), 1 replica; v1 alert rules come from observability/alerts (T14), not the chart defaults.
# CRDs come from the prometheus-operator-crds addon (wave -30) so wave -20 charts can create ServiceMonitors.
crds:
  enabled: false
defaultRules:
  create: false
kubeControllerManager: {enabled: false}
kubeScheduler: {enabled: false}
kubeEtcd: {enabled: false}
kubeProxy: {enabled: false}
prometheus:
  prometheusSpec:
    replicas: 1
    retention: 3d
    enableRemoteWriteReceiver: true
    externalLabels:
      env: kind
    ruleSelectorNilUsesHelmValues: false
    serviceMonitorSelectorNilUsesHelmValues: false
    podMonitorSelectorNilUsesHelmValues: false
    resources:
      requests: {cpu: 100m, memory: 512Mi}
      limits: {memory: 1Gi}
alertmanager:
  alertmanagerSpec:
    replicas: 1
    resources:
      requests: {cpu: 10m, memory: 32Mi}
      limits: {memory: 128Mi}
grafana:
  image:
    tag: 12.4.12
  replicas: 1
  defaultDashboardsEnabled: false
  grafana.ini:
    server:
      root_url: https://grafana.kind.localhost
  sidecar:
    dashboards:
      enabled: true
      label: grafana_dashboard
      labelValue: "1"
      searchNamespace: ALL
    datasources:
      enabled: true
      defaultDatasourceEnabled: true
      uid: prom
  additionalDataSources:
    - name: Jaeger
      type: jaeger
      uid: traces
      access: proxy
      url: http://jaeger.observability.svc:16686
  resources:
    requests: {cpu: 20m, memory: 128Mi}
    limits: {memory: 384Mi}
kube-state-metrics:
  resources:
    requests: {cpu: 10m, memory: 32Mi}
    limits: {memory: 128Mi}
prometheus-node-exporter:
  resources:
    requests: {cpu: 10m, memory: 16Mi}
    limits: {memory: 64Mi}
prometheusOperator:
  resources:
    requests: {cpu: 20m, memory: 64Mi}
    limits: {memory: 192Mi}
```

`deploy/platform/jaeger/values-kind.yaml`:
```yaml
# Jaeger v2.21.0 (chart 4.14.1) all-in-one with the default in-memory storage on kind (ADR 0011: no ES on kind).
fullnameOverride: jaeger
jaeger:
  replicas: 1
  image:
    tag: "2.21.0"
  resources:
    requests: {cpu: 20m, memory: 128Mi}
    limits: {memory: 512Mi}
```

`deploy/collector/kind.yaml`:
```yaml
# OpenTelemetry Collector (contrib v0.162.0) for env kind — values of chart open-telemetry/opentelemetry-collector 0.175.1.
# Full config in alternateConfig (not merged with chart defaults). observability.md § Pipeline: metrics → Prometheus
# (remote write), traces → Jaeger (OTLP), logs → debug (no ES on kind). Redaction is the 2nd PII layer (O-7).
mode: deployment
fullnameOverride: otel-collector
replicaCount: 1
image:
  repository: otel/opentelemetry-collector-contrib
  tag: "0.162.0"
command:
  name: otelcol-contrib
resources:
  requests: {cpu: 50m, memory: 128Mi}
  limits: {memory: 256Mi}
ports:
  jaeger-compact: {enabled: false}
  jaeger-thrift: {enabled: false}
  jaeger-grpc: {enabled: false}
  zipkin: {enabled: false}
  metrics: {enabled: true}
serviceMonitor:
  enabled: true
  metricsEndpoints:
    - port: metrics
alternateConfig:
  extensions:
    health_check:
      endpoint: ${env:MY_POD_IP}:13133
  receivers:
    otlp:
      protocols:
        grpc:
          endpoint: ${env:MY_POD_IP}:4317
        http:
          endpoint: ${env:MY_POD_IP}:4318
  processors:
    memory_limiter:
      check_interval: 1s
      limit_percentage: 80
      spike_limit_percentage: 25
    resource:
      attributes:
        - {key: deployment.environment.name, value: kind, action: upsert}
        - {key: env, value: kind, action: upsert}
    redaction:
      allow_all_keys: true
      blocked_key_patterns: ["(?i)password", "(?i)token", "(?i)authorization", "(?i)cookie", "(?i)otp", "(?i)secret", "(?i)phone", "(?i)national_id"]
      blocked_values: ["\\b[0-9]{9,12}\\b"]
      summary: silent
    batch: {}
  exporters:
    prometheusremotewrite:
      endpoint: http://kube-prometheus-stack-prometheus.monitoring.svc:9090/api/v1/write
      resource_to_telemetry_conversion:
        enabled: true
    otlp/jaeger:
      endpoint: jaeger.observability.svc:4317
      tls:
        insecure: true
    debug:
      verbosity: basic
  service:
    extensions: [health_check]
    telemetry:
      metrics:
        readers:
          - pull:
              exporter:
                prometheus:
                  host: ${env:MY_POD_IP}
                  port: 8888
    pipelines:
      traces:
        receivers: [otlp]
        processors: [memory_limiter, resource, redaction, batch]
        exporters: [otlp/jaeger]
      metrics:
        receivers: [otlp]
        processors: [memory_limiter, resource, redaction, batch]
        exporters: [prometheusremotewrite]
      logs:
        receivers: [otlp]
        processors: [memory_limiter, resource, redaction, batch]
        exporters: [debug]
```

`deploy/platform/routes/kind/ops-routes.yaml`:
```yaml
# Ops UIs on kind (spec "Thiết kế" hosts). Each route lives next to its backend (no ReferenceGrant needed).
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: grafana, namespace: monitoring}
spec:
  parentRefs: [{name: traefik-gateway, namespace: traefik, sectionName: websecure}]
  hostnames: [grafana.kind.localhost]
  rules: [{backendRefs: [{name: kube-prometheus-stack-grafana, port: 80}]}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: jaeger, namespace: observability}
spec:
  parentRefs: [{name: traefik-gateway, namespace: traefik, sectionName: websecure}]
  hostnames: [jaeger.kind.localhost]
  rules: [{backendRefs: [{name: jaeger, port: 16686}]}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: argocd, namespace: argocd}
spec:
  parentRefs: [{name: traefik-gateway, namespace: traefik, sectionName: websecure}]
  hostnames: [argocd.kind.localhost]
  rules: [{backendRefs: [{name: argocd-server, port: 80}]}]
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: {name: rabbitmq, namespace: banking-data}
spec:
  parentRefs: [{name: traefik-gateway, namespace: traefik, sectionName: websecure}]
  hostnames: [rabbitmq.kind.localhost]
  rules: [{backendRefs: [{name: rmq, port: 15672}]}]
```

`deploy/platform/namespaces/kind/namespaces.yaml` — thêm:
```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: observability
  labels: {app.kubernetes.io/part-of: banking-go}
---
apiVersion: v1
kind: Namespace
metadata:
  name: monitoring
  labels: {app.kubernetes.io/part-of: banking-go}
```

`deploy/platform/cert-manager/values-kind.yaml` — đổi `servicemonitor.enabled: false   # T13 …` thành:
```yaml
    enabled: true    # ServiceMonitor CRD comes from the prometheus-operator-crds addon (wave -30)
```

Catalog `deploy/argocd/kind/values.yaml` — thêm ngay sau addon `gateway-api-crds`:
```yaml
  - name: prometheus-operator-crds
    wave: -30
    namespace: monitoring
    chart: {repo: https://prometheus-community.github.io/helm-charts, name: prometheus-operator-crds, version: 32.0.1}
```
và thêm cuối `addons:`:
```yaml
  - name: kube-prometheus-stack
    wave: -10
    namespace: monitoring
    chart: {repo: https://prometheus-community.github.io/helm-charts, name: kube-prometheus-stack, version: 91.9.0}
    values: [deploy/platform/kube-prometheus-stack/values-kind.yaml]
  - name: jaeger
    wave: -10
    namespace: observability
    chart: {repo: https://jaegertracing.github.io/helm-charts, name: jaeger, version: 4.14.1}
    values: [deploy/platform/jaeger/values-kind.yaml]
  - name: otel-collector
    wave: -10
    namespace: observability
    chart: {repo: https://open-telemetry.github.io/opentelemetry-helm-charts, name: opentelemetry-collector, version: 0.175.1}
    values: [deploy/collector/kind.yaml]
  - name: ops-routes
    wave: -10
    path: deploy/platform/routes/kind
```

8 file `values-kind.yaml` Go (`core`, `core-worker`, `public-api`, `admin-api`, `mock-napas`, `mock-ekyc`, `mock-otp`, `mock-gateway`) — thêm ở đầu file:
```yaml
global:
  otelEndpoint: http://otel-collector.observability.svc:4317
```

`Makefile`:
```make
.PHONY: collector-validate
collector-validate: tools-k8s ## Validate deploy/collector/kind.yaml with the pinned otelcol-contrib image (needs Docker)
	scripts/collector-validate.sh
```

- [ ] **Step 4: Validate + cài + smoke**

Run: `make collector-validate`
Expected: `ok   collector config valid (otel/opentelemetry-collector-contrib:0.162.0)`. Nếu `validate` báo key/alias không hợp lệ (vd. `blocked_key_patterns`, exporter `otlp`), sửa theo thông báo của chính binary 0.162.0 rồi chạy lại.

Run: `make kind-platform && make kind-apps && make kind-smoke`
Expected: `== wave -30: prometheus-operator-crds` chạy trước cert-manager (ServiceMonitor được tạo ở wave -20); check-platform in `ok   Grafana 12.4.12`, 4 host vận hành `→ 200|302`; kind-smoke thêm `ok   Jaeger has N public-api span(s)` và `ok   Prometheus RED rate public-api = … req/s` (`make kind-apps` để pod nhận `OTEL_EXPORTER_OTLP_ENDPOINT`).

- [ ] **Step 5: Commit**

```bash
git add deploy/platform deploy/collector deploy/argocd/kind/values.yaml deploy/helm/*/values-kind.yaml scripts/lib/kind.sh scripts/kind-smoke.sh \
  scripts/collector-validate.sh deploy/kind/check-platform.sh Makefile
git commit -m "feat(platform): kind observability stack (prometheus, grafana 12.4, jaeger v2, otel collector)"
```

**Lệnh kiểm chứng:** `make collector-validate && make kind-smoke`

---

### T14: Alert rule v1 + recording rule SLI + promtool unit test + `PrometheusRule` sinh ra

**Files:**
- Create: `observability/alerts/slo.yaml`, `observability/alerts/platform.yaml`, `observability/alerts/tests/slo_test.yaml`, `observability/alerts/tests/platform_test.yaml`
- Create: `scripts/gen-observability.sh`, `deploy/platform/observability/kind/rules/bg-slo.yaml`, `deploy/platform/observability/kind/rules/bg-platform.yaml` (sinh ra)
- Modify: `deploy/argocd/kind/values.yaml` (addon `observability-as-code`, wave -9), `deploy/kind/check-platform.sh`, `Makefile` (`alerts-test`, `obs-gen`, `obs-gen-check`)

**Interfaces:**
- Consumes: metric `http_server_request_duration_seconds_{count,bucket}`, `rpc_server_duration_milliseconds_count` (label `service_name` qua remote write, T13), `otelcol_exporter_send_failed_*`, `up{job="otel-collector"}`, `certmanager_certificate_*`, `kube_pod_container_status_waiting_reason`, `argocd_app_info`; `bin/promtool`, `KUBECONFORM_FLAGS` (T7), `prom`/`svc_get` (T13).
- Produces: recording rule `sli:error_ratio:rate{5m,30m,1h,2h,6h,1d,3d}`, `sli:latency_p95:rate5m` (nhãn `service`, `service_name`[, `route_class`]); alert `Watchdog`, `ErrorBudgetBurnFast`, `ErrorBudgetBurnSlow`, `LatencyP95Breach`, `TelemetryPipelineDegraded`, `CertificateExpiringSoon`, `CertificateNotReady`, `PodCrashLooping`, `ArgoCDAppDegraded` với nhãn `severity`, `service`, `runbook_url` (đường dẫn trong repo `observability/runbooks/<kebab>.md`, T17 tạo file); `scripts/gen-observability.sh` (alerts → `deploy/platform/observability/kind/rules/bg-<file>.yaml`); target `make alerts-test`, `make obs-gen`, `make obs-gen-check`.

- [ ] **Step 1: Viết promtool test thất bại**

`observability/alerts/tests/slo_test.yaml`:
```yaml
rule_files:
  - ../slo.yaml
evaluation_interval: 1m
tests:
  - name: 10% 5xx on public-api burns the budget fast
    interval: 1m
    input_series:
      - series: 'http_server_request_duration_seconds_count{service_name="public-api",http_response_status_code="200"}'
        values: '0+90x120'
      - series: 'http_server_request_duration_seconds_count{service_name="public-api",http_response_status_code="500"}'
        values: '0+10x120'
    alert_rule_test:
      - eval_time: 60m
        alertname: ErrorBudgetBurnFast
        exp_alerts:
          - exp_labels: {severity: critical, runbook_url: observability/runbooks/error-budget-burn.md, service: public-api, service_name: public-api}
            exp_annotations: {summary: "public-api is burning its 30-day error budget fast (SLO 99.9%)."}
  - name: 4xx do not count against availability (2 errors / 100 non-4xx = 2% > 1.44%)
    interval: 1m
    input_series:
      - series: 'http_server_request_duration_seconds_count{service_name="admin-api",http_response_status_code="200"}'
        values: '0+98x120'
      - series: 'http_server_request_duration_seconds_count{service_name="admin-api",http_response_status_code="404"}'
        values: '0+100x120'
      - series: 'http_server_request_duration_seconds_count{service_name="admin-api",http_response_status_code="503"}'
        values: '0+2x120'
    alert_rule_test:
      - eval_time: 60m
        alertname: ErrorBudgetBurnFast
        exp_alerts:
          - exp_labels: {severity: critical, runbook_url: observability/runbooks/error-budget-burn.md, service: admin-api, service_name: admin-api}
            exp_annotations: {summary: "admin-api is burning its 30-day error budget fast (SLO 99.9%)."}
  - name: core gRPC Unavailable counts as a server error
    interval: 1m
    input_series:
      - series: 'rpc_server_duration_milliseconds_count{service_name="core",rpc_grpc_status_code="0"}'
        values: '0+90x120'
      - series: 'rpc_server_duration_milliseconds_count{service_name="core",rpc_grpc_status_code="14"}'
        values: '0+10x120'
    alert_rule_test:
      - eval_time: 60m
        alertname: ErrorBudgetBurnFast
        exp_alerts:
          - exp_labels: {severity: critical, runbook_url: observability/runbooks/error-budget-burn.md, service: core, service_name: core}
            exp_annotations: {summary: "core is burning its 30-day error budget fast (SLO 99.9%)."}
  - name: 0.5% errors fire only the slow burn alert
    interval: 1m
    input_series:
      - series: 'http_server_request_duration_seconds_count{service_name="public-api",http_response_status_code="200"}'
        values: '0+995x240'
      - series: 'http_server_request_duration_seconds_count{service_name="public-api",http_response_status_code="500"}'
        values: '0+5x240'
    alert_rule_test:
      - eval_time: 3h
        alertname: ErrorBudgetBurnSlow
        exp_alerts:
          - exp_labels: {severity: warning, runbook_url: observability/runbooks/error-budget-burn.md, service: public-api, service_name: public-api}
            exp_annotations: {summary: "public-api is burning its 30-day error budget steadily (SLO 99.9%)."}
      - eval_time: 3h
        alertname: ErrorBudgetBurnFast
        exp_alerts: []
  - name: p95 of read routes above 100 ms breaches, write routes under 300 ms do not
    interval: 1m
    input_series:
      - series: 'http_server_request_duration_seconds_bucket{service_name="public-api",route_class="read",le="0.1"}'
        values: '0+0x30'
      - series: 'http_server_request_duration_seconds_bucket{service_name="public-api",route_class="read",le="0.3"}'
        values: '0+10x30'
      - series: 'http_server_request_duration_seconds_bucket{service_name="public-api",route_class="read",le="+Inf"}'
        values: '0+10x30'
      - series: 'http_server_request_duration_seconds_bucket{service_name="public-api",route_class="write",le="0.1"}'
        values: '0+0x30'
      - series: 'http_server_request_duration_seconds_bucket{service_name="public-api",route_class="write",le="0.3"}'
        values: '0+10x30'
      - series: 'http_server_request_duration_seconds_bucket{service_name="public-api",route_class="write",le="+Inf"}'
        values: '0+10x30'
    alert_rule_test:
      - eval_time: 20m
        alertname: LatencyP95Breach
        exp_alerts:
          - exp_labels: {severity: warning, runbook_url: observability/runbooks/latency-p95-breach.md, service: public-api, service_name: public-api, route_class: read}
            exp_annotations: {summary: "public-api p95 latency of read routes is above its SLO."}
```

`observability/alerts/tests/platform_test.yaml`:
```yaml
rule_files:
  - ../platform.yaml
evaluation_interval: 1m
tests:
  - name: Watchdog always fires
    interval: 1m
    input_series: []
    alert_rule_test:
      - eval_time: 1m
        alertname: Watchdog
        exp_alerts:
          - exp_labels: {severity: none, service: platform, runbook_url: observability/runbooks/watchdog.md}
            exp_annotations: {summary: "Always firing. If Telegram stops receiving it, alerting is broken."}
  - name: Collector failing to export metric points
    interval: 1m
    input_series:
      - series: 'otelcol_exporter_send_failed_metric_points_total{exporter="prometheusremotewrite"}'
        values: '0+5x30'
      - series: 'up{job="otel-collector"}'
        values: '1+0x30'
    alert_rule_test:
      - eval_time: 15m
        alertname: TelemetryPipelineDegraded
        exp_alerts:
          - exp_labels: {severity: warning, service: otel-collector, runbook_url: observability/runbooks/telemetry-pipeline.md}
            exp_annotations: {summary: "The OpenTelemetry Collector is failing to export or is down."}
  - name: Collector down
    interval: 1m
    input_series:
      - series: 'up{job="otel-collector"}'
        values: '0+0x30'
    alert_rule_test:
      - eval_time: 15m
        alertname: TelemetryPipelineDegraded
        exp_alerts:
          - exp_labels: {severity: warning, service: otel-collector, runbook_url: observability/runbooks/telemetry-pipeline.md, job: otel-collector}
            exp_annotations: {summary: "The OpenTelemetry Collector is failing to export or is down."}
  - name: certificate expiring in 10 days warns, not critical
    interval: 1m
    input_series:
      - series: 'certmanager_certificate_expiration_timestamp_seconds{name="wildcard-kind-localhost",namespace="traefik"}'
        values: '864000+0x120'
    alert_rule_test:
      - eval_time: 70m
        alertname: CertificateExpiringSoon
        exp_alerts:
          - exp_labels: {severity: warning, service: cert-manager, runbook_url: observability/runbooks/certificate-expiry.md, name: wildcard-kind-localhost, namespace: traefik}
            exp_annotations: {summary: "Certificate traefik/wildcard-kind-localhost expires in less than 14 days."}
      - eval_time: 70m
        alertname: CertificateNotReady
        exp_alerts: []
  - name: certificate not ready
    interval: 1m
    input_series:
      - series: 'certmanager_certificate_ready_status{condition="False",name="core-mtls",namespace="banking"}'
        values: '1+0x30'
    alert_rule_test:
      - eval_time: 20m
        alertname: CertificateNotReady
        exp_alerts:
          - exp_labels: {severity: critical, service: cert-manager, runbook_url: observability/runbooks/certificate-expiry.md, condition: "False", name: core-mtls, namespace: banking}
            exp_annotations: {summary: "Certificate banking/core-mtls is not ready or expires in less than 3 days."}
  - name: pod in CrashLoopBackOff
    interval: 1m
    input_series:
      - series: 'kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff",namespace="banking",pod="core-7d9f",container="core"}'
        values: '1+0x30'
    alert_rule_test:
      - eval_time: 20m
        alertname: PodCrashLooping
        exp_alerts:
          - exp_labels: {severity: warning, service: kubernetes, runbook_url: observability/runbooks/pod-crashloop.md, namespace: banking, pod: core-7d9f, container: core}
            exp_annotations: {summary: "banking/core-7d9f container core is crash-looping."}
  - name: Argo CD application degraded
    interval: 1m
    input_series:
      - series: 'argocd_app_info{name="core",health_status="Degraded",sync_status="Synced"}'
        values: '1+0x30'
    alert_rule_test:
      - eval_time: 20m
        alertname: ArgoCDAppDegraded
        exp_alerts:
          - exp_labels: {severity: warning, service: argocd, runbook_url: observability/runbooks/argocd-app-degraded.md, name: core}
            exp_annotations: {summary: "Argo CD application core is Degraded or Missing."}
```

`Makefile` — thêm khối:
```make
# ---------------------------------------------------------------------------------------------
# Observability as code (platform v1): observability/ → deploy/platform/observability/kind (generated).
.PHONY: alerts-test obs-gen obs-gen-check
alerts-test: tools-k8s ## promtool check + unit tests of observability/alerts, kubeconform of the generated PrometheusRules
	$(PROMTOOL) check rules observability/alerts/*.yaml
	$(PROMTOOL) test rules observability/alerts/tests/*.yaml
	$(KUBECONFORM) $(KUBECONFORM_FLAGS) deploy/platform/observability/kind/rules
obs-gen: ## Regenerate PrometheusRule / dashboard ConfigMaps from observability/
	scripts/gen-observability.sh
obs-gen-check: obs-gen ## Fail if generated observability objects differ from the committed files (CI)
	git diff --exit-code -- deploy/platform/observability
	@test -z "$$(git status --porcelain -- deploy/platform/observability)" || { git status --porcelain -- deploy/platform/observability; exit 1; }
```

Run: `make alerts-test`
Expected: FAIL — `Checking observability/alerts/*.yaml … no such file or directory`.

- [ ] **Step 2: Rule** — `observability/alerts/slo.yaml`

```yaml
# SLI recording rules + SLO alerts v1 (spec §10; observability.md § SLI/SLO, § Alert catalog, recording rule naming).
# Availability SLO 99.9% (budget 0.001): HTTP edge = 5xx / non-4xx requests; core gRPC = server-error codes
# (Unknown 2, DeadlineExceeded 4, Internal 13, Unavailable 14, DataLoss 15) / all calls. Label `service` = service_name.
groups:
  - name: bg-sli
    rules:
      - record: sli:error_ratio:rate5m
        expr: |
          label_replace(sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code=~"5.."}[5m])) / sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code!~"4.."}[5m])), "service", "$1", "service_name", "(.*)")
          or
          label_replace(sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core",rpc_grpc_status_code=~"2|4|13|14|15"}[5m])) / sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core"}[5m])), "service", "$1", "service_name", "(.*)")
      - record: sli:error_ratio:rate30m
        expr: |
          label_replace(sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code=~"5.."}[30m])) / sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code!~"4.."}[30m])), "service", "$1", "service_name", "(.*)")
          or
          label_replace(sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core",rpc_grpc_status_code=~"2|4|13|14|15"}[30m])) / sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core"}[30m])), "service", "$1", "service_name", "(.*)")
      - record: sli:error_ratio:rate1h
        expr: |
          label_replace(sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code=~"5.."}[1h])) / sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code!~"4.."}[1h])), "service", "$1", "service_name", "(.*)")
          or
          label_replace(sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core",rpc_grpc_status_code=~"2|4|13|14|15"}[1h])) / sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core"}[1h])), "service", "$1", "service_name", "(.*)")
      - record: sli:error_ratio:rate2h
        expr: |
          label_replace(sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code=~"5.."}[2h])) / sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code!~"4.."}[2h])), "service", "$1", "service_name", "(.*)")
          or
          label_replace(sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core",rpc_grpc_status_code=~"2|4|13|14|15"}[2h])) / sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core"}[2h])), "service", "$1", "service_name", "(.*)")
      - record: sli:error_ratio:rate6h
        expr: |
          label_replace(sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code=~"5.."}[6h])) / sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code!~"4.."}[6h])), "service", "$1", "service_name", "(.*)")
          or
          label_replace(sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core",rpc_grpc_status_code=~"2|4|13|14|15"}[6h])) / sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core"}[6h])), "service", "$1", "service_name", "(.*)")
      - record: sli:error_ratio:rate1d
        expr: |
          label_replace(sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code=~"5.."}[1d])) / sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code!~"4.."}[1d])), "service", "$1", "service_name", "(.*)")
          or
          label_replace(sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core",rpc_grpc_status_code=~"2|4|13|14|15"}[1d])) / sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core"}[1d])), "service", "$1", "service_name", "(.*)")
      - record: sli:error_ratio:rate3d
        expr: |
          label_replace(sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code=~"5.."}[3d])) / sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~"public-api|admin-api",http_response_status_code!~"4.."}[3d])), "service", "$1", "service_name", "(.*)")
          or
          label_replace(sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core",rpc_grpc_status_code=~"2|4|13|14|15"}[3d])) / sum by (service_name) (rate(rpc_server_duration_milliseconds_count{service_name="core"}[3d])), "service", "$1", "service_name", "(.*)")
      - record: sli:latency_p95:rate5m
        expr: |
          label_replace(histogram_quantile(0.95, sum by (service_name, route_class, le) (rate(http_server_request_duration_seconds_bucket{service_name=~"public-api|admin-api"}[5m]))), "service", "$1", "service_name", "(.*)")
  - name: bg-slo
    rules:
      - alert: ErrorBudgetBurnFast
        expr: |
          (sli:error_ratio:rate1h > (14.4 * 0.001) and sli:error_ratio:rate5m > (14.4 * 0.001))
          or
          (sli:error_ratio:rate6h > (6 * 0.001) and sli:error_ratio:rate30m > (6 * 0.001))
        for: 2m
        labels:
          severity: critical
          runbook_url: observability/runbooks/error-budget-burn.md
        annotations:
          summary: "{{ $labels.service }} is burning its 30-day error budget fast (SLO 99.9%)."
      - alert: ErrorBudgetBurnSlow
        expr: |
          (sli:error_ratio:rate1d > (3 * 0.001) and sli:error_ratio:rate2h > (3 * 0.001))
          or
          (sli:error_ratio:rate3d > 0.001 and sli:error_ratio:rate6h > 0.001)
        for: 15m
        labels:
          severity: warning
          runbook_url: observability/runbooks/error-budget-burn.md
        annotations:
          summary: "{{ $labels.service }} is burning its 30-day error budget steadily (SLO 99.9%)."
      - alert: LatencyP95Breach
        # NFR-P1..P3 thresholds per route_class (O-1): read 100 ms, write 300 ms, login 500 ms, transfer 200 ms.
        expr: |
          sli:latency_p95:rate5m{route_class="read"} > 0.1
          or sli:latency_p95:rate5m{route_class="write"} > 0.3
          or sli:latency_p95:rate5m{route_class="login"} > 0.5
          or sli:latency_p95:rate5m{route_class="transfer"} > 0.2
        for: 10m
        labels:
          severity: warning
          runbook_url: observability/runbooks/latency-p95-breach.md
        annotations:
          summary: "{{ $labels.service }} p95 latency of {{ $labels.route_class }} routes is above its SLO."
```

`observability/alerts/platform.yaml`:
```yaml
# Platform alerts v1 (spec §10; observability.md § Alert catalog). Business alerts (invariant, unknown, DLQ, outbox)
# arrive with the features that emit their metrics.
groups:
  - name: bg-platform
    rules:
      - alert: Watchdog
        expr: vector(1)
        labels:
          severity: none
          service: platform
          runbook_url: observability/runbooks/watchdog.md
        annotations:
          summary: "Always firing. If Telegram stops receiving it, alerting is broken."
      - alert: TelemetryPipelineDegraded
        expr: |
          sum(rate({__name__=~"otelcol_exporter_send_failed_(metric_points|spans|log_records)(_total)?"}[5m])) > 0
          or absent(up{job="otel-collector"} == 1)
        for: 10m
        labels:
          severity: warning
          service: otel-collector
          runbook_url: observability/runbooks/telemetry-pipeline.md
        annotations:
          summary: "The OpenTelemetry Collector is failing to export or is down."
      - alert: CertificateExpiringSoon
        expr: certmanager_certificate_expiration_timestamp_seconds - time() < 14 * 86400
        for: 1h
        labels:
          severity: warning
          service: cert-manager
          runbook_url: observability/runbooks/certificate-expiry.md
        annotations:
          summary: "Certificate {{ $labels.namespace }}/{{ $labels.name }} expires in less than 14 days."
      - alert: CertificateNotReady
        expr: |
          (certmanager_certificate_expiration_timestamp_seconds - time() < 3 * 86400)
          or (certmanager_certificate_ready_status{condition="False"} == 1)
        for: 15m
        labels:
          severity: critical
          service: cert-manager
          runbook_url: observability/runbooks/certificate-expiry.md
        annotations:
          summary: "Certificate {{ $labels.namespace }}/{{ $labels.name }} is not ready or expires in less than 3 days."
      - alert: PodCrashLooping
        expr: max by (namespace, pod, container) (max_over_time(kube_pod_container_status_waiting_reason{reason="CrashLoopBackOff"}[5m])) >= 1
        for: 15m
        labels:
          severity: warning
          service: kubernetes
          runbook_url: observability/runbooks/pod-crashloop.md
        annotations:
          summary: "{{ $labels.namespace }}/{{ $labels.pod }} container {{ $labels.container }} is crash-looping."
      - alert: ArgoCDAppDegraded
        expr: max by (name) (argocd_app_info{health_status=~"Degraded|Missing"}) == 1
        for: 15m
        labels:
          severity: warning
          service: argocd
          runbook_url: observability/runbooks/argocd-app-degraded.md
        annotations:
          summary: "Argo CD application {{ $labels.name }} is Degraded or Missing."
```

- [ ] **Step 3: Chạy promtool**

Run: `bin/promtool check rules observability/alerts/*.yaml && bin/promtool test rules observability/alerts/tests/*.yaml`
Expected: `observability/alerts/platform.yaml` → `SUCCESS: 6 rules found`, `observability/alerts/slo.yaml` → `SUCCESS: 11 rules found`; `Unit Testing: … SUCCESS` cho 2 file test.

- [ ] **Step 4: Generator** — `scripts/gen-observability.sh`

```bash
#!/usr/bin/env bash
# Generates Kubernetes objects from observability-as-code sources (spec §10). Output is committed; CI runs obs-gen-check.
#   observability/alerts/<f>.yaml → deploy/platform/observability/kind/rules/bg-<f>.yaml (PrometheusRule)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="$ROOT/deploy/platform/observability/kind"

rm -rf "$OUT/rules"; mkdir -p "$OUT/rules"
for f in "$ROOT"/observability/alerts/*.yaml; do
  n=$(basename "$f" .yaml)
  {
    echo "# GENERATED by scripts/gen-observability.sh from observability/alerts/$n.yaml — do not edit."
    echo "apiVersion: monitoring.coreos.com/v1"
    echo "kind: PrometheusRule"
    echo "metadata:"
    echo "  name: bg-$n"
    echo "  namespace: monitoring"
    echo "  labels:"
    echo "    app.kubernetes.io/part-of: banking-go"
    echo "spec:"
    grep -v '^#' "$f" | sed 's/^/  /'
  } > "$OUT/rules/bg-$n.yaml"
done
echo "generated $(ls "$OUT/rules" | wc -l) PrometheusRule file(s)"
```

Run: `chmod +x scripts/gen-observability.sh && make obs-gen && make alerts-test`
Expected: `generated 2 PrometheusRule file(s)`; promtool SUCCESS; kubeconform `Valid: 2, Invalid: 0`.

- [ ] **Step 5: Nạp vào cluster** — catalog `deploy/argocd/kind/values.yaml`, thêm cuối `addons:`:

```yaml
  - name: observability-as-code
    wave: -9
    path: deploy/platform/observability/kind
```
Thêm cuối `deploy/kind/check-platform.sh`:
```bash
# --- wave -9: observability as code
groups=$(svc_get monitoring kube-prometheus-stack-prometheus:9090 /api/v1/rules | jq -r '[.data.groups[].name] | join(",")')
for g in bg-sli bg-slo bg-platform; do [[ ,$groups, == *",$g,"* ]] || fail "rule group $g not loaded ($groups)"; done
ok "rule groups bg-sli, bg-slo, bg-platform loaded"
for _ in $(seq 24); do
  [[ $(prom 'ALERTS{alertname="Watchdog",alertstate="firing"}' | jq '.data.result | length') -ge 1 ]] && break; sleep 5
done
[[ $(prom 'ALERTS{alertname="Watchdog",alertstate="firing"}' | jq '.data.result | length') -ge 1 ]] || fail "Watchdog not firing"
ok "Watchdog firing"
```

Run: `make kind-platform`
Expected: `== wave -9: observability-as-code`, check in `ok   rule groups …` và `ok   Watchdog firing`.

- [ ] **Step 6: Commit**

```bash
git add observability/alerts scripts/gen-observability.sh deploy/platform/observability deploy/argocd/kind/values.yaml deploy/kind/check-platform.sh Makefile
git commit -m "feat(platform): v1 alert rules with SLI recording rules and promtool unit tests"
```

**Lệnh kiểm chứng:** `make alerts-test obs-gen-check`

---

### T15: Dashboard `service-overview` + `platform` + scrape + test

**Files:**
- Create: `observability/dashboards/service-overview.json`, `observability/dashboards/platform.json`, `scripts/test-dashboards.sh`, `deploy/platform/observability/kind/scrape.yaml`
- Create (sinh ra): `deploy/platform/observability/kind/dashboards/bg-dashboard-service-overview.yaml`, `bg-dashboard-platform.yaml`
- Modify: `scripts/gen-observability.sh` (thêm dashboard), `deploy/platform/argocd/values-kind.yaml` (metrics + ServiceMonitor), `scripts/kind-smoke.sh` (Grafana API), `Makefile` (`dashboards-test`)

**Interfaces:**
- Consumes: Grafana sidecar label `grafana_dashboard: "1"`, datasource uid `prom`/`traces` (T13); `gen-observability.sh`, addon `observability-as-code` (T14); metric CNPG (`cnpg_*`), RabbitMQ (`rabbitmq_*`), Argo CD (`argocd_app_info`), kube-state-metrics.
- Produces: dashboard uid `bg-service-overview` (panel "Rate (req/s)", "Errors (5xx ratio)", "Duration p95 (s)"), `bg-platform` (panel "Argo CD applications", "PostgreSQL up", "RabbitMQ messages ready"); ConfigMap `monitoring/bg-dashboard-<name>`; PodMonitor `banking-data/pg`, ServiceMonitor `banking-data/rmq`; target `make dashboards-test`.

- [ ] **Step 1: Viết test thất bại** — `scripts/test-dashboards.sh`

```bash
#!/usr/bin/env bash
# Dashboards as code (spec §10, observability.md § Dashboards): valid Grafana 12.4 JSON, uid bg-<file>,
# only fixed datasource uids (prom, traces), unique panel ids, required panels present.
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "FAIL: $*" >&2; exit 1; }
declare -A REQUIRED=(
  [service-overview]='Rate (req/s)|Errors (5xx ratio)|Duration p95 (s)'
  [platform]='Argo CD applications|PostgreSQL up|RabbitMQ messages ready'
)
n_files=0
for f in observability/dashboards/*.json; do
  [[ -e $f ]] || fail "no dashboards in observability/dashboards"
  n=$(basename "$f" .json); n_files=$((n_files + 1))
  jq empty "$f" 2>/dev/null || fail "$f is not valid JSON"
  [[ $(jq -r .uid "$f") == "bg-$n" ]] || fail "$f: uid must be bg-$n"
  [[ $(jq -r .schemaVersion "$f") -ge 41 ]] || fail "$f: schemaVersion must be ≥ 41 (Grafana 12.4)"
  bad=$(jq -r '[.. | objects | select(has("datasource")) | .datasource | objects | .uid] | unique
               | map(select(. != "prom" and . != "traces")) | join(",")' "$f")
  [[ -z $bad ]] || fail "$f: datasource uid(s) '$bad' (allowed: prom, traces)"
  [[ $(jq '[.panels[].id] | length == (unique | length)' "$f") == true ]] || fail "$f: duplicate panel ids"
  [[ -n ${REQUIRED[$n]:-} ]] || fail "$f: add its required panels to $0"
  IFS='|' read -ra want <<<"${REQUIRED[$n]}"
  for t in "${want[@]}"; do
    jq -e --arg t "$t" 'any(.panels[]; .title == $t)' "$f" >/dev/null || fail "$f: missing panel '$t'"
  done
  echo "ok   $f"
done
[[ $n_files -ge 2 ]] || fail "want service-overview and platform dashboards"
```

`Makefile` — thêm vào khối Observability:
```make
.PHONY: dashboards-test
dashboards-test: ## Validate observability/dashboards/*.json (uids, datasources, required panels)
	scripts/test-dashboards.sh
```

Run: `chmod +x scripts/test-dashboards.sh && make dashboards-test`
Expected: `FAIL: no dashboards in observability/dashboards`.

- [ ] **Step 2: `observability/dashboards/service-overview.json`**

```json
{
  "uid": "bg-service-overview",
  "title": "banking-go / Service overview (RED)",
  "description": "Golden signals per deployable, SLO burn, firing alerts, running versions (observability.md § Dashboards).",
  "tags": ["banking-go", "red", "slo"],
  "editable": false,
  "graphTooltip": 1,
  "schemaVersion": 41,
  "version": 1,
  "refresh": "30s",
  "timezone": "browser",
  "time": {"from": "now-1h", "to": "now"},
  "templating": {
    "list": [
      {
        "name": "service",
        "label": "Service",
        "type": "query",
        "datasource": {"type": "prometheus", "uid": "prom"},
        "definition": "label_values(http_server_request_duration_seconds_count, service_name)",
        "query": {"query": "label_values(http_server_request_duration_seconds_count, service_name)", "refId": "service"},
        "refresh": 2,
        "includeAll": true,
        "multi": true,
        "allValue": ".*",
        "current": {"selected": true, "text": ["All"], "value": ["$__all"]},
        "sort": 1
      }
    ]
  },
  "panels": [
    {
      "id": 1,
      "type": "timeseries",
      "title": "Rate (req/s)",
      "gridPos": {"h": 8, "w": 8, "x": 0, "y": 0},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "reqps"}, "overrides": []},
      "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "multi", "sort": "desc"}},
      "targets": [
        {
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "prom"},
          "expr": "sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~\"$service\"}[$__rate_interval]))",
          "legendFormat": "{{service_name}}"
        }
      ]
    },
    {
      "id": 2,
      "type": "timeseries",
      "title": "Errors (5xx ratio)",
      "gridPos": {"h": 8, "w": 8, "x": 8, "y": 0},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "percentunit", "min": 0}, "overrides": []},
      "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "multi", "sort": "desc"}},
      "targets": [
        {
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "prom"},
          "expr": "sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~\"$service\",http_response_status_code=~\"5..\"}[$__rate_interval])) / sum by (service_name) (rate(http_server_request_duration_seconds_count{service_name=~\"$service\",http_response_status_code!~\"4..\"}[$__rate_interval]))",
          "legendFormat": "{{service_name}}"
        }
      ]
    },
    {
      "id": 3,
      "type": "timeseries",
      "title": "Duration p95 (s)",
      "gridPos": {"h": 8, "w": 8, "x": 16, "y": 0},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "s", "min": 0}, "overrides": []},
      "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "multi", "sort": "desc"}},
      "targets": [
        {
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "prom"},
          "expr": "histogram_quantile(0.95, sum by (service_name, le) (rate(http_server_request_duration_seconds_bucket{service_name=~\"$service\"}[$__rate_interval])))",
          "legendFormat": "{{service_name}}"
        }
      ]
    },
    {
      "id": 4,
      "type": "timeseries",
      "title": "core gRPC rate by method",
      "gridPos": {"h": 8, "w": 12, "x": 0, "y": 8},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "reqps"}, "overrides": []},
      "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "multi", "sort": "desc"}},
      "targets": [
        {
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "prom"},
          "expr": "sum by (rpc_method) (rate(rpc_server_duration_milliseconds_count{service_name=\"core\"}[$__rate_interval]))",
          "legendFormat": "{{rpc_method}}"
        }
      ]
    },
    {
      "id": 5,
      "type": "timeseries",
      "title": "core gRPC server error ratio",
      "gridPos": {"h": 8, "w": 12, "x": 12, "y": 8},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "percentunit", "min": 0}, "overrides": []},
      "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "multi", "sort": "desc"}},
      "targets": [
        {
          "refId": "A",
          "datasource": {"type": "prometheus", "uid": "prom"},
          "expr": "sum(rate(rpc_server_duration_milliseconds_count{service_name=\"core\",rpc_grpc_status_code=~\"2|4|13|14|15\"}[$__rate_interval])) / sum(rate(rpc_server_duration_milliseconds_count{service_name=\"core\"}[$__rate_interval]))",
          "legendFormat": "core"
        }
      ]
    },
    {
      "id": 6,
      "type": "stat",
      "title": "Error budget burn rate (1h)",
      "description": "sli:error_ratio:rate1h / 0.001 — 14.4 or more pages (ErrorBudgetBurnFast).",
      "gridPos": {"h": 6, "w": 8, "x": 0, "y": 16},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "none", "decimals": 2, "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "orange", "value": 1}, {"color": "red", "value": 14.4}]}}, "overrides": []},
      "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "colorMode": "background", "textMode": "value_and_name"},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "sli:error_ratio:rate1h / 0.001", "legendFormat": "{{service}}"}
      ]
    },
    {
      "id": 7,
      "type": "stat",
      "title": "Firing alerts",
      "gridPos": {"h": 6, "w": 8, "x": 8, "y": 16},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "none", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 1}]}}, "overrides": []},
      "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "colorMode": "background"},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "count(ALERTS{alertstate=\"firing\",severity!=\"none\"}) or vector(0)"}
      ]
    },
    {
      "id": 8,
      "type": "table",
      "title": "Running versions",
      "gridPos": {"h": 6, "w": 8, "x": 16, "y": 16},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {}, "overrides": []},
      "options": {"showHeader": true},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "max by (service_name, service_version) (target_info{service_name=~\"$service\"})", "format": "table", "instant": true}
      ]
    }
  ]
}
```

- [ ] **Step 3: `observability/dashboards/platform.json`**

```json
{
  "uid": "bg-platform",
  "title": "banking-go / Platform (Argo CD, CNPG, RabbitMQ)",
  "description": "GitOps health, PostgreSQL (CNPG) and RabbitMQ on the cluster, pod readiness (spec §10).",
  "tags": ["banking-go", "platform"],
  "editable": false,
  "graphTooltip": 1,
  "schemaVersion": 41,
  "version": 1,
  "refresh": "30s",
  "timezone": "browser",
  "time": {"from": "now-3h", "to": "now"},
  "templating": {"list": []},
  "panels": [
    {
      "id": 1,
      "type": "table",
      "title": "Argo CD applications",
      "gridPos": {"h": 9, "w": 16, "x": 0, "y": 0},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {}, "overrides": []},
      "options": {"showHeader": true},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "max by (name, health_status, sync_status) (argocd_app_info)", "format": "table", "instant": true}
      ]
    },
    {
      "id": 2,
      "type": "stat",
      "title": "Argo CD apps not Healthy",
      "gridPos": {"h": 9, "w": 8, "x": 16, "y": 0},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "none", "thresholds": {"mode": "absolute", "steps": [{"color": "green", "value": null}, {"color": "red", "value": 1}]}}, "overrides": []},
      "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "colorMode": "background"},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "count(argocd_app_info{health_status!=\"Healthy\"}) or vector(0)"}
      ]
    },
    {
      "id": 3,
      "type": "stat",
      "title": "PostgreSQL up",
      "gridPos": {"h": 6, "w": 6, "x": 0, "y": 9},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "none", "thresholds": {"mode": "absolute", "steps": [{"color": "red", "value": null}, {"color": "green", "value": 1}]}}, "overrides": []},
      "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "colorMode": "background"},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "max(cnpg_collector_up) or vector(0)"}
      ]
    },
    {
      "id": 4,
      "type": "timeseries",
      "title": "PostgreSQL backends by database",
      "gridPos": {"h": 6, "w": 6, "x": 6, "y": 9},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "none", "min": 0}, "overrides": []},
      "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "multi", "sort": "desc"}},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "sum by (datname) (cnpg_backends_total)", "legendFormat": "{{datname}}"}
      ]
    },
    {
      "id": 5,
      "type": "stat",
      "title": "RabbitMQ messages ready",
      "gridPos": {"h": 6, "w": 6, "x": 12, "y": 9},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "none"}, "overrides": []},
      "options": {"reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": false}, "colorMode": "value"},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "sum(rabbitmq_queue_messages_ready) or vector(0)"}
      ]
    },
    {
      "id": 6,
      "type": "timeseries",
      "title": "RabbitMQ connections",
      "gridPos": {"h": 6, "w": 6, "x": 18, "y": 9},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "none", "min": 0}, "overrides": []},
      "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "multi", "sort": "desc"}},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "sum(rabbitmq_connections)", "legendFormat": "connections"}
      ]
    },
    {
      "id": 7,
      "type": "timeseries",
      "title": "Pods not ready",
      "gridPos": {"h": 7, "w": 12, "x": 0, "y": 15},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "none", "min": 0}, "overrides": []},
      "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "multi", "sort": "desc"}},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "sum by (namespace) (kube_pod_status_ready{condition=\"false\",namespace=~\"banking|banking-data|observability|monitoring|argocd\"})", "legendFormat": "{{namespace}}"}
      ]
    },
    {
      "id": 8,
      "type": "timeseries",
      "title": "Container restarts (1h)",
      "gridPos": {"h": 7, "w": 12, "x": 12, "y": 15},
      "datasource": {"type": "prometheus", "uid": "prom"},
      "fieldConfig": {"defaults": {"unit": "none", "min": 0}, "overrides": []},
      "options": {"legend": {"displayMode": "list", "placement": "bottom", "showLegend": true}, "tooltip": {"mode": "multi", "sort": "desc"}},
      "targets": [
        {"refId": "A", "datasource": {"type": "prometheus", "uid": "prom"}, "expr": "sum by (namespace, pod) (increase(kube_pod_container_status_restarts_total{namespace=~\"banking|banking-data\"}[1h]))", "legendFormat": "{{namespace}}/{{pod}}"}
      ]
    }
  ]
}
```

Run: `make dashboards-test`
Expected: `ok   observability/dashboards/platform.json`, `ok   observability/dashboards/service-overview.json`.

- [ ] **Step 4: Generator + scrape**

Thêm vào cuối `scripts/gen-observability.sh` (trước dòng `echo "generated …"` thay bằng dòng echo mới):
```bash
#   observability/dashboards/<f>.json → deploy/platform/observability/kind/dashboards/bg-dashboard-<f>.yaml (ConfigMap, Grafana sidecar)
rm -rf "$OUT/dashboards"; mkdir -p "$OUT/dashboards"
for f in "$ROOT"/observability/dashboards/*.json; do
  n=$(basename "$f" .json)
  {
    echo "# GENERATED by scripts/gen-observability.sh from observability/dashboards/$n.json — do not edit."
    echo "apiVersion: v1"
    echo "kind: ConfigMap"
    echo "metadata:"
    echo "  name: bg-dashboard-$n"
    echo "  namespace: monitoring"
    echo "  labels:"
    echo "    app.kubernetes.io/part-of: banking-go"
    echo "    grafana_dashboard: \"1\""
    echo "data:"
    echo "  $n.json: |-"
    sed 's/^/    /' "$f"
  } > "$OUT/dashboards/bg-dashboard-$n.yaml"
done
echo "generated $(ls "$OUT/rules" | wc -l) PrometheusRule and $(ls "$OUT/dashboards" | wc -l) dashboard file(s)"
```
(xóa dòng `echo "generated $(ls "$OUT/rules" | wc -l) PrometheusRule file(s)"` cũ.)

`deploy/platform/observability/kind/scrape.yaml` (viết tay, không bị generator xóa):
```yaml
# Scrape targets for the platform dashboard (kind): CNPG instance metrics + RabbitMQ prometheus plugin.
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: pg
  namespace: banking-data
spec:
  selector:
    matchLabels:
      cnpg.io/cluster: pg
  podMetricsEndpoints:
    - port: metrics
---
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: rmq
  namespace: banking-data
spec:
  selector:
    matchLabels:
      app.kubernetes.io/name: rmq
  endpoints:
    - port: prometheus
      interval: 30s
```

`deploy/platform/argocd/values-kind.yaml` — thêm vào khối `controller:`:
```yaml
  metrics:
    enabled: true
    serviceMonitor:
      enabled: true
```

Thêm vào `scripts/kind-smoke.sh` ngay trước `echo "kind-smoke: all checks passed"`:
```bash
# 6. Dashboards as code are loaded in Grafana (spec criterion 5)
guser=$(kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-user}' | base64 -d)
gpass=$(kubectl -n monitoring get secret kube-prometheus-stack-grafana -o jsonpath='{.data.admin-password}' | base64 -d)
for uid in bg-service-overview bg-platform; do
  curl -sk --max-time 10 -u "$guser:$gpass" "https://grafana.kind.localhost/api/dashboards/uid/$uid" \
    | jq -e --arg u "$uid" '.dashboard.uid == $u' >/dev/null || fail "Grafana dashboard $uid missing"
  ok "Grafana dashboard $uid"
done
```

Run: `make obs-gen && make dashboards-test alerts-test && make kind-up && make kind-platform && make kind-smoke`
Expected: `generated 2 PrometheusRule and 2 dashboard file(s)`; kind-smoke thêm `ok   Grafana dashboard bg-service-overview`, `ok   Grafana dashboard bg-platform`; `prom_value 'max(cnpg_collector_up)'` = 1 (kiểm tay: `bash -c '. scripts/lib/kind.sh; PATH=bin:$PATH prom_value "max(cnpg_collector_up)"'`).

- [ ] **Step 5: Commit**

```bash
git add observability/dashboards scripts/test-dashboards.sh scripts/gen-observability.sh deploy/platform/observability deploy/platform/argocd/values-kind.yaml scripts/kind-smoke.sh Makefile
git commit -m "feat(platform): service-overview and platform grafana dashboards as code"
```

**Lệnh kiểm chứng:** `make dashboards-test obs-gen-check && make kind-smoke`

---

### T16: Alertmanager → Telegram (critical + Watchdog) từ Sealed Secret

**Owner trước:** tạo Telegram bot (@BotFather) lấy token, lấy chat id của owner (nhắn bot rồi `curl https://api.telegram.org/bot<token>/getUpdates`), ghi `TELEGRAM_BOT_TOKEN=` và `TELEGRAM_CHAT_ID=` vào `deploy/secrets/kind.env` (git-ignored). Không dán token vào chat với AI.

**Files:**
- Create: `observability/alertmanager/kind.yaml`, `scripts/render-alertmanager.sh`, `scripts/test-alertmanager.sh`
- Create (sinh ra): `deploy/secrets/kind/monitoring-alertmanager-kind-config.sealed.yaml`
- Modify: `scripts/seal-kind.sh`, `deploy/secrets/kind.env.example`, `deploy/platform/kube-prometheus-stack/values-kind.yaml`, `scripts/kind-smoke.sh`, `Makefile` (`alertmanager-test`)

**Interfaces:**
- Consumes: `seal()` + `ENV_FILE` của `seal-kind.sh` (T10), namespace `monitoring` (T13), alert labels `severity`/`alertname` (T14), `prom` (T13), `bin/amtool` (T1).
- Produces: template `observability/alertmanager/kind.yaml` (placeholder `${TELEGRAM_BOT_TOKEN}`, `${TELEGRAM_CHAT_ID}`), receiver `telegram` (route `alertname="Watchdog"` repeat 12h và `severity="critical"` repeat 1h), receiver `"null"` cho phần còn lại; Secret `monitoring/alertmanager-kind-config` (key `alertmanager.yaml`) dùng bởi `alertmanager.alertmanagerSpec.configSecret`; `scripts/render-alertmanager.sh [template]`; target `make alertmanager-test`.

- [ ] **Step 1: Viết test thất bại** — `scripts/test-alertmanager.sh`

```bash
#!/usr/bin/env bash
# Alertmanager config as code (spec §10): renders observability/alertmanager/kind.yaml with dummy Telegram values,
# validates it with amtool and checks routing: critical + Watchdog → telegram, the rest → "null".
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
TELEGRAM_BOT_TOKEN=123456:TEST-token_x TELEGRAM_CHAT_ID=-1001234 scripts/render-alertmanager.sh > "$TMP/am.yaml"
amtool check-config "$TMP/am.yaml" >/dev/null || fail "amtool check-config"
route() { amtool config routes test --config.file="$TMP/am.yaml" "$@"; }
[[ $(route alertname=Watchdog severity=none service=platform) == telegram ]] || fail "Watchdog must go to telegram"
[[ $(route alertname=ErrorBudgetBurnFast severity=critical service=public-api) == telegram ]] || fail "critical must go to telegram"
[[ $(route alertname=LatencyP95Breach severity=warning service=public-api) == null ]] || fail "warning must go to null on kind"
if TELEGRAM_BOT_TOKEN='x"; rm -rf /' TELEGRAM_CHAT_ID=1 scripts/render-alertmanager.sh >/dev/null 2>&1; then fail "malformed token accepted"; fi
echo "ok   alertmanager kind config: valid, critical + Watchdog → telegram"
```

`Makefile` — thêm vào khối Observability:
```make
.PHONY: alertmanager-test
alertmanager-test: tools-k8s ## amtool check + routing test of observability/alertmanager/kind.yaml
	scripts/test-alertmanager.sh
```

Run: `chmod +x scripts/test-alertmanager.sh && make alertmanager-test`
Expected: FAIL — `scripts/render-alertmanager.sh: No such file or directory`.

- [ ] **Step 2: Template + renderer**

`observability/alertmanager/kind.yaml`:
```yaml
# Alertmanager config for env kind (observability.md § Routing, staging variant without email):
# critical + Watchdog → Telegram; everything else → "null" (kind has no SLO commitment, ADR 0011).
# Rendered by scripts/render-alertmanager.sh and sealed by `make seal` into monitoring/alertmanager-kind-config.
global:
  resolve_timeout: 5m
route:
  receiver: "null"
  group_by: [alertname, service, env]
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 12h
  routes:
    - matchers: ['alertname="Watchdog"']
      receiver: telegram
      repeat_interval: 12h
    - matchers: ['severity="critical"']
      receiver: telegram
      repeat_interval: 1h
inhibit_rules:
  - source_matchers: ['severity="critical"']
    target_matchers: ['severity="warning"']
    equal: [alertname, service]
receivers:
  - name: "null"
  - name: telegram
    telegram_configs:
      - bot_token: '${TELEGRAM_BOT_TOKEN}'
        chat_id: ${TELEGRAM_CHAT_ID}
        send_resolved: true
        parse_mode: HTML
```

`scripts/render-alertmanager.sh`:
```bash
#!/usr/bin/env bash
# Renders the Alertmanager template with TELEGRAM_BOT_TOKEN / TELEGRAM_CHAT_ID from the environment (stdout).
#   TELEGRAM_BOT_TOKEN=… TELEGRAM_CHAT_ID=… scripts/render-alertmanager.sh [template]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TEMPLATE=${1:-$ROOT/observability/alertmanager/kind.yaml}
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}" "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is required}"
[[ $TELEGRAM_CHAT_ID =~ ^-?[0-9]+$ ]] || { echo "render-alertmanager: TELEGRAM_CHAT_ID must be numeric" >&2; exit 1; }
[[ $TELEGRAM_BOT_TOKEN =~ ^[0-9]+:[A-Za-z0-9_-]+$ ]] || { echo "render-alertmanager: TELEGRAM_BOT_TOKEN has an unexpected format" >&2; exit 1; }
sed -e "s|\${TELEGRAM_BOT_TOKEN}|$TELEGRAM_BOT_TOKEN|g" -e "s|\${TELEGRAM_CHAT_ID}|$TELEGRAM_CHAT_ID|g" "$TEMPLATE"
```

Run: `chmod +x scripts/render-alertmanager.sh && make alertmanager-test`
Expected: `ok   alertmanager kind config: valid, critical + Watchdog → telegram`.

- [ ] **Step 3: Seal + wiring**

`deploy/secrets/kind.env.example` — thêm:
```dotenv
# Alertmanager → Telegram (T16, owner): bot token from @BotFather, numeric chat id of the owner.
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
```

`scripts/seal-kind.sh` — thêm trước dòng cuối `"$ROOT/scripts/check-no-plain-secrets.sh"`:
```bash
# monitoring: Alertmanager config with the Telegram receiver (T16); skipped until the owner fills TELEGRAM_*.
if [[ -n ${TELEGRAM_BOT_TOKEN:-} && -n ${TELEGRAM_CHAT_ID:-} ]]; then
  seal monitoring alertmanager-kind-config --from-file=alertmanager.yaml=<("$ROOT/scripts/render-alertmanager.sh")
else
  echo "skip monitoring/alertmanager-kind-config: set TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID in $ENV_FILE"
fi
```

`deploy/platform/kube-prometheus-stack/values-kind.yaml` — trong `alertmanager.alertmanagerSpec` thêm:
```yaml
    # Whole config from the Sealed Secret (contains the Telegram token); template: observability/alertmanager/kind.yaml
    configSecret: alertmanager-kind-config
```

`scripts/kind-smoke.sh` — thêm trước `echo "kind-smoke: all checks passed"`:
```bash
# 7. Watchdog reaches Telegram (spec criterion 5): Alertmanager reports successful telegram notifications
active=$(svc_get monitoring kube-prometheus-stack-alertmanager:9093 '/api/v2/alerts?filter=alertname%3D%22Watchdog%22' | jq 'length')
[[ $active -ge 1 ]] || fail "Watchdog not active in Alertmanager"
sent=0
for _ in $(seq 24); do
  sent=$(prom_value 'sum(alertmanager_notifications_total{integration="telegram"})')
  awk -v v="$sent" 'BEGIN{exit !(v > 0)}' && break; sleep 5
done
failed=$(prom_value 'sum(alertmanager_notifications_failed_total{integration="telegram"})')
awk -v s="$sent" -v f="$failed" 'BEGIN{exit !(s > 0 && f == 0)}' || fail "telegram notifications sent=$sent failed=$failed"
ok "Alertmanager delivered $sent telegram notification(s), 0 failed"
```

- [ ] **Step 4: Chạy trên kind**

Run: `make seal && make kind-platform && make kind-smoke`
Expected: `sealed monitoring/alertmanager-kind-config`; kind-smoke thêm `ok   Alertmanager delivered N telegram notification(s), 0 failed`; tin `Watchdog` xuất hiện trong Telegram của owner.

- [ ] **Step 5: Commit**

```bash
git add observability/alertmanager scripts/render-alertmanager.sh scripts/test-alertmanager.sh scripts/seal-kind.sh deploy/secrets/kind.env.example \
  deploy/secrets/kind deploy/platform/kube-prometheus-stack/values-kind.yaml scripts/kind-smoke.sh Makefile
git commit -m "feat(platform): alertmanager telegram routing for critical alerts and watchdog"
```

**Lệnh kiểm chứng:** `make alertmanager-test && make kind-smoke`

---

### T17: Runbook + `make kind-watch`

**Files:**
- Create: `observability/runbooks/watchdog.md`, `error-budget-burn.md`, `latency-p95-breach.md`, `telemetry-pipeline.md`, `certificate-expiry.md`, `pod-crashloop.md`, `argocd-app-degraded.md`
- Create: `scripts/test-runbooks.sh`, `scripts/kind-watch.sh`
- Modify: `Makefile` (`runbooks-test`, `kind-watch`)

**Interfaces:**
- Consumes: nhãn `runbook_url` của rule (T14), `prom_value` (T13), `sli:error_ratio:rate5m` (T14).
- Produces: 7 runbook theo khung observability.md (5 runbook spec yêu cầu cho Watchdog, SLO burn, p95, TelemetryPipeline, cert expiry + 2 cho `PodCrashLooping`/`ArgoCDAppDegraded` để không có `runbook_url` treo); `scripts/kind-watch.sh` (env `WATCH_MINUTES`, mặc định 10; exit 1 kèm lệnh rollback đề xuất); target `make runbooks-test`, `make kind-watch`.

- [ ] **Step 1: Viết test thất bại** — `scripts/test-runbooks.sh`

```bash
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
```

`Makefile` — thêm vào khối Observability:
```make
.PHONY: runbooks-test
runbooks-test: tools-k8s ## Every runbook_url label points to a runbook with the required sections
	scripts/test-runbooks.sh
```

Run: `chmod +x scripts/test-runbooks.sh && make runbooks-test`
Expected: `FAIL: missing runbook observability/runbooks/argocd-app-degraded.md`.

- [ ] **Step 2: Viết 7 runbook**

`observability/runbooks/watchdog.md`:
````markdown
# Watchdog
- Mức / NFR / AD: none (dead man's switch) · NFR-S7 gián tiếp · AD-13 · O-14

## Ý nghĩa
Alert `vector(1)` luôn firing. Telegram nhận tin `Watchdog` mỗi `repeat_interval` (12 h). Không còn nhận nghĩa là chuỗi
Prometheus → Alertmanager → Telegram đã hỏng và mọi alert khác cũng không tới.

## Tác động
Không ảnh hưởng khách hàng trực tiếp; mất khả năng phát hiện sự cố trên kind.

## Kiểm tra (chỉ đọc)
- `bin/kubectl -n monitoring get pods` — Prometheus, Alertmanager có Running?
- PromQL: `ALERTS{alertname="Watchdog",alertstate="firing"}` có 1 series?
- PromQL: `sum(alertmanager_notifications_failed_total{integration="telegram"})` có tăng?
- `bin/kubectl -n monitoring logs statefulset/alertmanager-kube-prometheus-stack-alertmanager -c alertmanager | grep -i telegram`
- Secret `monitoring/alertmanager-kind-config` tồn tại? (`bin/kubectl -n monitoring get secret alertmanager-kind-config`)

## Xử lý
- Token/chat id sai hoặc bot bị chặn → sửa `deploy/secrets/kind.env`, `make seal`, commit `deploy/secrets/kind/monitoring-alertmanager-kind-config.sealed.yaml` qua PR → Argo CD sync.
- Pod Prometheus/Alertmanager lỗi → sửa `deploy/platform/kube-prometheus-stack/values-kind.yaml` qua PR.

## Không được làm
- Silence hoặc xóa `Watchdog`; sửa Secret bằng `kubectl edit`; dán bot token vào issue/chat.

## Đóng sự cố
Tin `Watchdog` tới lại Telegram và `alertmanager_notifications_failed_total` không tăng trong 15 phút. Mất alerting > 1 h → ghi `docs/incidents/<yyyy-mm-dd>-watchdog.md`.
````

`observability/runbooks/error-budget-burn.md`:
````markdown
# ErrorBudgetBurnFast / ErrorBudgetBurnSlow
- Mức / NFR / AD: critical (fast) · warning (slow) · NFR-A1 · AD-13, AD-26

## Ý nghĩa
Tỷ lệ lỗi (`sli:error_ratio:<window>`: 5xx / request không 4xx ở edge; mã gRPC lỗi server ở core) đốt error budget
30 ngày (SLO 99.9%) nhanh (14.4× trong 1 h, 6× trong 6 h) hoặc đều (3× trong 1 ngày, 1× trong 3 ngày).

## Tác động
Khách hàng/nhân viên gặp lỗi khi gọi API; tiếp diễn sẽ phá SLO tháng.

## Kiểm tra (chỉ đọc)
- Dashboard `banking-go / Service overview (RED)`: service nào, từ lúc nào, panel "Errors (5xx ratio)".
- PromQL: `sum by (service_name, http_route, http_response_status_code) (rate(http_server_request_duration_seconds_count{http_response_status_code=~"5.."}[5m]))`
- Trace lỗi trong Jaeger (`https://jaeger.kind.localhost`, service tương ứng, tag `error=true`).
- Deploy gần nhất: `git log --oneline -5 -- deploy/releases/kind.yaml`; Argo CD app có `Degraded`?
- Phụ thuộc: pod `pg-1`, `rmq-server-0`, Collector (`bin/kubectl -n banking-data get pods`).

## Xử lý
- Do deploy mới → owner chạy `gh workflow run rollback.yml -f env=kind -f revert_sha=<bump_sha>` (AI chỉ đề xuất lệnh).
- Do hạ tầng (DB, broker) → xử lý theo runbook tương ứng, sửa qua Git.

## Không được làm
- AI tự chạy rollback; tăng timeout hoặc nới SLO để che lỗi; `kubectl` sửa tay tài nguyên.

## Đóng sự cố
`sli:error_ratio:rate1h` < 0.001 trong 1 h và alert resolved. Nguyên nhân là bug → test tái hiện + fix qua PR (constitution II.1); ghi `docs/incidents/`.
````

`observability/runbooks/latency-p95-breach.md`:
````markdown
# LatencyP95Breach
- Mức / NFR / AD: warning · NFR-P1, NFR-P2, NFR-P3 · AD-13 · O-1

## Ý nghĩa
`sli:latency_p95:rate5m` của một `route_class` vượt ngưỡng SLO liên tục 10 phút: read 100 ms, write 300 ms, login 500 ms, transfer 200 ms.

## Tác động
Trải nghiệm chậm; transfer chậm kéo dài làm tăng timeout phía client.

## Kiểm tra (chỉ đọc)
- Dashboard Service overview, panel "Duration p95 (s)".
- PromQL: `histogram_quantile(0.95, sum by (http_route, le) (rate(http_server_request_duration_seconds_bucket{service_name="<svc>"}[5m])))`
- Trace chậm trong Jaeger (sắp theo duration); span DB/gRPC nào chiếm thời gian.
- core gRPC: `histogram_quantile(0.95, sum by (rpc_method, le) (rate(rpc_server_duration_milliseconds_bucket{service_name="core"}[5m])))`
- Deploy gần nhất (`git log -- deploy/releases/kind.yaml`), CPU throttling pod (`bin/kubectl -n banking top pods`).

## Xử lý
- Do deploy → đề xuất `rollback.yml` cho owner.
- Do tài nguyên kind → tăng `resources` trong `values-kind.yaml` qua PR.

## Không được làm
- Nới ngưỡng SLO/alert để tắt cảnh báo.

## Đóng sự cố
p95 dưới ngưỡng 30 phút liên tục; ghi nguyên nhân vào PR/`docs/incidents/` nếu ảnh hưởng demo.
````

`observability/runbooks/telemetry-pipeline.md`:
````markdown
# TelemetryPipelineDegraded
- Mức / NFR / AD: warning · NFR-M (quan sát được) · AD-13 · O-7, O-8

## Ý nghĩa
OpenTelemetry Collector (`observability/otel-collector`) đang lỗi khi export (metric/trace/log) hoặc không còn được scrape (`up{job="otel-collector"}` mất) trong 10 phút.

## Tác động
Mất metric RED/trace: alert SLO không còn đáng tin, dashboard trống; ứng dụng vẫn chạy.

## Kiểm tra (chỉ đọc)
- `bin/kubectl -n observability get pods`; `bin/kubectl -n observability logs deploy/otel-collector | tail -50`
- PromQL: `sum by (exporter) (rate({__name__=~"otelcol_exporter_send_failed_.*"}[5m]))`, `otelcol_exporter_queue_size`
- Backend: Prometheus (`kube-prometheus-stack-prometheus`) và Jaeger (`jaeger`) có Running?
- `make collector-validate` với config hiện tại.

## Xử lý
- Sửa `deploy/collector/kind.yaml` hoặc values backend qua PR (chạy `make collector-validate` trước) → Argo CD sync.

## Không được làm
- Cho service gửi thẳng tới backend (bỏ Collector, trái AD-13); tắt processor `redaction`.

## Đóng sự cố
Không còn `send_failed` 15 phút, `up{job="otel-collector"} == 1`, kind-smoke phần telemetry pass.
````

`observability/runbooks/certificate-expiry.md`:
````markdown
# CertificateExpiringSoon / CertificateNotReady
- Mức / NFR / AD: warning (< 14 ngày) · critical (< 3 ngày hoặc NotReady) · NFR-S7 · AD-10

## Ý nghĩa
Certificate của cert-manager sắp hết hạn mà chưa renew, hoặc đang `Ready=False` (wildcard `*.kind.localhost`, CA nội bộ, leaf mTLS `<svc>-mtls`).

## Tác động
Hết hạn → HTTPS qua Traefik hoặc mTLS nội bộ hỏng, toàn bộ API/SPA không truy cập được.

## Kiểm tra (chỉ đọc)
- `bin/kubectl get certificates -A`; `bin/kubectl -n <ns> describe certificate <name>` (Events, lý do renew fail)
- `bin/kubectl get clusterissuer` — `kind-ca`, `bg-internal-ca`, `selfsigned` có Ready?
- `bin/kubectl -n cert-manager logs deploy/cert-manager | grep -i <name>`
- PromQL: `certmanager_certificate_expiration_timestamp_seconds - time()`

## Xử lý
- Sửa issuer/Certificate trong `deploy/platform/cert-manager-issuers/kind/` hoặc values chart qua PR → cert-manager renew.

## Không được làm
- Tắt TLS/mTLS tạm thời; tự xóa Secret CA (`kind-root-ca`, `bg-internal-root-ca`).

## Đóng sự cố
Certificate `Ready=True`, hết hạn > 14 ngày, alert resolved.
````

`observability/runbooks/pod-crashloop.md`:
````markdown
# PodCrashLooping
- Mức / NFR / AD: warning · NFR-A5 · AD-26

## Ý nghĩa
Một container ở trạng thái `CrashLoopBackOff` liên tục 15 phút (kube-state-metrics).

## Tác động
Rollout mới kẹt (pod cũ vẫn phục vụ nhờ `maxUnavailable: 0`) hoặc add-on mất khả dụng.

## Kiểm tra (chỉ đọc)
- `bin/kubectl -n <namespace> describe pod <pod>`; `bin/kubectl -n <namespace> logs <pod> -c <container> --previous`
- Config/Secret thiếu (`CreateContainerConfigError`, env `BG_<SVC>_*`), OOMKilled (`lastState.terminated.reason`).
- Deploy gần nhất (`git log -- deploy/releases/kind.yaml deploy/helm`).

## Xử lý
- Do image/config mới → đề xuất `rollback.yml` (digest) hoặc PR revert values.
- OOMKilled → tăng `resources.limits.memory` trong `values-kind.yaml` qua PR.

## Không được làm
- `kubectl delete pod` lặp lại để "cho qua"; sửa Deployment bằng `kubectl edit`.

## Đóng sự cố
Pod Ready ổn định 15 phút, restart không tăng; nguyên nhân là bug → test tái hiện + fix.
````

`observability/runbooks/argocd-app-degraded.md`:
````markdown
# ArgoCDAppDegraded
- Mức / NFR / AD: warning · NFR-A5 · AD-14 · ADR 0011

## Ý nghĩa
Application Argo CD (`argocd_app_info`) ở `Degraded` hoặc `Missing` 15 phút: rollout kẹt quá `progressDeadlineSeconds`, PreSync migration fail, hoặc add-on không healthy.

## Tác động
Phiên bản mới không lên (bản cũ vẫn chạy nếu migration fail); add-on hỏng có thể ảnh hưởng mọi app.

## Kiểm tra (chỉ đọc)
- `bin/kubectl -n argocd get applications`; `bin/kubectl -n argocd get application <name> -o jsonpath='{.status.conditions}'`
- UI `https://argocd.kind.localhost` → app → resource đỏ, Events.
- Migration: `bin/kubectl -n banking logs job/<svc>-migrate`.
- Commit gây ra: `git log --oneline -5 -- deploy/`.

## Xử lý
- Digest lỗi → owner chạy `rollback.yml -f env=kind -f revert_sha=<bump_sha>`.
- Config lỗi → PR revert commit config.

## Không được làm
- Sync tay với `--force`/`--replace`, tắt auto-sync/selfHeal để "chạy tạm", `kubectl apply` tay.

## Đóng sự cố
Mọi Application `Synced/Healthy` (`deploy/kind/wait-argocd.sh`), `make kind-smoke` pass.
````

Run: `make runbooks-test`
Expected: 7 dòng `ok   observability/runbooks/…`.

- [ ] **Step 3: Viết `scripts/kind-watch.sh`** (post-deploy watch biến thể kind: 10 phút, chỉ báo, owner quyết)

```bash
#!/usr/bin/env bash
# make kind-watch: post-deploy watch on kind (observability.md § Post-deploy watch; kind = informative, 10 min).
# Exit 1 on breach and print the rollback command for the owner (AI only proposes it, constitution IV.3).
#   WATCH_MINUTES=10 scripts/kind-watch.sh
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
require_kind_context
MINUTES=${WATCH_MINUTES:-10}
STEP=${WATCH_STEP_SECONDS:-60}
int() { printf '%.0f' "$1"; }
restarts0=$(int "$(prom_value 'sum(kube_pod_container_status_restarts_total{namespace="banking"})')")
end=$(( $(date +%s) + MINUTES * 60 ))
breach=""
while :; do
  crit=$(int "$(prom_value 'count(ALERTS{alertstate="firing",severity="critical"})')")
  err=$(prom_value 'max(sli:error_ratio:rate5m)')
  restarts=$(( $(int "$(prom_value 'sum(kube_pod_container_status_restarts_total{namespace="banking"})')") - restarts0 ))
  printf '%s critical=%s error_ratio_5m=%s new_restarts=%s\n' "$(date -u +%H:%M:%S)" "$crit" "$err" "$restarts"
  if (( crit > 0 )); then breach="critical alert firing"; fi
  if awk -v e="$err" 'BEGIN{exit !(e > 0.005)}'; then breach="5xx/server-error ratio > 0.5%"; fi
  if (( restarts > 0 )); then breach="pod restarts in namespace banking"; fi
  [[ -z $breach && $(date +%s) -lt $end ]] || break
  sleep "$STEP"
done
if [[ -n $breach ]]; then
  sha=$(git -C "$ROOT" log -1 --format=%h -- deploy/releases/kind.yaml 2>/dev/null || true)
  echo "WATCH FAILED: $breach"
  echo "Đề xuất (owner quyết): gh workflow run rollback.yml -f env=kind -f revert_sha=${sha:-<bump_sha>}"
  exit 1
fi
echo "watch ok: $MINUTES phút không vượt ngưỡng"
```

`Makefile` — thêm vào khối kind:
```make
.PHONY: kind-watch
kind-watch: tools-k8s ## Post-deploy watch on kind (WATCH_MINUTES, default 10); prints a rollback proposal on breach
	scripts/kind-watch.sh
```

- [ ] **Step 4: Chạy watch (đạt + vượt ngưỡng)**

Run: `chmod +x scripts/kind-watch.sh && WATCH_MINUTES=2 make kind-watch`
Expected: 2–3 dòng trạng thái, `watch ok: 2 phút không vượt ngưỡng`.

Run (tiêm lỗi có chủ đích trên kind, trước GitOps): `bin/kubectl -n banking set env deploy/mock-otp BG_MOCK_OTP_ADMIN_ADDR=:bad; WATCH_MINUTES=3 WATCH_STEP_SECONDS=30 make kind-watch; bin/kubectl -n banking set env deploy/mock-otp BG_MOCK_OTP_ADMIN_ADDR-`
Expected: `WATCH FAILED: pod restarts in namespace banking` + dòng `Đề xuất (owner quyết): gh workflow run rollback.yml …` (exit 1); lệnh cuối gỡ biến lỗi, pod cũ vẫn phục vụ suốt quá trình (`maxUnavailable: 0`).

- [ ] **Step 5: Commit**

```bash
git add observability/runbooks scripts/test-runbooks.sh scripts/kind-watch.sh Makefile
git commit -m "docs(platform): runbooks for v1 alerts and kind post-deploy watch"
```

**Lệnh kiểm chứng:** `make runbooks-test && WATCH_MINUTES=2 make kind-watch`

**Demo S2:** `make kind-smoke` (thêm Jaeger, RED, dashboard, Telegram) → mở `https://grafana.kind.localhost` → dashboard `banking-go / Service overview (RED)` và `banking-go / Platform`; tin `Watchdog` trên Telegram.

---

# Sprint S3 — GitOps + pipeline thật (cần repo GitHub; owner làm các bước tay trước)

**Sprint goal:** commit lên `main` → `main.yml` build/scan/ký/push 6 image, bot ghi digest vào `deploy/releases/kind.yaml`; Argo CD trên kind (app-of-apps) tự sync bản mới, chạy PreSync migration; `rollback.yml` đưa digest về bản trước; nghiệm thu đủ tiêu chí 1–6 của spec. **Demo:** `make kind-down && make kind-up GH_OWNER=<owner>` → mọi Application `Synced/Healthy`; push một commit → digest mới chạy trên kind; `gh workflow run rollback.yml` → digest cũ.

### T18: `ci.yml` — build 6 image (không push), deploy lint/test, observability test, actionlint

**Files:**
- Modify: `.github/workflows/ci.yml` (thêm job `images`, `deploy`, `observability`, `actionlint`), `Makefile` (`actionlint`)

**Interfaces:**
- Consumes: Dockerfile + build-arg (T3, T4); `make tools-k8s helm-lint helm-test alerts-test dashboards-test alertmanager-test runbooks-test obs-gen-check collector-validate`, `scripts/vendor-manifests.sh --check`, `scripts/check-no-plain-secrets.sh` (T1–T17).
- Produces: `ci.yml` (vẫn `pull_request` + `workflow_call`) với job id `images` (matrix `image`, `dockerfile`, `build-arg`), `deploy`, `observability`, `actionlint`; target `make actionlint`. `main.yml` (T19) gọi lại `ci.yml`.

- [ ] **Step 1: Test thất bại** — Run: `make actionlint`
Expected: `make: *** No rule to make target 'actionlint'`.

- [ ] **Step 2: `Makefile`** — thêm vào khối Helm (trước kind):

```make
.PHONY: actionlint
actionlint: tools-k8s ## Lint .github/workflows (actionlint; uses shellcheck when installed)
	$(ACTIONLINT)
```

- [ ] **Step 3: `.github/workflows/ci.yml`** — thêm sau job `secrets`:

```yaml
  images:
    name: image ${{ matrix.image }} (build, no push)
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        include:
          - {image: core, dockerfile: deploy/docker/go.Dockerfile, build-arg: SERVICE=core}
          - {image: public-api, dockerfile: deploy/docker/go.Dockerfile, build-arg: SERVICE=public-api}
          - {image: admin-api, dockerfile: deploy/docker/go.Dockerfile, build-arg: SERVICE=admin-api}
          - {image: mocks, dockerfile: deploy/docker/go.Dockerfile, build-arg: SERVICE=mocks}
          - {image: web-customer, dockerfile: deploy/docker/spa.Dockerfile, build-arg: APP=web-customer}
          - {image: web-admin, dockerfile: deploy/docker/spa.Dockerfile, build-arg: APP=web-admin}
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v4
      - name: Build (no push)
        uses: docker/build-push-action@v7
        with:
          context: .
          file: ${{ matrix.dockerfile }}
          build-args: |
            ${{ matrix.build-arg }}
            VERSION=sha-${{ github.sha }}
            COMMIT=${{ github.sha }}
          push: false
          tags: banking-go/${{ matrix.image }}:ci
          cache-from: type=gha,scope=${{ matrix.image }}
          cache-to: type=gha,mode=max,scope=${{ matrix.image }}

  deploy:
    name: deploy (helm lint + kubeconform 1.36 + helm-unittest, manifests)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version: '1.27.x'
          cache-dependency-path: tools/go.sum
      - run: make tools-k8s
      - run: make helm-lint helm-test
      - name: Vendored manifests match deploy/platform/vendor.lock
        run: scripts/vendor-manifests.sh --check
      - name: No plaintext Secret under deploy/ (spec criterion 6)
        run: scripts/check-no-plain-secrets.sh

  observability:
    name: observability (promtool, dashboards, alertmanager, runbooks, generated objects, collector)
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version: '1.27.x'
          cache-dependency-path: tools/go.sum
      - run: make tools-k8s
      - run: make alerts-test dashboards-test alertmanager-test runbooks-test obs-gen-check collector-validate

  actionlint:
    name: actionlint
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - uses: actions/setup-go@v7
        with:
          go-version: '1.27.x'
          cache-dependency-path: tools/go.sum
      - run: make actionlint
```

- [ ] **Step 4: Chạy local các bước của job**

Run: `make actionlint && make helm-lint helm-test && scripts/vendor-manifests.sh --check && scripts/check-no-plain-secrets.sh && make alerts-test dashboards-test alertmanager-test runbooks-test obs-gen-check collector-validate`
Expected: actionlint không in lỗi (exit 0); mọi target khác exit 0.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml Makefile
git commit -m "ci(platform): build images, lint/test charts and observability as code in ci.yml"
```

**Lệnh kiểm chứng:** `make actionlint` (+ job chạy thật trên PR sau khi owner tạo repo)

---

### T19: `main.yml` — build → Trivy → push → SBOM + cosign → bot bump `deploy/releases/kind.yaml`

**Owner trước:**
1. Tạo repo GitHub **private** `<GH_OWNER>/banking-go`, `git remote add origin git@github.com:<GH_OWNER>/banking-go.git`, push `main` (owner chạy `git push`, AI không).
2. Tạo GitHub App `bg-release-bot` (Repository permissions: Contents **Read and write**, Metadata Read), cài vào repo; lưu repo variable `BG_RELEASE_BOT_CLIENT_ID` và repo secret `BG_RELEASE_BOT_PRIVATE_KEY` (Settings → Secrets and variables → Actions).
3. Ruleset nhánh `main`: bắt buộc PR + check `ci` xanh; bypass list chỉ app `bg-release-bot` (D-22: bot chỉ push commit đổi `deploy/releases/*` — ràng buộc bằng `paths-ignore` + `scripts/release-bump.sh`, review ở PR).
4. Settings → Actions → General: Workflow permissions = Read; sau lần push đầu, đặt 6 package GHCR `banking-go/*` là private và cấp quyền repo.

**Files:**
- Create: `.github/workflows/main.yml`, `scripts/release-bump.sh`, `scripts/release-bump_test.sh`
- Modify: `.github/workflows/ci.yml` (bỏ trigger `push`, thêm `make scripts-test` vào job `deploy`), `Makefile` (`scripts-test`)

**Interfaces:**
- Consumes: `ci.yml` (`workflow_call`, T18), Dockerfile (T3, T4), `deploy/deployables.tsv` (T3), `bin/yq`.
- Produces: `scripts/release-bump.sh <env> <git_sha> <gh_owner> <digests_dir> <out_file>` — ghi `{release: sha-<7>, gitSha, <deployable>: {image: ghcr.io/<owner>/banking-go/<image>, digest}}`; artifact `digest-<image>` (file `<image>` chứa `sha256:…`); image `ghcr.io/<owner>/banking-go/<image>:sha-<7>` ký keyless + attestation `spdxjson`; commit bot `chore(release): kind <sha7>`; `concurrency: release-kind`; target `make scripts-test`.

- [ ] **Step 1: Viết test thất bại** — `scripts/release-bump_test.sh`

```bash
#!/usr/bin/env bash
# Tests scripts/release-bump.sh (bg-release-bot): file format from spec "Thiết kế", core-worker shares the core image.
set -euo pipefail
cd "$(dirname "$0")/.."
export PATH="$PWD/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
sha=0123456789abcdef0123456789abcdef01234567
mkdir "$TMP/d"; i=0
for img in core public-api admin-api mocks web-customer web-admin; do i=$((i + 1)); printf 'sha256:%064d\n' "$i" > "$TMP/d/$img"; done

scripts/release-bump.sh kind "$sha" acme "$TMP/d" "$TMP/kind.yaml"
[[ $(yq '.release' "$TMP/kind.yaml") == sha-0123456 ]] || fail "release"
[[ $(yq '.gitSha' "$TMP/kind.yaml") == "$sha" ]] || fail "gitSha"
[[ $(yq 'keys | length' "$TMP/kind.yaml") == 12 ]] || fail "want release + gitSha + 10 deployables"
[[ $(yq '."public-api".image' "$TMP/kind.yaml") == ghcr.io/acme/banking-go/public-api ]] || fail "public-api image"
[[ $(yq '."core-worker".image' "$TMP/kind.yaml") == ghcr.io/acme/banking-go/core ]] || fail "core-worker must use the core image"
[[ $(yq '."core-worker".digest' "$TMP/kind.yaml") == "$(cat "$TMP/d/core")" ]] || fail "core-worker digest = core digest"
[[ $(yq '."mock-otp".image' "$TMP/kind.yaml") == ghcr.io/acme/banking-go/mocks ]] || fail "mock-otp image"
[[ $(yq '."web-admin".digest' "$TMP/kind.yaml") == "$(cat "$TMP/d/web-admin")" ]] || fail "web-admin digest"

echo keep > "$TMP/out.yaml"; rm "$TMP/d/web-admin"
if scripts/release-bump.sh kind "$sha" acme "$TMP/d" "$TMP/out.yaml" 2>/dev/null; then fail "missing digest accepted"; fi
[[ $(cat "$TMP/out.yaml") == keep ]] || fail "output overwritten on error"
if scripts/release-bump.sh kind "$sha" Acme "$TMP/d" "$TMP/out.yaml" 2>/dev/null; then fail "uppercase owner accepted"; fi
if scripts/release-bump.sh kind abc acme "$TMP/d" "$TMP/out.yaml" 2>/dev/null; then fail "short sha accepted"; fi
echo "ok   release-bump"
```

`Makefile` — thêm vào khối Helm:
```make
.PHONY: scripts-test
scripts-test: tools-k8s ## Shell tests of the release/rollback helpers (scripts/*_test.sh)
	@for t in scripts/*_test.sh; do echo "== $$t"; $$t; done
```

Run: `chmod +x scripts/release-bump_test.sh && make scripts-test`
Expected: FAIL — `scripts/release-bump.sh: No such file or directory`.

- [ ] **Step 2: `scripts/release-bump.sh`**

```bash
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
```

Run: `chmod +x scripts/release-bump.sh && make scripts-test`
Expected: `ok   release-bump`.

- [ ] **Step 3: `.github/workflows/main.yml`**

```yaml
name: main

# Every commit on main: CI → build 6 images → Trivy → push GHCR → SBOM attest + keyless sign by digest →
# bg-release-bot writes the digests to deploy/releases/kind.yaml (spec §4, deployment.md § Pipeline).
on:
  push:
    branches: [main]
    paths-ignore:
      - 'deploy/releases/**'   # bot bumps and rollbacks must not rebuild (would loop)

permissions:
  contents: read

concurrency:
  group: release-kind
  cancel-in-progress: false

jobs:
  ci:
    uses: ./.github/workflows/ci.yml
    permissions:
      contents: read

  build:
    name: build ${{ matrix.image }}
    needs: ci
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      id-token: write   # cosign keyless (OIDC GitHub → Fulcio)
    strategy:
      fail-fast: true
      matrix:
        include:
          - {image: core, dockerfile: deploy/docker/go.Dockerfile, build-arg: SERVICE=core}
          - {image: public-api, dockerfile: deploy/docker/go.Dockerfile, build-arg: SERVICE=public-api}
          - {image: admin-api, dockerfile: deploy/docker/go.Dockerfile, build-arg: SERVICE=admin-api}
          - {image: mocks, dockerfile: deploy/docker/go.Dockerfile, build-arg: SERVICE=mocks}
          - {image: web-customer, dockerfile: deploy/docker/spa.Dockerfile, build-arg: APP=web-customer}
          - {image: web-admin, dockerfile: deploy/docker/spa.Dockerfile, build-arg: APP=web-admin}
    steps:
      - uses: actions/checkout@v7
      - name: Image name (GHCR needs a lowercase owner)
        run: |
          echo "IMAGE=ghcr.io/${GITHUB_REPOSITORY_OWNER,,}/banking-go/${{ matrix.image }}" >> "$GITHUB_ENV"
          echo "TAG=sha-${GITHUB_SHA::7}" >> "$GITHUB_ENV"
      - uses: docker/setup-buildx-action@v4
      - uses: docker/login-action@v4
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - name: Build (load locally for scanning)
        uses: docker/build-push-action@v7
        with:
          context: .
          file: ${{ matrix.dockerfile }}
          build-args: |
            ${{ matrix.build-arg }}
            VERSION=${{ env.TAG }}
            COMMIT=${{ github.sha }}
          load: true
          push: false
          tags: ${{ env.IMAGE }}:${{ env.TAG }}
          cache-from: type=gha,scope=${{ matrix.image }}
          cache-to: type=gha,mode=max,scope=${{ matrix.image }}
      - name: Trivy (fail on CRITICAL with a fix, NFR-S5)
        run: |
          docker run --rm -v /var/run/docker.sock:/var/run/docker.sock aquasec/trivy:0.75.0 \
            image --exit-code 1 --severity CRITICAL --ignore-unfixed --no-progress "$IMAGE:$TAG"
      - name: Push and resolve digest
        id: push
        run: |
          docker push "$IMAGE:$TAG"
          digest=$(docker buildx imagetools inspect "$IMAGE:$TAG" --format '{{json .Manifest}}' | jq -r .digest)
          [[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || { echo "bad digest: $digest"; exit 1; }
          echo "digest=$digest" >> "$GITHUB_OUTPUT"
          mkdir -p digest && echo "$digest" > "digest/${{ matrix.image }}"
      - name: SBOM (syft, SPDX JSON)
        uses: anchore/sbom-action@v0.24.3
        with:
          image: ${{ env.IMAGE }}@${{ steps.push.outputs.digest }}
          format: spdx-json
          output-file: sbom.spdx.json
          upload-artifact: false
          syft-version: v1.54.0
      - uses: sigstore/cosign-installer@v4.1.2
        with:
          cosign-release: v3.1.3
      - name: Sign + attest SBOM by digest (keyless, D-19)
        env:
          REF: ${{ env.IMAGE }}@${{ steps.push.outputs.digest }}
        run: |
          cosign sign --yes "$REF"
          cosign attest --yes --type spdxjson --predicate sbom.spdx.json "$REF"
      - uses: actions/upload-artifact@v7
        with:
          name: digest-${{ matrix.image }}
          path: digest/
          retention-days: 7

  bump:
    name: bump deploy/releases/kind.yaml (bg-release-bot)
    needs: build
    runs-on: ubuntu-latest
    steps:
      - id: app
        uses: actions/create-github-app-token@v3
        with:
          client-id: ${{ vars.BG_RELEASE_BOT_CLIENT_ID }}
          private-key: ${{ secrets.BG_RELEASE_BOT_PRIVATE_KEY }}
          permission-contents: write
      - uses: actions/checkout@v7
        with:
          ref: main
          token: ${{ steps.app.outputs.token }}
      - uses: actions/download-artifact@v8
        with:
          pattern: digest-*
          path: digests
          merge-multiple: true
      - name: Write, commit and push the digests
        env:
          GH_TOKEN: ${{ steps.app.outputs.token }}
          SLUG: ${{ steps.app.outputs.app-slug }}
          OWNER: ${{ github.repository_owner }}
          SHA: ${{ github.sha }}
        run: |
          uid=$(gh api "/users/${SLUG}[bot]" --jq .id)
          git config user.name "${SLUG}[bot]"
          git config user.email "${uid}+${SLUG}[bot]@users.noreply.github.com"
          for attempt in 1 2 3; do
            git fetch origin main && git reset --hard origin/main
            scripts/release-bump.sh kind "$SHA" "${OWNER,,}" digests deploy/releases/kind.yaml
            git add deploy/releases/kind.yaml
            if git diff --cached --quiet; then echo "no digest change"; exit 0; fi
            git commit -m "chore(release): kind ${SHA::7}"
            if git push origin HEAD:main; then exit 0; fi
            echo "push rejected (attempt $attempt), retrying"; sleep 5
          done
          exit 1
```

- [ ] **Step 4: `ci.yml`** — xóa 2 dòng `push:` / `branches: [main]` trong khối `on:` (main.yml gọi ci.yml qua `workflow_call`, tránh chạy 2 lần), và thêm vào cuối job `deploy`:

```yaml
      - name: Release/rollback helper tests
        run: make scripts-test
```

- [ ] **Step 5: Lint workflow**

Run: `make actionlint && make scripts-test`
Expected: exit 0, `ok   release-bump`.

- [ ] **Step 6: Commit**

```bash
git add .github/workflows/main.yml .github/workflows/ci.yml scripts/release-bump.sh scripts/release-bump_test.sh Makefile
git commit -m "ci(platform): main.yml builds, scans, signs and pushes images, bot bumps kind digests"
```

- [ ] **Step 7: Chạy thật (sau khi owner push commit này)**

Run (owner): `bin/gh run watch "$(bin/gh run list --workflow main.yml -L1 --json databaseId -q '.[0].databaseId')" --exit-status`
Expected: job `ci`, 6 job `build …`, `bump` xanh; `git pull && git log --oneline -1 -- deploy/releases/kind.yaml` → `chore(release): kind <sha7>` của `bg-release-bot[bot]`.

Run (owner, sau `docker login ghcr.io` bằng PAT `read:packages` vì package private):
```bash
OWNER=<gh_owner>
ID="^https://github.com/$OWNER/banking-go/.github/workflows/main.yml@refs/heads/main\$"
ISSUER=https://token.actions.githubusercontent.com
for img in core public-api admin-api mocks web-customer web-admin; do
  key=$img; [[ $img == mocks ]] && key=mock-napas          # releases file is keyed by deployable
  ref="ghcr.io/$OWNER/banking-go/$img@$(bin/yq ".\"$key\".digest" deploy/releases/kind.yaml)"
  bin/cosign verify --certificate-identity-regexp "$ID" --certificate-oidc-issuer "$ISSUER" "$ref" >/dev/null && echo "verify ok $img"
  bin/cosign verify-attestation --type spdxjson --certificate-identity-regexp "$ID" --certificate-oidc-issuer "$ISSUER" "$ref" >/dev/null \
    && echo "attestation ok $img"
done
```
Expected: `verify ok <img>` và `attestation ok <img>` cho 6 image.

**Lệnh kiểm chứng:** `make actionlint scripts-test` (local) · `gh run watch … --exit-status` + `cosign verify` (sau owner push)

---

### T20: `rollback.yml` (env=kind, revert_sha)

**Owner trước:** như T19 (repo, App `bg-release-bot`, ruleset). Workflow do **owner** kích hoạt (`.claude/settings.json` chặn AI chạy `gh workflow run rollback*`).

**Files:**
- Create: `.github/workflows/rollback.yml`, `scripts/rollback-check.sh`, `scripts/rollback-check_test.sh`

**Interfaces:**
- Consumes: App token + `deploy/releases/kind.yaml` do bot ghi (T19), `concurrency` group `release-kind` (T19), `make scripts-test` (T19).
- Produces: `workflow_dispatch` input `env` (choice: `kind`), `revert_sha` (string); `scripts/rollback-check.sh <sha> <env>` (commit phải nằm trên `main` và chỉ đổi `deploy/releases/<env>.yaml`); commit bot `Revert "chore(release): kind <sha7>"`.

- [ ] **Step 1: Viết test thất bại** — `scripts/rollback-check_test.sh`

```bash
#!/usr/bin/env bash
# Tests scripts/rollback-check.sh against a throwaway git repo.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
fail() { echo "FAIL: $*" >&2; exit 1; }
repo=$(mktemp -d); trap 'rm -rf "$repo"' EXIT
g() { git -C "$repo" "$@"; }
g init -q -b main && g config user.email t@example.invalid && g config user.name test
mkdir -p "$repo/deploy/releases"
echo a > "$repo/README"; g add -A; g commit -qm init; A=$(g rev-parse HEAD)
echo "digest: 1" > "$repo/deploy/releases/kind.yaml"; g add -A; g commit -qm "chore(release): kind 1"; B=$(g rev-parse HEAD)
echo b >> "$repo/README"; echo "digest: 2" > "$repo/deploy/releases/kind.yaml"; g add -A; g commit -qm mixed; C=$(g rev-parse HEAD)
check() { (cd "$repo" && "$ROOT/scripts/rollback-check.sh" "$@") >/dev/null 2>&1; }
check "$B" kind || fail "digest-only bump must be accepted"
if check "$C" kind; then fail "commit touching other files accepted"; fi
if check "$A" kind; then fail "commit without deploy/releases/kind.yaml accepted"; fi
if check "$B" prod; then fail "env prod accepted in platform v1"; fi
if check deadbeef kind; then fail "unknown sha accepted"; fi
if check 'B;rm' kind; then fail "non-hex sha accepted"; fi
echo "ok   rollback-check"
```

Run: `chmod +x scripts/rollback-check_test.sh && make scripts-test`
Expected: `ok   release-bump`, rồi `FAIL: digest-only bump must be accepted` (script chưa có).

- [ ] **Step 2: `scripts/rollback-check.sh`**

```bash
#!/usr/bin/env bash
# rollback.yml guard (deployment.md § Rollback → App, D-22): <sha> must be on the current branch and change only
# deploy/releases/<env>.yaml, so bg-release-bot may push its revert directly. Config rollbacks go through a PR (v2+).
#   scripts/rollback-check.sh <sha> <env>
set -euo pipefail
die() { echo "rollback-check: $*" >&2; exit 1; }
sha=${1:-}; env=${2:-}
[[ $env == kind ]] || die "env '$env' is not supported in platform v1 (kind only)"
[[ $sha =~ ^[0-9a-f]{7,40}$ ]] || die "revert_sha must be a hex commit sha"
git cat-file -e "$sha^{commit}" 2>/dev/null || die "unknown commit $sha"
git merge-base --is-ancestor "$sha" HEAD || die "$sha is not on this branch"
files=$(git diff-tree --no-commit-id --name-only -r "$sha")
[[ $files == "deploy/releases/$env.yaml" ]] || die "$sha must change only deploy/releases/$env.yaml, changes: $(echo $files)"
echo "ok: $sha only changes deploy/releases/$env.yaml"
```

Run: `chmod +x scripts/rollback-check.sh && make scripts-test`
Expected: `ok   release-bump`, `ok   rollback-check`.

- [ ] **Step 3: `.github/workflows/rollback.yml`**

```yaml
name: rollback

# App rollback = git revert of a digest bump (deployment.md § Rollback → App). v1: env kind only.
# Find the bump: git log --oneline -- deploy/releases/kind.yaml
on:
  workflow_dispatch:
    inputs:
      env:
        description: Environment (platform v1 — kind only)
        type: choice
        options: [kind]
        required: true
      revert_sha:
        description: SHA of the bg-release-bot commit to revert
        type: string
        required: true

permissions:
  contents: read

concurrency:
  group: release-${{ inputs.env }}   # same group as main.yml (release-kind): never races a bump
  cancel-in-progress: false

jobs:
  revert:
    name: revert ${{ inputs.revert_sha }} on ${{ inputs.env }}
    runs-on: ubuntu-latest
    steps:
      - id: app
        uses: actions/create-github-app-token@v3
        with:
          client-id: ${{ vars.BG_RELEASE_BOT_CLIENT_ID }}
          private-key: ${{ secrets.BG_RELEASE_BOT_PRIVATE_KEY }}
          permission-contents: write
      - uses: actions/checkout@v7
        with:
          ref: main
          fetch-depth: 0
          token: ${{ steps.app.outputs.token }}
      - name: Only digest bumps can be reverted directly
        env:
          REVERT_SHA: ${{ inputs.revert_sha }}
          ENV_NAME: ${{ inputs.env }}
        run: scripts/rollback-check.sh "$REVERT_SHA" "$ENV_NAME"
      - name: Revert and push (bg-release-bot, D-22)
        env:
          GH_TOKEN: ${{ steps.app.outputs.token }}
          SLUG: ${{ steps.app.outputs.app-slug }}
          REVERT_SHA: ${{ inputs.revert_sha }}
          ENV_NAME: ${{ inputs.env }}
        run: |
          uid=$(gh api "/users/${SLUG}[bot]" --jq .id)
          git config user.name "${SLUG}[bot]"
          git config user.email "${uid}+${SLUG}[bot]@users.noreply.github.com"
          git revert --no-edit "$REVERT_SHA"
          git push origin HEAD:main
          {
            echo "Reverted \`$REVERT_SHA\` on \`$ENV_NAME\`: Argo CD syncs the previous digests."
            echo "Then on the dev machine: \`make kind-smoke\` (digest check) and \`make kind-watch\`."
          } >> "$GITHUB_STEP_SUMMARY"
```

- [ ] **Step 4: Lint + test**

Run: `make actionlint && make scripts-test`
Expected: exit 0; `ok   rollback-check`.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/rollback.yml scripts/rollback-check.sh scripts/rollback-check_test.sh
git commit -m "ci(platform): rollback.yml reverts a kind digest bump through bg-release-bot"
```

**Lệnh kiểm chứng:** `make actionlint scripts-test` (chạy thật ở nghiệm thu T21, tiêu chí 4)

---

### T21: Argo CD app-of-apps `deploy/argocd/kind/` + bootstrap GitOps + nghiệm thu tiêu chí 1–6

**Owner trước:**
1. T19 đã có ít nhất một lần `main.yml` xanh → `deploy/releases/kind.yaml` tồn tại trên `main`.
2. Tạo deploy key **chỉ đọc**: `ssh-keygen -t ed25519 -N '' -C argocd-kind -f ~/.config/banking-go/argocd-deploy-key && chmod 600 ~/.config/banking-go/argocd-deploy-key`; thêm `argocd-deploy-key.pub` vào repo (Settings → Deploy keys, không tick write).
3. Tạo PAT classic scope `read:packages` (GHCR chưa hỗ trợ fine-grained cho pull), ghi `GHCR_USER=<login>` và `GHCR_PAT=<token>` vào `deploy/secrets/kind.env`; chạy `make seal` rồi commit `deploy/secrets/kind/banking-ghcr-pull.sealed.yaml` qua PR (bước 5 của task).
4. Telegram đã cấu hình (T16).

**Files:**
- Create: `deploy/argocd/kind/Chart.yaml`, `deploy/argocd/kind/templates/addons.yaml`, `deploy/argocd/kind/templates/apps.yaml`, `deploy/argocd/kind/tests/app-of-apps_test.yaml`, `deploy/kind/root.yaml`, `deploy/kind/wait-argocd.sh`
- Modify: `deploy/argocd/kind/values.yaml` (addon `argocd` wave -25, danh sách `apps`), `deploy/kind/bootstrap.sh`, `deploy/platform/argocd/values-kind.yaml` (health của Application), `scripts/seal-kind.sh` (`ghcr-pull`), `deploy/secrets/kind.env.example`, `Makefile` (`kind-up` truyền `GH_OWNER`, `helm-lint`/`helm-test` gồm chart app-of-apps), `CLAUDE.md` (Gotchas)

**Interfaces:**
- Consumes: catalog `addons[]` (T9–T14), chart `deploy/helm/<d>` (T7), `deploy/releases/kind.yaml` (T19), `sealed-key.sh` (T8), smoke/watch (T12–T17), rollback (T20).
- Produces: Application `bg-kind-root` (ns `argocd`, path `deploy/argocd/kind`, Helm parameter `repoURL`, `ghOwner`), một Application cho mỗi addon (annotation `argocd.argoproj.io/sync-wave` = `wave`) và mỗi app (wave `0`, multi-source: `deploy/helm/<d>` + `values-kind.yaml` + `$values/deploy/releases/kind.yaml`, parameter `global.ghOwner`, `global.imagePullSecrets[0]=ghcr-pull`); Secret repo `argocd/repo-banking-go` (từ deploy key, tạo bởi bootstrap); `deploy/kind/wait-argocd.sh` (env `WAIT_TIMEOUT`, mặc định 1800 s); `make kind-up GH_OWNER=<owner>` = GitOps đầy đủ; không có `GH_OWNER` → chỉ cluster + Argo CD (đường offline `kind-platform`/`kind-apps` giữ nguyên cho máy chưa có GitHub).

- [ ] **Step 1: Viết test thất bại**

`deploy/argocd/kind/tests/app-of-apps_test.yaml`:
```yaml
suite: kind app-of-apps
templates:
  - templates/addons.yaml
  - templates/apps.yaml
set:
  repoURL: git@github.com:acme/banking-go.git
  ghOwner: acme
tests:
  - it: renders one Application per deployable, releases file as the last values file
    template: templates/apps.yaml
    documentSelector: {path: metadata.name, value: public-api}
    asserts:
      - equal: {path: "metadata.annotations[\"argocd.argoproj.io/sync-wave\"]", value: "0"}
      - equal: {path: spec.destination.namespace, value: banking}
      - equal: {path: spec.sources[0].path, value: deploy/helm/public-api}
      - equal: {path: spec.sources[0].helm.valueFiles, value: [values-kind.yaml, $values/deploy/releases/kind.yaml]}
      - contains: {path: spec.sources[0].helm.parameters, content: {name: global.ghOwner, value: acme}}
      - contains: {path: "spec.sources[0].helm.parameters", content: {name: "global.imagePullSecrets[0]", value: ghcr-pull}}
      - equal: {path: spec.sources[1], value: {repoURL: "git@github.com:acme/banking-go.git", targetRevision: main, ref: values}}
      - equal: {path: spec.syncPolicy.automated, value: {prune: true, selfHeal: true}}
  - it: renders the 10 deployables
    template: templates/apps.yaml
    asserts:
      - hasDocuments: {count: 10}
  - it: installs chart add-ons from their Helm repo with values from Git, in their sync wave
    template: templates/addons.yaml
    documentSelector: {path: metadata.name, value: cert-manager}
    asserts:
      - equal: {path: "metadata.annotations[\"argocd.argoproj.io/sync-wave\"]", value: "-20"}
      - equal:
          path: spec.sources[0]
          value:
            repoURL: https://charts.jetstack.io
            chart: cert-manager
            targetRevision: v1.21.2
            helm: {releaseName: cert-manager, valueFiles: [$values/deploy/platform/cert-manager/values-kind.yaml]}
  - it: applies directory add-ons recursively from Git with server-side apply
    template: templates/addons.yaml
    documentSelector: {path: metadata.name, value: gateway-api-crds}
    asserts:
      - equal:
          path: spec.source
          value: {repoURL: "git@github.com:acme/banking-go.git", targetRevision: main, path: deploy/platform/gateway-api, directory: {recurse: true}}
      - contains: {path: spec.syncPolicy.syncOptions, content: ServerSideApply=true}
  - it: Argo CD manages itself before the other add-ons
    template: templates/addons.yaml
    documentSelector: {path: metadata.name, value: argocd}
    asserts:
      - equal: {path: "metadata.annotations[\"argocd.argoproj.io/sync-wave\"]", value: "-25"}
  - it: requires repoURL
    template: templates/apps.yaml
    set:
      repoURL: ""
    asserts:
      - failedTemplate: {errorPattern: "repoURL is required"}
```

`Makefile` — trong `helm-test`, đổi danh sách vòng lặp thành `deploy/helm/_libtest deploy/argocd/kind $(HELM_CHARTS)`; trong `helm-lint`, thêm cuối recipe:
```make
	@echo "== deploy/argocd/kind (app-of-apps)"
	$(HELM) lint --strict deploy/argocd/kind --set repoURL=git@github.com:lint-owner/banking-go.git --set ghOwner=lint-owner
	$(HELM) template bg-kind-root deploy/argocd/kind -n argocd --set repoURL=git@github.com:lint-owner/banking-go.git --set ghOwner=lint-owner \
		| $(KUBECONFORM) $(KUBECONFORM_FLAGS)
```

Run: `make helm-test`
Expected: FAIL — `Chart.yaml file is missing` trong `deploy/argocd/kind`.

- [ ] **Step 2: Chart app-of-apps**

`deploy/argocd/kind/Chart.yaml`:
```yaml
apiVersion: v2
name: bg-kind
description: App-of-apps of the kind env (ADR 0011). Values = the add-on/app catalog in values.yaml.
type: application
version: 0.1.0
```

`deploy/argocd/kind/templates/addons.yaml`:
```yaml
{{- $repo := required "repoURL is required" .Values.repoURL }}
{{- range .Values.addons }}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ .name }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: {{ .wave | quote }}
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: {{ .namespace | default "default" }}
  {{- if .chart }}
  sources:
    - repoURL: {{ .chart.repo }}
      chart: {{ .chart.name }}
      targetRevision: {{ .chart.version }}
      helm:
        releaseName: {{ .releaseName | default .name }}
        {{- with .values }}
        valueFiles:
          {{- range . }}
          - $values/{{ . }}
          {{- end }}
        {{- end }}
    - repoURL: {{ $repo }}
      targetRevision: {{ $.Values.targetRevision }}
      ref: values
  {{- else }}
  source:
    repoURL: {{ $repo }}
    targetRevision: {{ $.Values.targetRevision }}
    path: {{ .path }}
    directory:
      recurse: true
  {{- end }}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
    retry:
      limit: 10
      backoff: {duration: 10s, factor: 2, maxDuration: 3m}
{{- end }}
```

`deploy/argocd/kind/templates/apps.yaml`:
```yaml
{{- $repo := required "repoURL is required" .Values.repoURL }}
{{- $owner := required "ghOwner is required" .Values.ghOwner }}
{{- range .Values.apps }}
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: {{ . }}
  namespace: argocd
  annotations:
    argocd.argoproj.io/sync-wave: "0"
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: banking
  sources:
    - repoURL: {{ $repo }}
      targetRevision: {{ $.Values.targetRevision }}
      path: deploy/helm/{{ . }}
      helm:
        releaseName: {{ . }}
        valueFiles:
          - values-kind.yaml
          - $values/deploy/releases/kind.yaml
        parameters:
          - name: global.ghOwner
            value: {{ $owner }}
          - name: global.imagePullSecrets[0]
            value: ghcr-pull
    - repoURL: {{ $repo }}
      targetRevision: {{ $.Values.targetRevision }}
      ref: values
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
    retry:
      limit: 5
      backoff: {duration: 10s, factor: 2, maxDuration: 3m}
{{- end }}
```

`deploy/argocd/kind/values.yaml` — thêm addon ngay sau `prometheus-operator-crds`:
```yaml
  - name: argocd
    wave: -25
    namespace: argocd
    chart: {repo: https://argoproj.github.io/argo-helm, name: argo-cd, version: 10.9.6}
    values: [deploy/platform/argocd/values-kind.yaml]
```
và thêm cuối file:
```yaml
# Wave 0: one Application per deployable (AD-1); must match deploy/deployables.tsv.
apps: [core, core-worker, public-api, admin-api, mock-napas, mock-ekyc, mock-otp, mock-gateway, web-customer, web-admin]
```

`deploy/platform/argocd/values-kind.yaml` — trong `configs.cm` thêm (khôi phục health của Application để sync-wave của app-of-apps chờ add-on Healthy):
```yaml
    resource.customizations.health.argoproj.io_Application: |
      hs = {}
      hs.status = "Progressing"
      hs.message = ""
      if obj.status ~= nil and obj.status.health ~= nil then
        hs.status = obj.status.health.status
        if obj.status.health.message ~= nil then
          hs.message = obj.status.health.message
        end
      end
      return hs
```

Run: `make helm-lint helm-test`
Expected: app-of-apps lint `1 chart(s) linted, 0 chart(s) failed`, kubeconform `Invalid: 0`; suite `kind app-of-apps` 6 test pass.

- [ ] **Step 3: Root app + chờ đồng bộ**

`deploy/kind/root.yaml`:
```yaml
# Root Application of the kind env (app-of-apps). deploy/kind/bootstrap.sh replaces ${GH_OWNER} and applies it.
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bg-kind-root
  namespace: argocd
spec:
  project: default
  destination:
    server: https://kubernetes.default.svc
    namespace: argocd
  source:
    repoURL: git@github.com:${GH_OWNER}/banking-go.git
    targetRevision: main
    path: deploy/argocd/kind
    helm:
      parameters:
        - name: repoURL
          value: git@github.com:${GH_OWNER}/banking-go.git
        - name: ghOwner
          value: ${GH_OWNER}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

`deploy/kind/wait-argocd.sh`:
```bash
#!/usr/bin/env bash
# Waits until every Application of the kind app-of-apps (root + add-ons + apps) is Synced and Healthy (spec criterion 1).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
require_kind_context
CATALOG="$ROOT/deploy/argocd/kind/values.yaml"
want=$(( $(yq '.addons | length' "$CATALOG") + $(yq '.apps | length' "$CATALOG") + 1 ))
deadline=$(( $(date +%s) + ${WAIT_TIMEOUT:-1800} ))
while :; do
  apps=$(kubectl -n argocd get applications.argoproj.io -o json)
  total=$(jq '.items | length' <<<"$apps")
  bad=$(jq -r '[.items[] | select(.status.sync.status != "Synced" or .status.health.status != "Healthy")
               | "\(.metadata.name)=\(.status.sync.status // "?")/\(.status.health.status // "?")"] | join(" ")' <<<"$apps")
  if [[ $total -ge $want && -z $bad ]]; then echo "ok   $total Argo CD applications Synced/Healthy"; exit 0; fi
  (( $(date +%s) < deadline )) || { echo "FAIL: $total/$want applications; not ready: $bad" >&2; exit 1; }
  echo "waiting: $total/$want applications; not ready: ${bad:-none}"
  sleep 15
done
```

- [ ] **Step 4: `deploy/kind/bootstrap.sh`** — thay toàn bộ file:

```bash
#!/usr/bin/env bash
# Idempotent bootstrap of the kind env (ADR 0011, spec §7):
#   1. create kind cluster banking-go (k8s 1.36.4, 1 CP + 2 workers, host 80/443) if missing
#   2. restore the Sealed Secrets controller key from ~/.config/banking-go (before any controller starts)
#   3. install/upgrade Argo CD (chart pinned; afterwards Argo CD manages itself, wave -25)
#   4. with GH_OWNER: repo credentials from the read-only deploy key, root app-of-apps, wait Synced/Healthy, back up the key
#      without GH_OWNER: stop after Argo CD (offline path: make kind-platform kind-apps)
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export PATH="$ROOT/bin:$PATH"
. "$ROOT/scripts/lib/kind.sh"
ARGOCD_CHART_VERSION=10.9.6
CONFIG_DIR=${BG_CONFIG_DIR:-$HOME/.config/banking-go}
log() { printf '[bootstrap] %s\n' "$*"; }
die() { printf '[bootstrap] ERROR: %s\n' "$*" >&2; exit 1; }

if kind get clusters 2>/dev/null | grep -qx "$KIND_CLUSTER"; then
  log "cluster $KIND_CLUSTER exists"
else
  log "creating cluster $KIND_CLUSTER"
  kind create cluster --config "$ROOT/deploy/kind/kind-config.yaml" --wait 180s
fi
kubectl config use-context "$KIND_CONTEXT" >/dev/null
kubectl wait --for=condition=Ready nodes --all --timeout=180s >/dev/null

"$ROOT/deploy/kind/sealed-key.sh" restore

log "installing Argo CD (chart argo-cd $ARGOCD_CHART_VERSION)"
helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version "$ARGOCD_CHART_VERSION" \
  --namespace argocd --create-namespace -f "$ROOT/deploy/platform/argocd/values-kind.yaml" --wait --timeout 10m

if [[ -z ${GH_OWNER:-} ]]; then
  log "GH_OWNER not set: Argo CD only (offline path: make kind-platform kind-apps)"
  exit 0
fi
owner=${GH_OWNER,,}
[[ $owner =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die "GH_OWNER '$GH_OWNER' is not a GitHub login"
key="$CONFIG_DIR/argocd-deploy-key"
[[ -s $key ]] || die "missing read-only deploy key $key (owner step of T21)"
repo="git@github.com:$owner/banking-go.git"

log "repository credentials for $repo (bootstrap secret, never committed)"
kubectl -n argocd create secret generic repo-banking-go \
  --from-literal=type=git --from-literal=url="$repo" --from-file=sshPrivateKey="$key" --dry-run=client -o yaml \
  | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
  | kubectl apply -f - >/dev/null

log "applying root app-of-apps bg-kind-root"
sed "s|\${GH_OWNER}|$owner|g" "$ROOT/deploy/kind/root.yaml" | kubectl apply -f - >/dev/null
"$ROOT/deploy/kind/wait-argocd.sh"
"$ROOT/deploy/kind/sealed-key.sh" backup
log "done: GitOps from $repo"
```

`Makefile` — đổi recipe `kind-up` thành:
```make
kind-up: tools-k8s ## Create/refresh kind (idempotent): k8s 1.36, Sealed Secrets key, Argo CD; GH_OWNER=<owner> → full GitOps
	GH_OWNER=$(GH_OWNER) deploy/kind/bootstrap.sh
	deploy/kind/check-cluster.sh
```

- [ ] **Step 5: Pull secret GHCR** — `scripts/seal-kind.sh`, thêm trước dòng cuối `"$ROOT/scripts/check-no-plain-secrets.sh"`:

```bash
# banking: GHCR pull secret (T21, owner PAT read:packages); skipped until GHCR_USER/GHCR_PAT are set.
if [[ -n ${GHCR_USER:-} && -n ${GHCR_PAT:-} ]]; then
  kubectl create secret docker-registry ghcr-pull --namespace banking --docker-server=ghcr.io \
    --docker-username="$GHCR_USER" --docker-password="$GHCR_PAT" --dry-run=client -o yaml \
    | kubeseal --cert "$CERT" --format yaml > "$OUT/banking-ghcr-pull.sealed.yaml"
  echo "sealed banking/ghcr-pull"
else
  echo "skip banking/ghcr-pull: set GHCR_USER and GHCR_PAT in $ENV_FILE"
fi
```
`deploy/secrets/kind.env.example` — thêm:
```dotenv
# GHCR pull (T21, owner): GitHub login + classic PAT with read:packages only.
GHCR_USER=
GHCR_PAT=
```
`CLAUDE.md` — thêm vào `## Gotchas`:
```markdown
- kind GitOps: `make kind-up GH_OWNER=<owner>` cần deploy key chỉ đọc ở ~/.config/banking-go/argocd-deploy-key; `deploy/releases/kind.yaml` chỉ bot `bg-release-bot` ghi; rollback chỉ owner chạy `gh workflow run rollback.yml`.
```

Run: `chmod +x deploy/kind/wait-argocd.sh && make seal && make helm-lint helm-test && make actionlint`
Expected: `sealed banking/ghcr-pull`; lint/test exit 0.

- [ ] **Step 6: Commit (owner mở PR, merge vào `main`)**

```bash
git add deploy/argocd/kind deploy/kind deploy/platform/argocd/values-kind.yaml scripts/seal-kind.sh deploy/secrets Makefile CLAUDE.md
git commit -m "feat(platform): argo cd app-of-apps for kind with multi-source release digests"
```

- [ ] **Step 7: Nghiệm thu tiêu chí 1–6 của spec** (sau khi commit lên `main` và `main.yml` xanh)

| # | Lệnh | Kỳ vọng |
|---|---|---|
| 1 | `make kind-down && make kind-up GH_OWNER=<owner>` rồi `bin/kubectl -n argocd get applications` | exit 0; `ok   N Argo CD applications Synced/Healthy`; mọi dòng `Synced   Healthy` |
| 2 | Owner push 1 commit lên `main`; `bin/gh run watch "$(bin/gh run list --workflow main.yml -L1 --json databaseId -q '.[0].databaseId')" --exit-status`; lệnh `cosign verify` + `cosign verify-attestation --type spdxjson` ở T19 Step 7 cho 6 image; `git pull && git log --oneline -1 -- deploy/releases/kind.yaml` | run xanh; 6× `verify ok`, 6× `attestation ok`; commit `chore(release): kind <sha7>` của `bg-release-bot[bot]` |
| 3 | `deploy/kind/wait-argocd.sh && make kind-smoke` | Job `*-migrate` `Completed`; 4 host 200 (`{"status":"ok"}` / HTML); 10 dòng `<deployable> runs sha256:…` khớp `deploy/releases/kind.yaml` |
| 4 | `prev=$(git log -2 --format=%H -- deploy/releases/kind.yaml \| tail -1)`; owner: `bin/gh workflow run rollback.yml -f env=kind -f revert_sha=$(git log -1 --format=%H -- deploy/releases/kind.yaml)`; sau khi run xanh: `git pull && deploy/kind/wait-argocd.sh && make kind-smoke && git diff --quiet $prev HEAD -- deploy/releases/kind.yaml` | rollback run xanh; kind-smoke pass với digest = bản trước; `git diff` không khác |
| 5 | `make kind-smoke` (mục 5–7) và `make runbooks-test` | trace `public-api` trong Jaeger `/api/v3/traces`; RED rate > 0; dashboard `bg-service-overview` có trong Grafana; `Alertmanager delivered N telegram notification(s), 0 failed`; 7 runbook `ok` |
| 6 | `make helm-lint helm-test && make alerts-test && make actionlint && scripts/check-no-plain-secrets.sh && docker run --rm -v "$PWD:/repo" -w /repo -e GIT_CONFIG_COUNT=1 -e GIT_CONFIG_KEY_0=safe.directory -e GIT_CONFIG_VALUE_0='*' zricethezav/gitleaks:v8.30.0 git /repo --redact --exit-code 1` | tất cả exit 0; gitleaks `no leaks found`; `ok   no plaintext Secret under deploy/` |

Ghi kết quả từng dòng (lệnh + output rút gọn) làm evidence của T21 trong `tasks.json`.

**Lệnh kiểm chứng:** `make kind-down && make kind-up GH_OWNER=<owner> && make kind-smoke` + bảng nghiệm thu ở Step 7

---

## Sprint

| Sprint | Goal | Task |
|---|---|---|
| S1 | Image + chart chạy trên kind (cài bằng helm trực tiếp, chưa cần GitHub): 6 image, lib + 10 chart, cluster kind 1.36 + add-on + data, 10 deployable Ready, smoke qua Traefik | T1, T2, T3, T4, T5, T6, T7, T8, T9, T10, T11, T12 (12) |
| S2 | Observability as code trên kind: trace + RED + alert (promtool) + dashboard + Telegram + runbook + watch | T13, T14, T15, T16, T17 (5) |
| S3 | GitOps + pipeline thật (cần repo GitHub; owner làm các bước tay trước): CI image/chart/obs, main.yml ký + bump digest, rollback.yml, app-of-apps, nghiệm thu tiêu chí 1–6 | T18, T19, T20, T21 (4) |

Tổng: 21 task (S1 12, S2 5, S3 4) — mỗi sprint ≤ 15, 3 sprint.

## Thứ tự phụ thuộc

- T1: —
- T2: —
- T3: T2
- T4: T3
- T5: T1
- T6: T5
- T7: T6, T4
- T8: T1
- T9: T8
- T10: T9
- T11: T7, T10
- T12: T11
- T13: T12
- T14: T13
- T15: T14
- T16: T14, T10
- T17: T14
- T18: T7, T15, T16, T17
- T19: T18
- T20: T19
- T21: T19, T20, T12, T16

Song song được trong S1: nhánh image (T2 → T3 → T4), nhánh chart (T5 → T6 → T7), nhánh cluster (T8 → T9 → T10) gặp nhau ở T11. Theo luật WIP = 1 vẫn làm tuần tự theo `scripts/sprint.sh next`.

## Self-review

**1. Spec coverage**

| Spec | Task |
|---|---|
| §1 Image (6 image / 10 deployable, distroless nonroot, `CGO_ENABLED=0`, `-trimpath`, ldflags version/commit; SPA nginx-unprivileged + `config.js` ConfigMap) | T3, T4 (mount ConfigMap: T5 `configFiles`, T7 values-kind) |
| §2 `migrate up` (goose embed, migrator DSN, no-op khi rỗng) | T2 (+ image: T3 `image-smoke`) |
| §3 CI (build 6 image không push + cache GHA, helm lint + kubeconform 1.36 + CRD catalog + helm-unittest, promtool check/test, actionlint) | T18 (target từ T7, T14) |
| §4 `main.yml` (ci → build matrix `sha-<short>` → Trivy CRITICAL có fix → syft SPDX + attest → sign keyless digest → GHCR → bot bump, `concurrency: release-kind`) | T19 |
| §5 `rollback.yml` (env ∈ {kind}, revert_sha, bot revert + push) | T20 |
| §6 Helm lib (Deployment, Service, ServiceAccount, ConfigMap, HTTPRoute, PDB, PreSync Job, Certificate mTLS) + 10 chart mỏng + values-kind + digest từ releases qua multi-source | T5, T6, T7, T21 |
| §7 kind-config, bootstrap idempotent, app-of-apps + sync-wave; Makefile `kind-up/down/ca/smoke/watch`, `seal`, `helm-lint`, `helm-test` | T8, T9 (`kind-ca`), T10 (`seal`), T12, T17, T7, T21 |
| §8 Add-on (Gateway API v1.6, cert-manager 2 CA, sealed-secrets, Traefik, CNPG + `Cluster pg` 3 DB 6 role, RabbitMQ op + 1 node + topology, SeaweedFS + bucket, kube-prometheus-stack Grafana 12.4, Jaeger v2 in-memory, Collector `deploy/collector/kind.yaml`) | T9, T10, T13 |
| §9 Secrets (sealed: role DB, user RabbitMQ, S3, GHCR pull, Telegram; backup/khôi phục key ở `~/.config/banking-go/`) | T8, T9, T10, T16, T21 |
| §10 Alert v1 + promtool test, dashboard `service-overview` + `platform` uid cố định, runbook 5 alert, Alertmanager → Telegram critical + Watchdog | T14, T15, T17, T16 |
| Vận hành: `OTEL_EXPORTER_OTLP_ENDPOINT`, `BG_<SVC>_*` từ Secret + `.env.example`, migration PreSync chạy lại an toàn, redaction PII, rollback, việc owner | T13, T10/T2, T6/T11, T13, T20, T19/T21 (Owner trước) |
| Tiêu chí 1–6 | T21 Step 7 (từng tiêu chí một lệnh) |

Không có yêu cầu spec nào thiếu task. Lệch nhỏ có chủ đích: (a) thêm 2 runbook (`pod-crashloop`, `argocd-app-degraded`) để alert crashloop/Argo CD không có `runbook_url` treo — spec yêu cầu ≥ 5; (b) `runbook_url` là đường dẫn trong repo vì `GH_OWNER` chưa chốt; (c) thứ tự trong `main.yml` là scan → push → SBOM/attest → sign (ký keyless cần image đã ở registry; deployment.md cũng đặt push trước ký); (d) wave kind: -30 CRD/namespace, -25 Argo CD, -20 operator/ingress/secret controller, -19 RabbitMQ ops, -18 secret + issuer, -15/-14 data, -10/-9 observability, 0 app — khung theo deployment.md, số cụ thể của kind; (e) thêm key values ngoài interface spec, chỉ cho nội bộ lib: `image.tag`, `image.pullPolicy`, `global.*`, `configFiles`, `secretsRevision`, `mtls.issuer`.

**2. Placeholder scan** — không có "TBD/TODO/implement later/similar to Task N"; mọi bước code có code đầy đủ; mọi bước chạy có lệnh + kết quả mong đợi. Hai chỗ có điều kiện kiểm thật (không phải placeholder): T10 Step 9 (tên service S3 của chart SeaweedFS) và T13 Step 4 (nếu `otelcol-contrib validate` 0.162.0 báo key khác thì sửa theo binary).

**3. Type/name consistency** — đã đối chiếu: `migrate.Up(ctx, dsn, fsys, log)` (T2) ↔ CLI 3 service; env `BG_<SVC>_MIGRATOR_DSN` (T2) ↔ `lib.envPrefix` + `MIGRATOR_DSN` (T6); Secret `<svc>-migrator-dsn` key `dsn` (T6/T7) ↔ `seal-kind.sh` (T10); `<deployable>-env` (T7) ↔ T10; `lib.image` thứ tự releases → digest → tag (T5) ↔ `kind-apps.sh` (`image.repository`/`image.tag`, T11) ↔ `release-bump.sh` `{image,digest}` (T19) ↔ app-of-apps `$values/deploy/releases/kind.yaml` (T21); `deploy/deployables.tsv` cột `deployable image command app_port admin_port` dùng bởi T3/T11/T12/T19; catalog `addons[].{name,wave,namespace,chart,values,releaseName,path,wait,post}` (T9) ↔ `kind-platform.sh` ↔ template T21; Gateway `traefik/traefik-gateway`/`websecure` (T9) ↔ `global.gateway` (T5/T6) ↔ route vận hành (T13); hàm `require_kind_context` (T8), `svc_get`/`prom`/`prom_value` (T13) dùng ở T14–T17, T21; datasource uid `prom`/`traces` (T13) ↔ dashboard + test (T15); `runbook_url` (T14) ↔ file (T17); `concurrency` `release-kind` (T19) ↔ `release-${{ inputs.env }}` (T20).
