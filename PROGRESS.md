# PROGRESS

## Current State
- Cập nhật: 2026-10-06 · Commit: c445406 · Test: pass (`./init.sh` → Baseline OK)
- Feature đang làm: platform v1 · Sprint: S1 (0/12) · Task kế: T1 (chi tiết: scripts/sprint.sh status)

## Đã xong
- Foundation v1 (docs/foundation/, spine AD-1..AD-26, ADR 0001–0010) — commit d70d4e5
- Scaffold monorepo (Go workspace, 2 SPA, compose local, Makefile, CI) — commit 41d7a69
- Foundation v2 (env kind, ADR 0011), v3 (cosign v3, URL chart Sealed Secrets)
- Setup AI workflow: CLAUDE.md, .claude/settings.json (permissions, hooks, plugins), 11 lệnh vỏ, reviewer agent,
  Superpowers (writing-plans, TDD, verification) + 18 mục ECC (vendor-lock.json), .opencodereview/rule.json,
  init.sh, scripts/sprint.sh

## Đang dở
- platform v1: spec + plan (21 task / 3 sprint) đã duyệt; S1 active, chưa bắt đầu task nào

## Tiếp theo (cụ thể, làm được ngay)
1. Mở phiên Claude Code mới trong banking-go/ (nạp hooks/skills, đồng ý cài plugin), kiểm `/plugin`, `/hooks`, gõ `/`.
2. platform v1: `/write-tests platform T1` → `/implement platform T1`, rồi lần lượt theo `scripts/sprint.sh next`. S3 cần owner tạo repo GitHub, GitHub App, deploy key, PAT trước.
3. Sau đó các feature nghiệp vụ R1 theo business-flows (BF-1 đăng ký + eKYC trước).

## Blocker / Rủi ro
- Chưa có remote GitHub; CI chưa chạy thật trên GitHub Actions.
- Staging VPS và tài khoản AWS chưa có (cần cho feature nền tảng vận hành).

## Baseline đã biết (test fail từ trước, không phải lỗi mới)
- Không có.

## Ghi chú cho phiên sau
- Backlog platform v2 (review S1, F4): anti-affinity/`topologySpreadConstraints` mềm (hostname + zone) trong `deploy/helm/_lib` Deployment theo deployment.md:239, kèm helm-unittest — làm cùng values staging/prod.
- Hoãn (review platform S1, N1): test `lock_timeout=5s` + advisory lock của `pkg/migrate` — làm khi có migration thật đầu tiên.
- BMAD tắt trong settings dự án; bật lại qua /plugin khi chạy /foundation (config ở _bmad/, output docs/foundation/_bmad/).
- Plugin Superpowers user-level bị tắt trong dự án; bản copy lẻ ở .claude/vendor/superpowers/.
- Open Code Review chạy chế độ delegate (`/open-code-review:delegate-review`), không cần API key.
