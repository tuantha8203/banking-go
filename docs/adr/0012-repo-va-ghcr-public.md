# 0012. Repo GitHub và package GHCR công khai (public)

- Trạng thái: Accepted (2026-10-09)
- Liên quan: D-19, D-22, D-31, D-37, D-38 (`deployment.md`), ADR 0011, feature `platform` v1 (S3)

## Bối cảnh
Tài khoản GitHub của owner là gói Free. Foundation dựa vào ruleset `main` (PR + CI xanh, bot `bg-release-bot` bypass chỉ
`deploy/releases/*`, D-22) và environment `production`/`staging-infra` có Required reviewer = owner. Trên gói Free các tính năng
này chỉ có cho repo public; repo private còn giới hạn ~2.000 phút Actions/tháng và ~500 MB lưu trữ package (6 image × nhiều
release đầy nhanh). D-31 cũ (package private, pull bằng token) cần thêm PAT/pull secret ở mọi môi trường. Dự án là học +
portfolio, không có khách hàng thật.

## Các phương án đã cân nhắc
1. Repo public + package GHCR public — chọn.
2. Repo public + package private — ruleset/reviewer dùng được, nhưng vẫn cần PAT + Sealed `ghcr-pull`, giới hạn ~500 MB.
3. Giữ repo private — mất ruleset và Required reviewer (cổng duyệt prod), giới hạn phút Actions và lưu trữ.

## Quyết định
Repo `<GH_OWNER>/banking-go` và 6 package GHCR `banking-go/*` để public. Bỏ pull secret GHCR ở mọi môi trường; tính toàn vẹn
image dựa vào digest pin trong `deploy/releases/<env>.yaml` + chữ ký cosign keyless (D-19). Workflow không dùng
`pull_request_target`; PR từ fork không nhận secret/`id-token`; job release chỉ chạy trên `main`/`workflow_dispatch` (D-38).

## Hệ quả
- Mã nguồn và image công khai; Git chỉ chứa ciphertext Sealed Secrets (giải mã cần controller key do owner giữ, D-32).
  Trước khi public: gitleaks toàn lịch sử (đã chạy 2026-10-09: sạch, một finding được chấp nhận trong `.gitleaksignore`).
- Ruleset `main` + CODEOWNERS (`deploy/`, `infra/`, `.github/`) và environment Required reviewers dùng được trên gói Free.
- platform v1: bỏ bước PAT `read:packages`, `GHCR_USER/GHCR_PAT`, Sealed `banking-ghcr-pull` và parameter `imagePullSecrets`
  của app-of-apps; lib chart vẫn hỗ trợ `global.imagePullSecrets` nếu sau này cần registry riêng.
