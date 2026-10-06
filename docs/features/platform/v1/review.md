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

## Vòng 2 — 2026-10-06

Bước a: `ocr delegate preview -c 9a5ad59` (3 file reviewable) — không có lỗi mới ở mức High/Medium.
Bước b: subagent reviewer mới, tập trung vào fix F1 và các lỗi vòng 1. Đã chạy `deploy/kind/test-sealed-key.sh` (exit 0;
sha256 `~/.config/banking-go/*` không đổi, cluster vẫn còn); chạy test trên bản `9a5ad59^` → exit 1 ở bước 1 (RED thật).
Bước 3 RED đã chạy ở vòng 1 (Makefile cũ → `delete cluster --name banking-go` dù backup lỗi).

| id | Mức | File | Lỗi | Lớp | Trạng thái |
|---|---|---|---|---|---|
| F1 | — | — | Đã sửa đủ ở `sealed-key.sh` (restore + backup), `kind-down`, `kind-ca` | — | đóng |
| R1 | Minor | `Makefile:201` | `kind get clusters` lỗi → `if` false → bỏ backup im lặng rồi vẫn delete | a | chờ owner quyết |
| R2 | Minor | `deploy/kind/sealed-key.sh:27` | "Chưa có key → exit 0" cũng làm post hook `kind-platform` (`deploy/argocd/kind/values.yaml:26`) qua im lặng; `check-platform.sh:30` chỉ kiểm file backup tồn tại | a | chờ owner quyết |
| R3 | Minor | `deploy/kind/test-sealed-key.sh:39` | Test đọc `KIND_CLUSTER` từ env, Makefile `:=` bỏ qua env → tên khác mặc định thì bước 3 fail sai lý do; chưa có target make/CI chạy test | a | chờ owner quyết |
| R4 | Minor | `tasks.json` (T8 evidence), `plan.md:2913` | Còn mô tả hành vi cũ (`-` nuốt lỗi backup) | b | chờ owner quyết |

Rubric (1–5): spec 5 · correctness 4 · security 5 · test evidence 4 · maintainability 4.
**Verdict: Accept** — F1 (Major duy nhất) đã sửa và có test hồi quy RED/GREEN; còn lại Minor (F2, F5, F6, N1, R1–R4) và lớp b
(F3 plan T21, F4 anti-affinity v2) chờ owner quyết.
