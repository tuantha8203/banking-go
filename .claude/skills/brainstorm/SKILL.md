---
name: brainstorm
description: Turn a feature idea into an approved spec for a new feature or a new version of an existing one.
disable-model-invocation: true
argument-hint: "[feature idea]"
---

Chưa viết code. Ý tưởng: $ARGUMENTS
A. Phân loại TRƯỚC TIÊN. Hỏi tôi bằng AskUserQuestion: "Tính năng mới" · "Nâng cấp tính năng có sẵn" ·
   "Để AI tự tra". Tự tra = đọc docs/features/INDEX.md + tìm trong code (route, module, bảng, tên hàm), rồi
   đề xuất "mới" hoặc "nâng cấp <feature> (đang ở vN)" kèm bằng chứng (đường dẫn file); tôi xác nhận.
   - Mới: tạo docs/features/<slug>/feature.json {"feature","title","current": null, "working": "v1",
     "versions": {"v1": {"status": "draft", "summary": "..."}}} và README.md; W = docs/features/<slug>/v1.
   - Nâng cấp: đọc spec.md/design.md của version "current". Feature cũ chưa có thư mục (làm trước khi có flow)
     → dựng v1 từ code trước (hành vi đang chạy, nhãn [code]/[suy đoán], status "released", current "v1").
     Tạo v(N+1): W = docs/features/<slug>/v(N+1), "working": "v(N+1)", "base": "vN", status "draft".
     Viết thêm W/diff-from-vN.md: Thêm / Đổi / Bỏ, Vì sao, Tương thích ngược, Migration, Rollback.
     Hỏi tôi: có cần feature flag không (khuyến nghị cho nâng cấp lớn); có thì ghi tên flag vào feature.json.
   KHÔNG sửa thư mục của version đã "released" (hook sẽ chặn).
0. Đọc file foundation liên quan: business-flows.md (flow nào?), architecture.md, data-model.md,
   api-contracts/, design-system.md nếu có UI, constitution.md. Chỉ hỏi những gì foundation chưa trả lời.
   Feature mâu thuẫn foundation, hoặc chạm vùng [suy đoán]/[thiếu] → DỪNG, hỏi tôi: sửa feature
   hay chạy /foundation update.
1. Đọc CLAUDE.md và phần code liên quan để hiểu hiện trạng.
2. Phỏng vấn tôi bằng AskUserQuestion, mỗi lượt tối đa 3 câu: mục tiêu, edge case,
   hiệu năng, bảo mật, trade-off. Bỏ qua câu hiển nhiên.
3. Đưa 2-3 phương án kèm ưu/nhược, đề xuất 1, chờ tôi chốt.
4. Viết W/spec.md: Mục tiêu, Flow liên quan (trỏ tới business-flows.md), Phạm vi, Ngoài phạm vi,
   Hands off (file/module cấm sửa), Thiết kế (file/interface), Tiêu chí hoàn thành (mỗi tiêu chí kiểm được
   bằng một lệnh), Vận hành (biến môi trường/config mới, migration và thứ tự deploy, log/metric/alert cần thêm
   theo observability.md, feature flag, cách rollback), Rủi ro.
   Spec của version mới phải đọc được độc lập (mô tả đầy đủ, không chỉ phần thay đổi). Có UI → viết W/design.md
   (màn hình, hành vi, component/token dùng từ design-system.md). Nâng cấp → design.md đầy đủ cho version mới,
   phần khác biệt nằm trong diff-from-vN.md.
5. Cập nhật feature.json (status "in-progress" khi tôi chốt spec), README.md của feature (bảng các version),
   chạy `scripts/sprint.sh index`.
