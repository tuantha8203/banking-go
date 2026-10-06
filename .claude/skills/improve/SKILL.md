---
name: improve
description: Propose improvements to rules, hooks, skills, tools and foundation drift from recent work.
disable-model-invocation: true
---

Xác định W từ docs/features/<feature>/feature.json (W = docs/features/<feature>/<working>); không có feature.json hoặc không có `working` → DỪNG, đề xuất /brainstorm.
Commit tuần qua: !`git log --since="1 week ago" --oneline || true`
Công cụ: plugin claude-code-setup (gợi ý automation) + hookify (tạo hook từ lỗi lặp lại).
Đề xuất:
1. Rule trong CLAUDE.md hay bị lờ → chuyển thành hook.
2. Chuỗi thao tác lặp lại → skill mới.
3. Dòng CLAUDE.md thừa/mâu thuẫn → xóa.
4. Skill nào trong flow cần sửa prompt (dựa trên chỗ tôi phải sửa bạn nhiều).
5. Công cụ cộng đồng nào cần chỉnh: thêm rule vào .opencodereview/rule.json, sửa rule ECC,
   tắt skill trùng bằng skillOverrides, hoặc fork skill về .claude/skills/ để sửa sâu.
6. Đối chiếu .claude/vendor-lock.json với dự án hiện tại: dependency/hạ tầng mới (Kafka, frontend...)
   → đề xuất lấy thêm từ catalog nguồn (kèm bằng chứng); mục không còn bằng chứng hoặc không dùng → đề xuất gỡ.
   Có version mới của nguồn → tóm tắt changelog, hỏi tôi trước khi nâng; mục "modified": true phải merge tay.
7. Foundation có lệch với code không: commit tuần qua có thêm service/queue/entity/API mà docs/foundation/
   chưa có, hoặc vi phạm architecture.md/constitution.md → liệt kê, đề xuất /foundation update hoặc
   feature trả nợ kỹ thuật. Không tự sửa foundation.
8. Release tuần qua (mục "Release" trong docs/features/*/vN/review.md): pipeline có bước nào chậm/hay fail, smoke test
   thiếu gì, alert nào kêu sai hoặc lẽ ra phải kêu mà không kêu, rollback nào đã xảy ra → đề xuất sửa
   pipeline, smoke test, alert rule (qua PR) hoặc runbook (qua /foundation update observability).
Chờ tôi chọn mục nào áp dụng. Gợi ý chạy thêm /doctor.
