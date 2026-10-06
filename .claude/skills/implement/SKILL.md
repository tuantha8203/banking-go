---
name: implement
description: Implement exactly one plan task until its tests and lint pass.
disable-model-invocation: true
argument-hint: "[feature] [task-id]"
---

Xác định W từ docs/features/<feature>/feature.json (W = docs/features/<feature>/<working>); không có feature.json hoặc không có `working` → DỪNG, đề xuất /brainstorm.
Implement task $1 trong W/plan.md. Không truyền task → lấy bằng `scripts/sprint.sh next`.
Task truyền vào khác `next` (dependency chưa xong, khác sprint active) → hỏi tôi trước.
Công cụ: tuân theo rules trong `.claude/rules/ecc/` và skill ECC trong `.claude/skills/` (xem `.claude/vendor-lock.json`);
build/type lỗi thì dùng build-fix. Convention trong CLAUDE.md luôn thắng nếu mâu thuẫn với rule của công cụ.
- Trước khi code: chạy `./init.sh`. Fail ngoài "Baseline đã biết" trong PROGRESS.md → DỪNG, báo tôi.
- Chuyển task sang "in-progress" trong W/tasks.json. Chỉ làm task này (WIP = 1).
- Kẹt (thiếu thông tin, phụ thuộc ngoài) → chuyển "blocked", ghi note lý do, báo tôi; KHÔNG bỏ qua sang task khác im lặng.
- Chỉ viết đủ code để test pass. IMPORTANT: không sửa/xóa test để "cho qua"; không sửa file trong "Hands off".
- Chạy `make test-one PKG=<./path/pkg> RUN=<TestName>` (Go) hoặc `make test-one WEB=<@banking-go/app> RUN=<tên test>` (web)` rồi `make lint`, lặp đến khi pass. Refactor nếu cần, chạy lại test.
- Chuyển task sang "done", ghi evidence (lệnh + kết quả tóm tắt). Đánh dấu [x] trong plan, chạy
  `scripts/sprint.sh board`, commit "feat: <task>". Báo tiến độ dạng "Sprint S1: 5/12 done, tiếp theo T6".
