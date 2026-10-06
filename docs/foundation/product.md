# Product — banking-go

> Nguồn: `_bmad/planning-artifacts/briefs/brief-banking-go-2026-10-05/` (brief.md, addendum.md). Chốt 2026-10-05.

## Là gì
Core banking tối giản viết bằng Go: backend + web khách hàng (internet banking) + web admin. Không có khách hàng thật;
tác giả tự đóng mọi vai. Đối tác ngoài (NAPAS, eKYC, OTP, cổng nạp/rút) là mock có lỗi giống thật.
"Production" = **chuẩn kỹ thuật** (đúng tiền, bảo mật + audit, vận hành thật, tải/HA), không phải sản phẩm thương mại.

## Mục tiêu
Học sâu cách core banking vận hành + portfolio chứng minh bằng số liệu. Câu chuyện phụ: xây bằng quy trình AI coding có kỷ luật.

## Vai
- Khách hàng cá nhân — web KH.
- Giao dịch viên/vận hành · Kiểm soát viên (maker-checker) · Kế toán/đối soát · Quản trị hệ thống — web admin.

## Release
| Release | Nội dung | Demo |
|---|---|---|
| R1 | KH (eKYC mock), tài khoản, ledger kép, nạp/rút, chuyển nội bộ, audit, admin cơ bản; CI/CD, observability | Mở TK → nạp → chuyển → sao kê; số dư luôn cân |
| R2 | Chuyển liên NH (NAPAS mock), OTP, hạn mức, phí, maker-checker, web KH | Internet banking chuyển liên NH với lỗi/timeout giả lập |
| R3 | Đối soát, EOD, báo cáo kế toán, load test + HA/failover | Chạy EOD, phát hiện và xử lý giao dịch lệch |
| R4 | Tiết kiệm có kỳ hạn, lãi dồn tích, tất toán | Gửi tiết kiệm, tính lãi qua nhiều ngày |

Mỗi release đạt chuẩn production cho phần của nó. 500 TPS + failover bắt buộc từ R3; R1–R2 đo baseline.

## Tiêu chí thành công
| Nhóm | Tiêu chí |
|---|---|
| Đúng tiền | Tổng Nợ = tổng Có mọi lúc; chaos test (đồng thời, kill process/DB, retry trùng) → 0 lệch, 0 nhân đôi; chạy trong CI |
| Hiệu năng | Chuyển khoản 500 TPS, p95 < 200ms (k6) — từ R3 |
| Sẵn sàng | SLO 99.9%; kill instance/DB primary dưới tải → không mất giao dịch, phục hồi < 1 phút — từ R3 |
| Bảo mật | AuthN/AuthZ theo vai, audit log append-only, mã hóa dữ liệu nhạy cảm, không lỗi nghiêm trọng theo OWASP Top 10 |
| Portfolio | Demo E2E trên staging mỗi release (5 phút); kiến trúc + ADR; báo cáo load/chaos/failover; ≥ 1 postmortem + runbook |

## Phạm vi
**Trong**: nghiệp vụ R1–R4; chỉ VND; KH cá nhân; phí giao dịch cấu hình được; mock NAPAS/eKYC/OTP/cổng nạp-rút
(chế độ lỗi: thành công, lỗi nghiệp vụ, timeout, trả chậm, callback trùng, callback không đến).
Bối cảnh VN *tham khảo* (tinh thần quy định NHNN: eKYC, OTP theo ngưỡng, hạn mức, lưu trữ, AML cơ bản; PCI DSS, OWASP) —
không cam kết tuân thủ pháp lý.

**Ngoài**: thẻ; cho vay/tín dụng; đa tiền tệ/FX; mobile app; KH doanh nghiệp; đối tác thật.

## Vision
Dừng ở R4: bộ reference core banking chuẩn production bằng Go — code để hiểu cách làm, ADR để hiểu vì sao, test để thấy nó đúng.
