---
name: review-diff
description: Review the branch diff against spec and plan in up to three review-fix rounds.
disable-model-invocation: true
argument-hint: "[feature]"
---

Xác định W từ docs/features/<feature>/feature.json (W = docs/features/<feature>/<working>); không có feature.json hoặc không có `working` → DỪNG, đề xuất /brainstorm.
Thay đổi so với main: !`git diff --stat main...HEAD || true`
Vòng lặp review cho feature $ARGUMENTS, TỐI ĐA 3 VÒNG:
1. Mỗi vòng:
   a. Chạy `/open-code-review:delegate-review` trên diff so với main (chế độ delegate: OCR chọn file + rule
      `.opencodereview/rule.json`, bạn là người review). KHÔNG dùng `/open-code-review:review` (lệnh đó tự sửa code).
   b. Dùng subagent reviewer (mỗi vòng một subagent mới) đối chiếu diff + kết quả bước a với
      W/spec.md và W/plan.md, gộp lỗi, chấm rubric và ra verdict.
   Ghi kết quả vào W/review.md, mục "Vòng N" (lỗi, mức độ, trạng thái).
2. Verdict Accept → báo ĐẠT, đề xuất chạy /verify-done $ARGUMENTS. Minor: liệt kê cho tôi quyết.
   Verdict Block → DỪNG, báo tôi (xử lý như mục 3b).
3. Verdict Revise → phân loại TỪNG lỗi Critical/Major:
   a. Lỗi code / thiếu edge case / test yếu: viết test tái hiện (chạy cho thấy FAIL),
      sửa code đến khi pass, chạy `make test` và `make lint`, commit "fix: <lỗi>".
      KHÔNG sửa/xóa test cũ để cho qua.
   b. Sai thiết kế, plan thiếu task, spec thiếu/mâu thuẫn: DỪNG, báo tôi kèm đề xuất sửa
      plan hoặc spec. Không tự đổi spec/plan.
4. Sửa xong nhóm (a) → quay lại bước 1 (vòng mới), reviewer tập trung vào phần vừa sửa
   và các lỗi vòng trước.
5. Hết 3 vòng vẫn còn Critical/Major, HOẶC 2 vòng liền cùng một lỗi lặp lại (không tiến triển)
   → DỪNG, tóm tắt lỗi còn lại và các cách đã thử, để tôi quyết.
