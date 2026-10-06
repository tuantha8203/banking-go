---
title: "Addendum: banking-go brief"
created: 2026-10-05
updated: 2026-10-05
---

# Addendum — chi tiết cho PRD / kiến trúc

## Kế hoạch release

| Release | Nội dung | Demo |
|---|---|---|
| R1 | KH (eKYC mock), tài khoản, ledger kép, nạp/rút, chuyển nội bộ, audit, admin cơ bản; CI/CD, observability | Mở tài khoản → nạp → chuyển → sao kê; số dư luôn cân |
| R2 | Chuyển liên NH (NAPAS mock), OTP, hạn mức, phí, maker-checker, web khách hàng | Internet banking chuyển liên NH với lỗi/timeout giả lập |
| R3 | Đối soát, EOD, báo cáo kế toán, load test + HA/failover | Chạy EOD, phát hiện và xử lý giao dịch lệch |
| R4 | Tiết kiệm có kỳ hạn, lãi dồn tích, tất toán | Gửi tiết kiệm, tính lãi qua nhiều ngày |

Luật: mỗi release đạt đủ 4 chuẩn (đúng tiền, bảo mật + audit, vận hành, tải/HA) cho phần nó làm; không dồn hạng mục chất lượng xuống cuối. Ngoại lệ: mục tiêu 500 TPS và failover test chốt ở R3, nhưng R1–R2 đã đo baseline.

## Vai trong web admin

- **Giao dịch viên / vận hành**: tra cứu KH/tài khoản, khóa/mở, xử lý giao dịch treo.
- **Kiểm soát viên**: duyệt thao tác nhạy cảm do người khác tạo (điều chỉnh số dư, mở khóa, đổi hạn mức) — maker ≠ checker.
- **Kế toán / đối soát**: xem sổ cái, kết quả đối soát, báo cáo EOD.
- **Quản trị hệ thống**: user admin, phân quyền, cấu hình hạn mức/phí/sản phẩm tiết kiệm, xem audit log.

## Mock service

Mỗi mock có chế độ lỗi cấu hình được: thành công, lỗi nghiệp vụ, timeout, trả chậm, callback trùng, callback không bao giờ đến.

- NAPAS mock: chuyển liên NH, tra cứu tên người nhận, file đối soát cuối ngày.
- eKYC mock: xác thực giấy tờ + khuôn mặt (kết quả giả lập).
- OTP mock: gửi/nhận OTP (SMS giả lập, xem được qua UI/log).
- Cổng nạp/rút mock: mô phỏng nạp từ nguồn ngoài, rút về nguồn ngoài.

## Yêu cầu chất lượng (đầu vào cho NFR)

- Bất biến ledger: tổng Nợ = tổng Có trên toàn hệ thống và từng giao dịch; số dư suy ra được từ bút toán.
- Idempotency key bắt buộc cho mọi API tạo giao dịch.
- Chaos test: N request đồng thời trên cùng tài khoản, kill process giữa giao dịch, kill DB primary, retry trùng key → 0 lệch, 0 nhân đôi.
- Hiệu năng: chuyển khoản 500 TPS, p95 < 200ms (k6).
- HA: SLO 99.9%; failover DB primary dưới tải, phục hồi < 1 phút, không mất giao dịch đã xác nhận.
- Audit log append-only, ai/lúc nào/cái gì/trước-sau.

## Bối cảnh pháp lý tham khảo (VN)

Lấy tinh thần, không cam kết tuân thủ: eKYC khi mở tài khoản; xác thực giao dịch theo ngưỡng hạn mức (OTP trên ngưỡng); hạn mức theo ngày/giao dịch; lưu trữ dữ liệu giao dịch; AML cơ bản (cảnh báo giao dịch bất thường). Bảo mật tham khảo PCI DSS, OWASP ASVS/Top 10.

## Portfolio deliverables

- URL staging + kịch bản demo 5 phút mỗi release.
- docs/foundation + ADR giải thích lựa chọn thiết kế.
- Báo cáo k6, chaos, failover kèm ảnh dashboard.
- ≥ 1 postmortem sự cố giả lập + runbook.
