# banking-go
Core banking tối giản chuẩn kỹ thuật production (học + portfolio, không có khách hàng thật). Stack: Go 1.27 (chi + Huma v2, grpc-go, pgx/sqlc/goose, RabbitMQ, OpenTelemetry) + React 19/Vite 8/Ant Design 6 (pnpm), PostgreSQL 18, RabbitMQ 4.3.

## Commands
- Cài: `make install` · Build: `make build`
- Test 1 phần (ưu tiên): `make test-one PKG=./pkg/health RUN=TestReadyz` (Go) · `make test-one WEB=@banking-go/web-customer RUN='renders'` (web)
- Toàn bộ: `make test` (không cần Docker) · Integration (testcontainers, cần Docker): `make test-integration` · E2E: `make e2e`
- Lint: `make lint` (golangci-lint v2 + depguard, buf lint, ESLint/Prettier, tsc) — chạy sau mỗi loạt thay đổi
- Sinh code: `make gen` (protobuf → pkg/gen, OpenAPI → services/*/api/openapi); `make gen-check` trong CI
- Run: `make run` (compose: postgres, rabbitmq, seaweedfs) rồi chạy service theo hướng dẫn in ra; `make up-obs` thêm OTel Collector
- Tool Go pin trong `tools/` (ngoài go.work): `cd tools && GOWORK=off go tool sqlc|goose ...`
- pnpm: luôn qua `npx -y pnpm@12.9.1` (Makefile đã bọc)
- kind (platform v1): `make tools-k8s` → `make kind-up` → `make kind-platform` → `make seal` (lần đầu) → `make images kind-load kind-apps` → `make kind-smoke`; xóa: `make kind-down` (backup key Sealed Secrets ở ~/.config/banking-go/)

## Foundation (đọc file liên quan khi cần, không đọc hết)
- Sản phẩm & phạm vi: docs/foundation/product.md · Thuật ngữ: docs/foundation/glossary.md
- Business flow: docs/foundation/business-flows.md · Data: docs/foundation/data-model.md · API: docs/foundation/api-contracts/
- Kiến trúc: docs/foundation/architecture.md · Hợp đồng ràng buộc (AD-1..AD-26): docs/foundation/_bmad/planning-artifacts/architecture/architecture-banking-go-2026-10-05/ARCHITECTURE-SPINE.md
- NFR: docs/foundation/nfr.md · UI: docs/foundation/design-system.md · Nguyên tắc bất biến: docs/foundation/constitution.md
- Deploy & CI/CD: docs/foundation/deployment.md · Observability & SLO: docs/foundation/observability.md · ADR: docs/adr/
- IMPORTANT: không sửa docs/foundation/ khi làm feature (hook chặn). Feature mâu thuẫn foundation → dừng, đề xuất /foundation update.

## Architecture
- Deployables: public-api, admin-api (edge REST, Huma), core (gRPC, modular monolith, sở hữu mọi thứ chạm tiền), core-worker (cùng code core: outbox relay, consumer, job, webhook), 4 mock đối tác, 2 SPA.
- Mỗi service một database; mỗi module core một schema; module khác chỉ gọi qua `internal/<module>/app` (depguard chặn import domain/adapters chéo).
- Hexagonal: `adapters → app → domain`. Một use case = một Unit of Work; chỉ use case gốc mở/commit transaction (AD-16).
- Tiền: BIGINT VND; ledger kép append-only; chỉ `ledger` đổi số dư, chỉ `payment.Transition` đổi trạng thái giao dịch (AD-4, AD-17, AD-18).
- Async: outbox + RabbitMQ, consumer idempotent qua inbox; không gọi đối tác trong transaction DB; timeout = `unknown` (AD-7, AD-8).
- AuthN ở edge, AuthZ ở core qua internal token; KH chỉ thấy tài nguyên của mình (AD-10).

## Conventions
- Lỗi: mã snake_case ổn định (bảng trong api-contracts/README.md); REST trả RFC 9457; core gửi `ErrorInfo.reason`.
- Config: env `BG_<SERVICE>_<KEY>`, mọi key có trong `.env.example`. Health: `/livez`, `/readyz` trên admin port. Telemetry chỉ OTLP.
- Không log PII đầy đủ, token, secret, ảnh. ID: UUIDv7. Event: `banking.<context>.<entity>.<verb>.v<major>`.
- Integration test dùng Postgres/RabbitMQ thật (testcontainers, tag `integration`); không mock DB cho logic tiền.
- Branch: `feat/<feature>-<vN>`, `fix/...`, `chore/...`; commit: Conventional Commits (`feat:`, `fix:`, `test:`, `docs:`, `chore:`).

## Session
- Đầu phiên: hook SessionStart đã in tiến độ sprint (scripts/sprint.sh status). Đọc thêm PROGRESS.md + BOARD.md của sprint
  + `git log --oneline -5`, rồi chạy `./init.sh`. Baseline fail → sửa baseline trước (trừ test đã ghi trong "Baseline đã biết").
- Cuối phiên: /remember để cập nhật PROGRESS.md; commit khi repo ở trạng thái an toàn để tiếp tục.

## Workflow
- Nền dự án: /foundation (tạo / dựng lại) · /foundation update <phần> (đổi core, bắt buộc ADR)
- Release: /ship <feature> sau khi PR merge. IMPORTANT: KHÔNG deploy production từ máy này, không duyệt job prod;
  prod chỉ qua pipeline GitHub Actions có duyệt tay (environment `production`). Observability chỉ đọc.
- Feature: /brainstorm (mới hay nâng cấp?) → /write-plan → /sprint plan → [/write-tests → /implement] × task → /review-diff
  → /verify-done → /ship → /remember. Xem board: /sprint status.
- IMPORTANT: mỗi lần chỉ làm ĐÚNG MỘT task (WIP = 1), lấy task kế bằng `scripts/sprint.sh next`, không tự chọn;
  không sửa file ngoài phạm vi task hoặc trong mục "Hands off" của spec.
- IMPORTANT: KHÔNG báo sprint/feature xong khi `scripts/sprint.sh check` còn fail. Task chỉ "done" khi có evidence
  (lệnh + kết quả). KHÔNG xóa task: bỏ thì "dropped" + lý do + tôi duyệt. Việc phát sinh → sprint sau (hoặc hỏi tôi).
- Version: "current" trong feature.json là bản đã lên prod; chỉ sửa thư mục version đang làm ("working"),
  không sửa thư mục của version đã released.
- Review/Verify không đạt: lỗi code → viết test tái hiện → sửa → review lại (tối đa 3 vòng); lỗi spec/thiết kế → dừng hỏi tôi.
- Feature: docs/features/<feature>/vN/ (spec, design, diff, plan, tasks, review) · Sổ feature: docs/features/INDEX.md · Quyết định kiến trúc: docs/adr/
- IMPORTANT: không sửa/xóa test để "cho qua"; không commit secret.
- When compacting, always preserve the list of modified files and test commands.

## Definition of Done
- Implement đủ theo spec · `scripts/sprint.sh check` pass · verification đã chạy thật, có evidence · review Accept · verify đạt
- PROGRESS.md và tasks.json đã cập nhật · repo chạy lại được bằng `./init.sh`
- Đã ship: staging đạt + observability có dữ liệu + prod qua khoảng theo dõi 30 phút (hoặc ghi "chờ release" trong PROGRESS.md)

## Tool conventions
- Foundation: BMAD (plugin chỉ bật khi chạy /foundation)
- Brainstorm: tự viết (template /brainstorm) · Plan: Superpowers writing-plans · Test: Superpowers TDD · Implement: ECC (rules + skill đã duyệt)
- Review: Open Code Review (delegate) + subagent reviewer · Verify: Superpowers verification-before-completion · Ship: plugin github + MCP observability chỉ đọc
- Remember: claude-md-management · Improve: claude-code-setup + hookify
- Mọi spec/plan lưu ở docs/features/<feature>/vN/ — KHÔNG dùng thư mục mặc định của công cụ.
- Convention trong file này luôn thắng rule của công cụ nếu mâu thuẫn.

## Gotchas
- Chưa có remote GitHub: `main` chỉ ở local; CI (`.github/workflows/ci.yml`) chưa từng chạy thật.
- `tools/` nằm ngoài go.work: chạy tool Go với `GOWORK=off` trong `tools/`.
- pnpm 12 chặn package mới phát hành (minimum release age) → có thể phải pin bản cũ hơn một chút.
- File sinh ra (pkg/gen, api/openapi, lockfile) bị hook chặn sửa tay: sửa nguồn rồi `make gen` / chạy lệnh package manager.
- Migration đã có trên main: không sửa, tạo file mới (hook chặn).
- kind cần cổng 80/443 trống trên host và ~6–7 GB RAM; `*.kind.localhost` tự trỏ 127.0.0.1 (curl/trình duyệt), CA: `make kind-ca`.
- S1/S2 cài kind bằng helm/kubectl trực tiếp (`kind-platform`, `kind-apps`) — đường tạm chỉ cho kind, S3 chuyển sang Argo CD.
- Script kind kiểm kubectl context một lần lúc bắt đầu: KHÔNG đổi context (`kubectl config use-context`) ở terminal khác khi `kind-platform`/`kind-apps` đang chạy.
