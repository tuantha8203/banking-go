# Spec — platform v1: đóng gói, pipeline, Helm/GitOps, observability trên kind

> Feature `platform`, version v1 (mới). Nguồn: docs/foundation/deployment.md, observability.md, ADR 0007, 0008, 0011,
> spine AD-13, AD-14, AD-26. Thiết kế đã duyệt qua brainstorming ngày 2026-10-06.

## Mục tiêu
Mỗi commit lên `main` tự động được đóng gói (image ký + SBOM trên GHCR), ghi digest vào Git, và Argo CD triển khai lên
môi trường `kind` trên máy dev cùng add-on platform giống staging bản nhẹ và observability as code — kiểm chứng được toàn bộ
luồng GitOps, rollback và telemetry trước khi có VPS (v2) và AWS (v3).

## Flow liên quan
Không thuộc business flow (BF-n). Hiện thực "Pipeline", "Release & promotion", "Rollback → App", "Migration", "Secrets"
của deployment.md và "Pipeline theo môi trường", "Alert catalog", "Dashboards", "Runbooks", "Post-deploy watch" của
observability.md cho env `kind`.

## Phạm vi
1. **Image** (6 image cho 10 deployable, D-23): `core` (binary `core`, `core-worker`), `public-api`, `admin-api`, `mocks`
   (4 binary), `web-customer`, `web-admin`. Go: multi-stage → `gcr.io/distroless/static-debian12:nonroot`, `CGO_ENABLED=0`,
   `-trimpath`, version/commit qua ldflags. SPA: build Vite → `nginxinc/nginx-unprivileged`, `config.js` runtime từ ConfigMap.
2. **Subcommand `migrate up`** cho `core`, `public-api`, `admin-api`: goose với migration embed (`services/<svc>/migrations`),
   dùng DSN của role migrator; không có migration nào thì no-op thành công (D-25).
3. **CI** (`ci.yml`, PR + `workflow_call`): thêm build 6 image không push (buildx, cache GHA), `helm lint` + kubeconform
   (schema k8s 1.36 + CRD catalog) + helm-unittest, `promtool check rules` + `promtool test rules`, actionlint.
4. **`main.yml`** (push `main`): gọi `ci.yml` → build matrix 6 image tag `sha-<short>` → Trivy (fail CRITICAL có fix) →
   syft SBOM SPDX + `cosign attest` → `cosign sign` keyless (OIDC GitHub) theo digest → push GHCR → job bump: token GitHub App
   `bg-release-bot` ghi digest vào `deploy/releases/kind.yaml`, commit `chore(release): kind <sha>`; `concurrency: release-kind`.
5. **`rollback.yml`** (`workflow_dispatch`: `env` ∈ {kind}, `revert_sha`): bot `git revert` commit digest, push.
6. **Helm**: library chart `deploy/helm/_lib` (Deployment, Service, ServiceAccount, ConfigMap, HTTPRoute, PDB, migration Job
   PreSync, Certificate mTLS nội bộ) + chart mỏng `deploy/helm/<deployable>` cho 10 deployable với `values.yaml`,
   `values-kind.yaml`. Image lấy từ `deploy/releases/kind.yaml` qua Argo CD multi-source.
7. **kind + Argo CD**: `deploy/kind/kind-config.yaml` (k8s 1.36, 1 CP + 2 worker, 80/443 ra host), `deploy/kind/bootstrap.sh`
   (idempotent), app-of-apps `deploy/argocd/kind/` với sync-wave theo thiết kế; Makefile `kind-up`, `kind-down`, `kind-ca`,
   `kind-smoke`, `kind-watch`, `seal`, `helm-lint`, `helm-test`.
8. **Add-on kind** (`deploy/platform/`, values kind): Gateway API CRDs v1.6, cert-manager (CA self-signed cho `*.kind.localhost`
   + CA nội bộ mTLS), sealed-secrets, Traefik (Gateway API), CNPG operator + `Cluster pg` 1 instance (DB `core`/`public`/`admin`,
   6 managed role), RabbitMQ Cluster Operator + `RabbitmqCluster` 1 node + Messaging Topology Operator (`deploy/messaging/`:
   `banking.events`, `banking.commands`, retry 3 mức, DLQ, user/quyền theo service), SeaweedFS 1 node + Job tạo bucket
   `banking-kind`, kube-prometheus-stack (Grafana 12.4, 1 replica), Jaeger v2 in-memory, OTel Collector contrib
   (`deploy/collector/kind.yaml`).
9. **Secrets**: `deploy/secrets/kind/*.sealed.yaml` (mật khẩu role DB, user RabbitMQ, key S3, pull secret GHCR, Telegram bot
   token/chat id); bootstrap backup/khôi phục key controller ở `~/.config/banking-go/` (ngoài repo).
10. **Observability as code**: alert v1 (`observability/alerts/`): `Watchdog`, SLO burn (`sli:error_ratio:<window>`), p95 breach,
    `TelemetryPipeline`, cert expiry, pod crashloop, Argo CD app degraded — kèm `promtool` unit test; dashboard
    `service-overview` (RED) và `platform` (Argo CD, CNPG, RabbitMQ) JSON Grafana 12.4 (`observability/dashboards/`), datasource
    UID cố định; runbook cho 5 alert (`observability/runbooks/`); Alertmanager → Telegram cho critical + `Watchdog`.

## Ngoài phạm vi
- Staging VPS, Ansible kubeadm, `values-staging.yaml`, `deploy/argocd/staging` (v2); prod AWS, Terraform, `infra-prod.yml`,
  `release-prod.yml`, `db-pitr.yml`, `staging-*.yml`, `nightly.yml` (v3).
- Elasticsearch/Kibana trên kind; admission policy kiểm chữ ký image; NetworkPolicy; alert nghiệp vụ (invariant, unknown,
  DLQ, outbox — feature phát metric sẽ thêm); dùng mTLS trong code service (feature có gọi gRPC chéo sẽ bật).
- Chạy kind trong CI.

## Hands off
- `services/*/internal/**` (nghiệp vụ) — chỉ được thêm `cmd/*` phần `migrate` và wiring version.
- `docs/foundation/**` (đã cập nhật ở foundation v2), `infra/**`, `pkg/gen/**`, `services/*/api/openapi/**`.
- `deploy/releases/*.yaml` chỉ do bot ghi (AI không sửa tay; hook chặn).

## Thiết kế
- Bố cục thư mục và luồng: như mục Phạm vi; lib chart là nơi duy nhất định nghĩa template K8s, chart mỏng chỉ có values.
- Interface chart (`values.yaml` của từng deployable): `image.repository`, `command`, `ports.app`, `ports.admin`,
  `replicas`, `resources`, `env`, `envFromSecrets`, `route.{enabled,host,pathPrefix}`, `migration.{enabled,dsnSecret}`,
  `mtls.enabled`, `shutdownTimeoutSeconds`. Digest: `image.digest` từ `deploy/releases/<env>.yaml` (khóa = tên deployable).
- `deploy/releases/kind.yaml`: `{ <deployable>: { image: ghcr.io/<owner>/banking-go/<image>, digest: sha256:… } }`.
- Host trên kind: `api.`, `admin-api.`, `app.`, `admin.`, `grafana.`, `jaeger.`, `argocd.`, `rabbitmq.` + `.kind.localhost`.

## Tiêu chí hoàn thành (mỗi tiêu chí kiểm bằng lệnh)
1. `make kind-up` exit 0 trên máy sạch; `kubectl -n argocd get applications` toàn `Synced`/`Healthy`.
2. Commit lên `main` → `gh run watch` cho `main.yml` xanh; `cosign verify --certificate-identity-regexp … ghcr.io/<owner>/banking-go/<image>@<digest>`
   đạt cho 6 image; `cosign verify-attestation --type spdxjson` đạt; có commit bot `chore(release): kind <sha>`.
3. Argo CD sync digest mới; Job migration `Completed`; `make kind-smoke` exit 0: `curl -k https://api.kind.localhost/v1/ping`
   và `https://admin-api.kind.localhost/v1/ping` → 200 `{"status":"ok"}`; `app.` và `admin.` → 200 HTML; digest đang chạy
   (`kubectl get pods -o jsonpath`) khớp `deploy/releases/kind.yaml`.
4. `gh workflow run rollback.yml -f env=kind -f revert_sha=<sha>` → sau sync, digest đang chạy = digest trước đó (kind-smoke kiểm).
5. Gọi `api.kind.localhost/v1/ping` → trace `public-api` có trong Jaeger API (`/api/v3/traces?service=public-api`); query
   Prometheus `sum(rate(http_server_request_duration_seconds_count{service_name="public-api"}[5m])) > 0`; dashboard
   `service-overview` tồn tại (Grafana API); alert `Watchdog` firing và tới receiver Telegram (Alertmanager API báo gửi thành công);
   5 runbook tồn tại.
6. `make helm-lint helm-test` exit 0; `promtool test rules` exit 0; `actionlint` exit 0; gitleaks không leak; không có secret
   plaintext trong `deploy/` (chỉ `*.sealed.yaml`).

## Vận hành
- **Config mới**: `OTEL_EXPORTER_OTLP_ENDPOINT` trỏ Collector trong cluster; `BG_<SVC>_*` cho DSN/broker/S3 từ Secret;
  thêm vào `.env.example` nếu có key mới.
- **Migration**: PreSync Job mỗi service có DB; chạy lại an toàn; thất bại → sync dừng, phiên bản cũ chạy tiếp.
- **Log/metric/alert**: alert v1 ở trên; metric RED do otelhttp/otelgrpc phát; Collector redaction PII (O-7).
- **Feature flag**: không.
- **Rollback**: `rollback.yml env=kind`; hỏng cluster → `make kind-down && make kind-up` (khôi phục key Sealed Secrets).
- **Việc owner tự làm**: tạo repo GitHub private + push `main`; GitHub App `bg-release-bot` (contents:write) + ruleset cho bot
  bypass `deploy/releases/*`; deploy key chỉ đọc cho Argo CD; PAT `read:packages` cho pull GHCR; Telegram bot + chat id.

## Rủi ro
- RAM máy dev (~6–7 GB cho kind) → request thấp, 1 replica; quá tải thì tắt Jaeger/Grafana bằng values.
- Node image `kindest/node` 1.36.x chưa có → pin bản 1.36 gần nhất có sẵn, ghi vào Gotchas.
- Chưa có repo GitHub → tiêu chí 2–4 chờ owner; các task còn lại kiểm chứng local trước.
- pnpm 12 minimum release age / Trivy CVE mới có thể làm `main.yml` đỏ ngoài ý muốn → ghi nhận, sửa theo PR.
