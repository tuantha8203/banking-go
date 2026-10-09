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

## Quyết định của owner — 2026-10-06
- R1, R2, R3, R4, F5, F6 → task **T22** "Sửa lỗi nhỏ sau review S1" (sprint S2).
- N1 → hoãn, làm khi có migration thật đầu tiên.
- F2 → bỏ qua; ghi vào Gotchas trong `CLAUDE.md`.
- F3 → đã sửa plan T21: `core-worker` sync-wave `1` (sau `core` Healthy) + helm-unittest tương ứng.
- F4 → backlog v2 (owner duyệt 2026-10-06): `topologySpreadConstraints` mềm (hostname + zone, `ScheduleAnyway`) trong library chart + helm-unittest, làm cùng values staging/prod.

## Retro sprint S2 — 2026-10-09

**Plan so với thực tế**
- Phát sinh: T22 (sửa Minor sau review S1, owner duyệt, làm trước T13). Không task nào dropped.
- Blocked: T16 bị chặn 3 ngày (06→09/10) chờ owner: lần 1 thiếu `TELEGRAM_*` trong `deploy/secrets/kind.env`, lần 2 thiếu `=` ở dòng 17.
- AI phải làm lại: T16 báo "done" trên pass giả (smoke §7 đọc `alertmanager_notifications_failed_total`, chỉ tăng khi hết retry;
  thực tế 100% request tới Telegram timeout vì pod kind không qua proxy công ty) → owner phát hiện, mở lại, sửa test + proxy.
  T14: biểu thức `TelemetryPipelineDegraded` trong plan mất nhãn `job` (unit test bắt được). T13/T14: hai check thiếu chờ
  (counter export lần đầu, Prometheus reload rule) → thêm poll/traffic, assertion giữ nguyên.
- Môi trường: stack observability đẩy máy 15.4 GiB vào swap đầy (load ~98, kube-apiserver restart); T14/T15 chỉ cài addon thay
  đổi thay vì full `kind-platform`. AI không được đọc `deploy/secrets/` nên không tự kiểm được `kind.env(.example)`.

**Bài học**
1. Check "đã gửi được" phải đo tín hiệu thành công dương (`*_requests_total - *_requests_failed_total > 0`, hoặc API phía nhận),
   không suy ra từ "chưa có lỗi"; và mỗi smoke/check mới phải có một lần chạy đối chứng âm với đúng failure mode thật
   (vd. chặn egress) — RED "file chưa tồn tại" không chứng minh check bắt được lỗi.
2. Pod trong kind không có proxy công ty: mọi tích hợp ra internet (Telegram, webhook, sau này GHCR/GitHub từ trong cluster)
   cần cấu hình proxy rõ ràng; nghi proxy đầu tiên khi gặp `dial tcp … timeout`.
3. Check trên hệ eventual-consistent (export metric 60 s, operator reload rule 30–60 s) phải poll có giới hạn và tự tạo traffic
   trong lúc chờ; viết sẵn như vậy trong plan thay vì sửa khi đỏ.
4. Bước owner (secret, bot, chat id) nên được kiểm trước khi bắt đầu task bằng một validator chỉ in tên key/định dạng, không in
   giá trị — vừa bắt lỗi cú pháp `.env` sớm, vừa để AI tự kiểm mà không cần đọc `deploy/secrets/`.
5. RAM là ràng buộc thật của kind + observability trên máy dev: ghi yêu cầu, đóng app khác trước khi chạy full chain, hoặc giảm
   resources/retention cho kind.

**Đề xuất cho /improve (công cụ/flow — cần owner duyệt)**
- Skill `/write-tests`: với smoke/check tích hợp, yêu cầu thêm một lần chạy đối chứng âm theo failure mode thật, ghi vào evidence.
- `CLAUDE.md` Gotchas: pod kind không có proxy (dùng `TELEGRAM_PROXY_URL`/proxy_url); RAM thực tế khi có observability.
- Script `scripts/check-kind-env.sh` (key bắt buộc + định dạng `KEY=value`, chỉ in tên key) chạy đầu `make seal` — là code sản
  phẩm nên đưa vào sprint sau/v2 nếu owner đồng ý.
- Rủi ro S3: xác nhận kind node pull được `ghcr.io` qua proxy (containerd của node) trước T19/T21.

## Quyết định của owner — 2026-10-09 (trước S3)
- GitHub gói Free → **A1**: repo public + package GHCR public (foundation v4, ADR 0012: D-31 sửa, thêm D-37/D-38). Spec/plan T19,
  T21 bỏ PAT `read:packages`, `GHCR_USER/GHCR_PAT`, Sealed `ghcr-pull` và parameter `imagePullSecrets` của app-of-apps
  (test đổi sang `notContains`). Bảng nghiệm thu T21 dòng 5 dùng thông điệp mới của smoke §7 (sau sửa T16).
- gitleaks toàn lịch sử trước khi public: 1 finding (ví dụ `curl -u` với mật khẩu compose local trong skill docker-patterns),
  owner chấp nhận → `.gitleaksignore` theo fingerprint, ví dụ đổi sang env var; quét lại sạch (61 commit).
- /improve sau retro S2: 4a, 3a, 5a đã áp dụng (73077b3); 7a chờ owner chạy `/foundation update observability`.
