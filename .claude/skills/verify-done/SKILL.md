---
name: verify-done
description: Verify a feature end to end with evidence, then open the PR.
disable-model-invocation: true
argument-hint: "[feature]"
---

Xác định W từ docs/features/<feature>/feature.json (W = docs/features/<feature>/<working>); không có feature.json hoặc không có `working` → DỪNG, đề xuất /brainstorm.
Công cụ: chạy `.claude/vendor/superpowers/verification-before-completion/SKILL.md` (+ `.claude/vendor/ecc/verification-loop/SKILL.md` nếu có).
0. Chạy `scripts/sprint.sh check --all`. Fail → liệt kê task còn thiếu, DỪNG. Không được bỏ qua bước này.
   Đối chiếu thêm: mọi task "done" đều có commit/test tương ứng (git log, file test) — thấy task "done" mà
   không có dấu vết trong code → chuyển lại "in-progress", báo tôi.
1. Chạy `make build`, `make test`, `make lint`. Dán output.
2. Chạy app (`make run`), thực hiện từng "Tiêu chí hoàn thành" trong W/spec.md,
   ghi bằng chứng (request/response, log, screenshot) cho từng tiêu chí. Kiểm luôn ở local: `/livez`, `/readyz` (admin port) trả đúng; log của luồng mới có trace id;
   metric/trace mới trong mục "Vận hành" xuất hiện ở OTel Collector (`make up-obs`, debug exporter).
3. Tiêu chí nào fail hoặc có regression: KHÔNG báo "xong". Với mỗi lỗi: viết test tái hiện
   (phải FAIL) → sửa đến khi pass → commit "fix: ..." → chạy /review-diff $ARGUMENTS cho phần sửa
   → quay lại bước 1. Nếu lỗi do spec sai: DỪNG, báo tôi.
4. Kiểm clean-state checklist: `./init.sh` chạy được · verification chạy được ·
   mọi task trong W/tasks.json là "done" và có evidence ·
   không có bước dở dang chưa ghi lại · phiên sau làm tiếp được mà không cần sửa tay.
5. Tất cả đạt: hỏi tôi trước khi push; tạo PR với mô tả + bảng bằng chứng
   + link W/review.md. Theo dõi CI của PR tới khi xanh; đỏ thì đọc log job và sửa như bước 3.
   PR được duyệt và merge xong thì đề xuất /ship $ARGUMENTS.
