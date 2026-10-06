# PROGRESS

## Current State
- Cập nhật: 2026-10-06 · Commit: 9e8646d (scaffold) + setup AI workflow (commit kế) · Test: pass (`make test` → exit 0; `make lint` → exit 0)
- Feature đang làm: chưa có · Sprint: - · Task đang làm: - (chi tiết: scripts/sprint.sh status)

## Đã xong
- Foundation v1 (docs/foundation/, spine AD-1..AD-26, ADR 0001–0010) — commit 15e846d
- Scaffold monorepo (Go workspace, 2 SPA, compose local, Makefile, CI) — commit 9e8646d
- Setup AI workflow: CLAUDE.md, .claude/settings.json (permissions, hooks, plugins), 11 lệnh vỏ, reviewer agent,
  Superpowers (writing-plans, TDD, verification) + 18 mục ECC (vendor-lock.json), .opencodereview/rule.json,
  init.sh, scripts/sprint.sh

## Đang dở
- 

## Tiếp theo (cụ thể, làm được ngay)
1. Mở phiên Claude Code mới trong banking-go/ (nạp hooks/skills, đồng ý cài plugin), kiểm `/plugin`, `/hooks`, gõ `/`.
2. Feature đầu tiên: `/brainstorm nền tảng vận hành R1` — Helm chart, Argo CD, staging kubeadm, Terraform prod, workflow main/release-prod/rollback theo deployment.md.
3. Sau đó các feature nghiệp vụ R1 theo business-flows (BF-1 đăng ký + eKYC trước).

## Blocker / Rủi ro
- Chưa có remote GitHub; CI chưa chạy thật trên GitHub Actions.
- Staging VPS và tài khoản AWS chưa có (cần cho feature nền tảng vận hành).

## Baseline đã biết (test fail từ trước, không phải lỗi mới)
- Không có.

## Ghi chú cho phiên sau
- BMAD tắt trong settings dự án; bật lại qua /plugin khi chạy /foundation (config ở _bmad/, output docs/foundation/_bmad/).
- Plugin Superpowers user-level bị tắt trong dự án; bản copy lẻ ở .claude/vendor/superpowers/.
- Open Code Review chạy chế độ delegate (`/open-code-review:delegate-review`), không cần API key.
