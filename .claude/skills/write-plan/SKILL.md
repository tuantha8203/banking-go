---
name: write-plan
description: Write the implementation plan and tasks.json for the working version of a feature.
disable-model-invocation: true
argument-hint: "[feature]"
---

Xác định W từ docs/features/<feature>/feature.json (W = docs/features/<feature>/<working>); không có feature.json hoặc không có `working` → DỪNG, đề xuất /brainstorm.
Công cụ: đọc và làm theo `.claude/vendor/superpowers/writing-plans/SKILL.md` để lập plan; lưu theo quy ước bên dưới.
Đọc W/spec.md và code liên quan. Chưa sửa code.
Viết W/plan.md dạng checklist "- [ ] T1: ...":
- Mỗi task 1 commit, sửa ít file; ghi file sẽ sửa, test cần viết, lệnh kiểm chứng.
- Mục "Vận hành" của spec cũng thành task (metric, alert rule, dashboard, config môi trường, migration, pipeline),
  không dồn xuống cuối.
- Ghi thứ tự phụ thuộc giữa các task.
- Chia sprint: mỗi sprint TỐI ĐA 15 task, có sprint goal; sprint xong phải chạy/demo được. Nhiều hơn 15 task
  → nhiều sprint. Nhiều hơn khoảng 4 sprint → đề xuất tách thành version nhỏ hơn.
Trình bày plan và chờ tôi duyệt. (Nên chạy trong plan mode.)
Sau khi tôi duyệt: tạo W/tasks.json theo format ở mục 3.8 (feature, version, sprints, tasks; mỗi task có
id, sprint, name, dependencies, status "not-started", evidence ""). Đếm lại: số task trong tasks.json
PHẢI bằng số task trong plan.md. Rồi đề xuất /sprint plan.
