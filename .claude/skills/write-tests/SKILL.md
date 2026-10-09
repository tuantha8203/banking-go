---
name: write-tests
description: Write failing tests for one plan task before implementing it.
disable-model-invocation: true
argument-hint: "[feature] [task-id]"
---

Xác định W từ docs/features/<feature>/feature.json (W = docs/features/<feature>/<working>); không có feature.json hoặc không có `working` → DỪNG, đề xuất /brainstorm.
Công cụ: áp dụng `.claude/vendor/superpowers/test-driven-development/SKILL.md` (+ skill testing Go/React trong .claude/skills/ nếu có).
Từ W/plan.md, lấy task $1.
1. Viết test cho tiêu chí của task bằng go test (unit; integration dùng testcontainers với tag `integration`) / Vitest (web);
   task hạ tầng (deploy/, scripts/, observability/) dùng script kiểm/smoke, helm-unittest, promtool, amtool theo plan. KHÔNG viết code implement.
2. Chạy `make test-one PKG=<./path/pkg> RUN=<TestName>` (Go) hoặc `make test-one WEB=<@banking-go/app> RUN=<tên test>` (web)
   hoặc target make của plan (hạ tầng) cho test mới, xác nhận FAIL đúng lý do, dán output.
3. Check tích hợp/smoke (cluster, dịch vụ ngoài, metric): RED "file/target chưa có" KHÔNG đủ chứng minh check bắt được lỗi.
   - Khẳng định bằng tín hiệu thành công dương (vd. `*_requests_total - *_requests_failed_total > 0`, API phía nhận trả về),
     không suy ra từ "chưa có lỗi" (bộ đếm lỗi có thể chỉ tăng khi hết retry).
   - Hệ eventual-consistent (metric export, reload rule/config): poll có giới hạn, tự tạo traffic trong lúc chờ.
   - Khi phần implement xong: chạy thêm một lần đối chứng âm với đúng failure mode thật (chặn egress, sai cấu hình, pod lỗi…)
     và ghi lệnh + output vào evidence của task; nếu chưa làm được ở bước này thì ghi rõ vào commit để /implement làm.
4. Commit "test: <task>".
