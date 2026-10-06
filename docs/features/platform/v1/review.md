# Review — platform v1 (sprint S1, T1–T12, `git diff main..HEAD`)

## Vòng 1 — 2026-10-06

Bước a: OpenCodeReview delegate (`ocr delegate preview --from main --to HEAD`, 134/186 file; rule `.opencodereview/rule.json`
+ system rule Go/TS/YAML/JSON), review chia 4 nhóm (Go+web, image+Makefile, Helm, kind/platform/secrets). Manifest vendored
(gateway-api, rabbitmq operators) khớp `deploy/platform/vendor.lock` (`sha256sum -c` OK). `make helm-lint helm-test` exit 0.
Bước b: subagent reviewer đối chiếu spec.md + plan.md.

| id | Mức | File | Lỗi | Lớp | Trạng thái |
|---|---|---|---|---|---|
| F1 | Major | `deploy/kind/sealed-key.sh`, `Makefile` (`kind-down`, `kind-ca`) | `sealed-key.sh` không ghim kubectl context; `kind-down` bỏ qua lỗi backup (`-`) rồi xóa cluster → context sai/lỗi backup làm mất hoặc tráo key Sealed Secrets kind (và `make seal` mã hóa bằng cert lạ); `kind-ca` đọc context hiện tại | a (T8) | đã sửa (`fix:` vòng 1) — test `deploy/kind/test-sealed-key.sh` |
| F2 | Minor | `scripts/lib/kind.sh:6-10` | Context chỉ kiểm một lần; đổi context ở terminal khác giữa lúc `kind-platform` chạy → áp vào cluster khác | a | chờ owner quyết |
| F3 | Minor (S1) / Major với plan T21 | `deploy/helm/core-worker/values.yaml:23`, plan.md:6476 | S1 đúng thứ tự (kind-apps tuần tự `--wait`, hook pre-upgrade); app-of-apps T21 để mọi app sync-wave 0 → core-worker có thể rollout trước/không cần migration core | b (plan T21) | chờ owner sửa plan trước S3 |
| F4 | Minor | `deploy/helm/_lib/templates/_deployment.tpl:29-43` | Không có anti-affinity/topologySpread (deployment.md:239 yêu cầu cho staging/prod); spec v1 không liệt kê | b (spec, v2 staging) | chờ owner quyết |
| F5 | Minor | `pkg/go.mod` | Chưa tidy: pgx/goose/testcontainers đánh dấu `// indirect`, thiếu `jackc/puddle/v2` | a (T2) | chờ owner quyết |
| F6 | Minor | `apps/web-*/public/config.js`, `deploy/docker/spa.Dockerfile:20` | `config.js` dev (localhost) nằm trong image; env thiếu ConfigMap mount thì SPA âm thầm gọi localhost | a (T4) | chờ owner quyết |
| N1 | Minor | `pkg/migrate/migrate.go:33` | `lock_timeout=5s` + advisory lock chưa có test | a (T2) | chờ owner quyết |

Rubric (1–5): spec 4 · correctness 3 · security 4 · test evidence 4 · maintainability 4.
**Verdict: Revise** — F1 là lỗi code thật trong phạm vi T8, sửa được kèm test tái hiện; các lỗi còn lại Minor hoặc lớp b.

### Sửa F1
- Test tái hiện `deploy/kind/test-sealed-key.sh` (kubeconfig tạm, current context `elsewhere` không tới được; kind giả ghi lệnh delete):
  RED trước khi sửa — (1) `backup` đọc context hiện tại → `connection refused` rồi báo sai "no controller key"; (2) `make kind-ca`
  → `Makefile:210: kind-ca Error 1`; (3) Makefile cũ: backup lỗi (`notadir/...: Not a directory`) nhưng `make kind-down` exit 0 và gọi
  `delete cluster --name banking-go`.
- Sửa: `sealed-key.sh` source `scripts/lib/kind.sh`, mọi `kubectl`/`kubeseal` dùng `--context "$KIND_CONTEXT"`; chưa có key → exit 0
  (không có gì để backup), lỗi kubectl → exit ≠ 0. `kind-down`: backup chỉ khi cluster tồn tại, không còn `-` → backup lỗi thì dừng
  trước delete. `kind-ca`: `--context kind-$(KIND_CLUSTER)`.
- GREEN: `deploy/kind/test-sealed-key.sh` → 3 dòng `ok`, `sealed-key: all checks passed`; `make test` exit 0; `make lint` exit 0.
