---
title: "Product Brief: banking-go"
status: final
created: 2026-10-05
updated: 2026-10-05
---

# Product Brief: banking-go

## Executive Summary

banking-go là một core banking tối giản viết bằng Go, gồm backend, web cho khách hàng (internet banking) và web admin cho đội vận hành. Hệ thống không có khách hàng thật: tác giả tự đóng mọi vai, từ khách hàng, giao dịch viên, kiểm soát viên, kế toán đến quản trị. Mọi đối tác bên ngoài (NAPAS, eKYC, SMS OTP) là mock service có lỗi và độ trễ giống thật.

"Production" ở đây là **chuẩn kỹ thuật**, không phải sản phẩm thương mại: tiền luôn đúng kể cả khi crash hoặc retry, có bảo mật và audit, vận hành qua CI/CD có observability và runbook, chịu được tải và có failover. Mỗi tuyên bố về chất lượng phải đi kèm test và báo cáo chạy được, không chỉ ghi trong tài liệu.

Mục đích là học sâu cách một core banking thật vận hành và có một portfolio chứng minh được năng lực bằng số liệu. Câu chuyện phụ là hệ thống này được xây bằng quy trình AI coding có kỷ luật (spec, harness, review, verify).

## Vấn đề

Phần lớn dự án "ngân hàng" trong portfolio chỉ là CRUD số dư: cập nhật thẳng cột `balance`, không có sổ cái, không chống retry trùng, không có đối soát, không biết chuyện gì xảy ra khi process chết giữa giao dịch. Chúng không trả lời được những câu hỏi mà người phỏng vấn hệ thống tài chính sẽ hỏi: làm sao chứng minh tiền không bị tạo ra hay mất đi, xử lý timeout từ NAPAS thế nào, cuối ngày chốt sổ ra sao, ai duyệt điều chỉnh số dư.

Học các vấn đề này qua sách thì thiếu trải nghiệm thật. Làm việc trên core banking thật thì hiếm khi được đụng vào toàn bộ luồng.

## Giải pháp

Một hệ thống làm đủ các nghiệp vụ lõi, đi hết vòng đời của tiền:

- **Khách hàng và tài khoản**: đăng ký có eKYC (mock), mở/khóa tài khoản thanh toán, sổ cái kép (double-entry), sao kê.
- **Dòng tiền**: nạp/rút qua cổng mock, chuyển nội bộ, chuyển liên ngân hàng qua NAPAS mock, OTP theo hạn mức, phí giao dịch cấu hình được.
- **Kiểm soát**: maker-checker cho thao tác nhạy cảm, audit log bất biến, phân quyền theo vai.
- **Cuối ngày**: đối soát với NAPAS mock, chốt sổ EOD, báo cáo cân đối.
- **Tiết kiệm**: sổ có kỳ hạn, lãi dồn tích hằng ngày, tất toán đúng hạn và trước hạn.

Hệ thống ra mắt theo 4 release. Mỗi release chạy được, demo được trên staging và đạt chuẩn production cho phần nó làm (chi tiết trong addendum).

## Điểm khác biệt

- **Chứng minh bằng số liệu.** Bất biến tổng Nợ = tổng Có được kiểm liên tục; chaos test (đồng thời, kill process/DB, retry trùng) chạy trong CI; báo cáo tải k6 và failover có dashboard.
- **Vận hành như thật.** Có staging, prod qua pipeline có duyệt tay, SLO, alert, runbook và ít nhất một postmortem sự cố giả lập.
- **Đối tác giả lập có lỗi thật.** Mock NAPAS/eKYC/OTP sinh timeout, lỗi và callback trễ có chủ đích, để luồng xử lý lỗi được test thật.
- **Quy trình AI coding có kỷ luật** (câu chuyện phụ): spec → plan → test → implement → review → verify cho từng feature, lịch sử lưu trong repo.

Không có lợi thế cạnh tranh thương mại; giá trị nằm ở chiều sâu và bằng chứng.

## Đối tượng

- **Tác giả**: người học và chủ portfolio, tự đóng mọi vai.
- **Người đánh giá portfolio** (nhà tuyển dụng, reviewer kỹ thuật): đọc ADR, xem demo 5 phút, xem báo cáo test.
- **Vai trong hệ thống**: khách hàng cá nhân (web KH); giao dịch viên/vận hành, kiểm soát viên, kế toán/đối soát, quản trị hệ thống (web admin).

## Tiêu chí thành công

| Nhóm | Tiêu chí |
|---|---|
| Đúng tiền | Tổng Nợ = tổng Có mọi lúc; chaos test → 0 lệch, 0 giao dịch nhân đôi; chạy trong CI |
| Hiệu năng | API chuyển khoản 500 TPS, p95 < 200ms, có báo cáo k6 (bắt buộc từ R3; R1–R2 đo baseline) |
| Sẵn sàng | (bắt buộc từ R3) SLO 99.9%; kill instance/DB primary dưới tải → không mất giao dịch, phục hồi < 1 phút |
| Bảo mật | AuthN/AuthZ theo vai, audit log bất biến, dữ liệu nhạy cảm được mã hóa, OWASP Top 10 không lỗi nghiêm trọng |
| Portfolio | Mỗi release có demo E2E trên staging; tài liệu kiến trúc + ADR; báo cáo load/chaos; ≥ 1 postmortem |

## Phạm vi

**Trong phạm vi**: các nghiệp vụ ở mục Giải pháp; chỉ VND; khách hàng cá nhân; web khách hàng + web admin; mock NAPAS, eKYC, OTP, cổng nạp/rút; bối cảnh Việt Nam *tham khảo* (tinh thần quy định NHNN về eKYC, xác thực theo hạn mức, lưu trữ, AML cơ bản; PCI/OWASP), không cam kết tuân thủ pháp lý thật.

**Ngoài phạm vi**: thẻ debit/credit; cho vay/tín dụng; đa tiền tệ/FX; mobile app; kết nối đối tác thật; khách hàng doanh nghiệp.

## Vision

Dừng ở R4. banking-go trở thành bộ reference hoàn chỉnh về core banking chuẩn production bằng Go: đọc code để hiểu cách làm, đọc ADR để hiểu vì sao, chạy test để thấy nó đúng.
