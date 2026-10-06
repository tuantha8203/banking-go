---
name: remember
description: Update PROGRESS.md and propose CLAUDE.md or ADR additions from this session.
disable-model-invocation: true
---

Xác định W từ docs/features/<feature>/feature.json (W = docs/features/<feature>/<working>); không có feature.json hoặc không có `working` → DỪNG, đề xuất /brainstorm.
1. Clock-out: cập nhật PROGRESS.md theo template (Current State với commit hash + trạng thái test,
   Đã xong, Đang dở, Tiếp theo cụ thể, Blocker, Baseline đã biết, Ghi chú cho phiên sau).
   Đồng bộ status trong tasks.json với thực tế.
2. Xem lại phiên này và diff của branch (công cụ: `/claude-md-management:revise-claude-md`, ví dụ /claude-md-management:revise-claude-md).
   Đề xuất (chưa ghi) cho tôi duyệt:
   - CLAUDE.md: lệnh mới, gotcha mới, lỗi bạn mắc từ 2 lần trở lên. Mỗi mục 1 dòng.
   - docs/adr/NNNN-<tên>.md: quyết định kiến trúc (Bối cảnh, Quyết định, Hệ quả).
   Không thêm thứ đọc code là biết. Giữ CLAUDE.md dưới 200 dòng.
3. Tôi duyệt rồi mới ghi; commit PROGRESS.md cùng các thay đổi đã duyệt.
