---
name: foundation
description: Create, rebuild or update the project foundation (product, flows, UX, architecture, data/API, NFR, deployment, observability).
disable-model-invocation: true
argument-hint: "[update <phần>]"
---

Lệnh nền dự án. Tham số: $ARGUMENTS (trống = tạo mới hoặc dựng lại; "update <phần>" = đổi một phần core).
Công cụ: BMAD (plugin bmad-method@bmad, skill: bmad-product-brief, bmad-prd, bmad-ux, bmad-architecture; đọc thẳng SKILL.md trong ~/.claude/plugins/cache/bmad/bmad-method/<version>/skills/ nếu skill chưa hiện; config _bmad/, output docs/foundation/_bmad/) (BMAD: bmad-product-brief, bmad-prd, bmad-ux, bmad-architecture, bmad-walkthrough).
Nếu plugin BMAD đang tắt: nhắc tôi bật trong /plugin rồi /reload-plugins, hoặc chạy bản tự viết bên dưới.
Bắt đầu: tạo file .claude/foundation.unlock (bằng Bash). Kết thúc (kể cả khi dừng giữa chừng): xóa file đó.

A. Tạo mới (chưa có docs/foundation/, chưa có code):
   Làm lần lượt, mỗi phần phỏng vấn tôi bằng AskUserQuestion, đưa 2-3 phương án cho quyết định lớn, chờ tôi chốt:
   1. Product → docs/foundation/product.md, glossary.md
   2. Business flows → business-flows.md (Mermaid sequence/state, có ngoại lệ)
   3. UX & design system → design-system.md (bỏ qua nếu không có frontend)
   4. System design → architecture.md (C4 context + container, stack, deploy) + docs/adr/NNNN-*.md cho mỗi lựa chọn lớn
   5. Data & API → data-model.md, api-contracts/ (OpenAPI/AsyncAPI)
   6. NFR & nguyên tắc → nfr.md, constitution.md
   7. Deployment → deployment.md: môi trường; VM / Kubernetes / cloud; đóng gói; CI/CD (GitLab CI / GitHub Actions /
      Jenkins); rollout, rollback; secret; thứ tự migration; ai duyệt deploy prod
   8. Observability → observability.md: SLI/SLO từng service; chuẩn log/metric/trace; stack giám sát (ưu tiên
      hệ thống công ty đang có); alert + người nhận; runbook; khoảng theo dõi sau deploy
   Bản gốc của công cụ để ở docs/foundation/_bmad/; file chuẩn là bản đã gộp, ngắn gọn.
   Hết mỗi phần: ghi tiến độ vào PROGRESS.md, đề xuất /clear trước phần sau.
B. Dựng lại (đã có code):
   Dùng subagent đọc code (service, handler/route, model/schema, migration, queue/topic, pipeline CI/CD,
   Dockerfile/Helm/Terraform/Ansible, endpoint health/metrics, alert rule, docs/runbook có sẵn).
   Viết nháp từng file như mục A, mỗi ý gắn nhãn [code] (kèm đường dẫn), [suy đoán] hoặc [thiếu].
   Hỏi tôi để xác nhận [suy đoán] và trả lời [thiếu]. Chỗ code lệch thiết kế → mục "Nợ kỹ thuật đã biết"
   trong architecture.md. KHÔNG sửa code.
C. Update <phần>:
   Đọc phần đó và các phần phụ thuộc. Nêu: thay đổi gì, vì sao, ảnh hưởng tới phần nào của foundation,
   tới feature nào (tra docs/features/INDEX.md) và spec/plan/code nào đang có. Viết ADR mới trong docs/adr/.
   Chỉ sửa sau khi tôi duyệt. Ghi một mục vào docs/foundation/CHANGELOG.md: "foundation vN — ngày — phần đổi —
   tóm tắt diff — ADR", rồi gợi ý tôi gắn git tag foundation-vN.
Cuối mọi chế độ: rà chéo (flow nào thiếu API/màn hình, entity nào không flow nào dùng, NFR nào kiến trúc
chưa đáp ứng, SLO nào chưa có metric để đo, môi trường nào chưa có cách deploy/rollback), báo tôi, rồi commit "docs: foundation vN" và xóa .claude/foundation.unlock.
