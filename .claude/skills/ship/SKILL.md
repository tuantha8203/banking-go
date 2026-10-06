---
name: ship
description: Release a merged feature through staging to production with observability checks.
disable-model-invocation: true
argument-hint: "[feature]"
---

Xác định W từ docs/features/<feature>/feature.json (W = docs/features/<feature>/<working>); không có feature.json hoặc không có `working` → DỪNG, đề xuất /brainstorm.
Release feature $ARGUMENTS. IMPORTANT: KHÔNG chạy deploy production từ máy này, KHÔNG duyệt job production.
Production chỉ đi qua pipeline GitHub Actions có bước duyệt tay. Observability chỉ đọc.
Công cụ: plugin github (PR, GitHub Actions) + MCP Grafana / Elasticsearch / OpenSearch chỉ đọc (nếu đã cấu hình); không có thì dùng `gh run watch`, `gh pr checks`.
Đọc W/spec.md (Tiêu chí hoàn thành, Vận hành), docs/foundation/deployment.md, observability.md.
1. Điều kiện: `scripts/sprint.sh check --all` pass; PR đã merge vào main; pipeline của commit đó
   xanh tới bước build/đóng gói. Chưa đạt → dừng, báo tôi.
2. Staging: theo dõi job deploy staging tới khi xong, dán link/kết quả. Fail → đọc log job:
   lỗi code → đề xuất quay lại /write-tests + /implement; lỗi hạ tầng/pipeline/credential → DỪNG, báo tôi.
3. Smoke test staging (smoke staging theo deployment.md (`/v1/ping` của public-api/admin-api qua Gateway, `/readyz` qua admin port) + từng tiêu chí hoàn thành chạy được trên staging), dán kết quả.
4. Observability trên staging, theo mục "Vận hành" của spec:
   - log có trace id, đúng format, không lộ secret/PII
   - metric mới có dữ liệu; dashboard có panel
   - alert rule mới đã nạp (không cần kích hoạt thật)
   Thiếu mục nào → coi như chưa đạt, quay lại plan/implement.
5. Trình tôi bảng "Hạng mục | Kết quả | Bằng chứng". Hỏi: deploy production?
   Tôi đồng ý → nhắc tôi bấm duyệt job production trên GitHub Actions. AI không tự duyệt.
6. Sau khi job production xong: theo dõi 30 phút các SLI trong observability.md (error rate,
   latency p95, saturation, lỗi mới trong log), so với mức nền trước deploy.
   Vượt ngưỡng SLO → báo ngay, kèm lệnh/cách rollback đã chốt trong deployment.md. Tôi quyết; AI không tự rollback prod.
7. Ghi mục "Release" vào W/review.md (version/commit, thời điểm, bằng chứng staging, kết quả
   theo dõi prod) và cập nhật PROGRESS.md. Có sự cố → đề xuất bổ sung runbook qua /foundation update observability.
8. Prod ổn qua khoảng theo dõi → cập nhật docs/features/<feature>/feature.json: version này "status": "released",
   "release": "<app version / tag / commit>", "date"; "current" = version này; "working" = null; version
   "current" cũ (nếu có) giữ nguyên thư mục, ghi "superseded_by". Làm bước 7 TRƯỚC bước 8 (sau khi released,
   thư mục version bị khóa). Xóa nội dung docs/features/ACTIVE, chạy `scripts/sprint.sh index`, commit.
