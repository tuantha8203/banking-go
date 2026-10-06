---
name: sprint
description: Plan, show, review or retro the active sprint backed by tasks.json.
disable-model-invocation: true
argument-hint: "[plan|status|review|retro]"
---

Xác định W từ docs/features/<feature>/feature.json (W = docs/features/<feature>/<working>); không có feature.json hoặc không có `working` → DỪNG, đề xuất /brainstorm.
Điều phối sprint. Chế độ: $ARGUMENTS (trống = status). Nguồn sự thật: W/tasks.json; xem bằng scripts/sprint.sh.
- plan: kiểm W/tasks.json đã chia sprint; đặt sprint đầu chưa xong là "active" (chỉ 1 sprint active);
  ghi "<feature>/<version>" vào docs/features/ACTIVE; chạy `scripts/sprint.sh board`; báo sprint goal + danh sách task.
- status: chạy `scripts/sprint.sh status` và `scripts/sprint.sh board`; báo: đã xong, đang làm, blocked (kèm lý do),
  task tiếp theo (`scripts/sprint.sh next`). Không tự làm task nào.
- review: chạy `scripts/sprint.sh check`. Fail → liệt kê task còn thiếu, DỪNG, không đóng sprint.
  Pass → tóm tắt kết quả theo sprint goal, đề xuất demo trên staging (/ship); tôi đồng ý thì đặt sprint này
  "done", sprint kế "active", chạy board. Hết sprint của version → đề xuất /verify-done rồi /ship.
- retro: so plan với thực tế (task phát sinh, task dropped, task blocked lâu, chỗ AI phải sửa nhiều lần);
  ghi 3-5 bài học vào W/review.md mục "Retro sprint X"; bài học về công cụ/flow → đề xuất cho /improve.
Luật: không xóa task; bỏ task = "dropped" + note lý do + tôi duyệt; việc phát sinh → sprint sau (hoặc hỏi tôi).
