# Glossary — banking-go

Thuật ngữ dùng thống nhất trong spec, code và UI. Tên code (tiếng Anh) trong ngoặc.

| Thuật ngữ | Nghĩa |
|---|---|
| Khách hàng (Customer) | Cá nhân đã đăng ký (mọi trạng thái hồ sơ) |
| Tài khoản thanh toán (Account) | Tài khoản VND của khách hàng, có trạng thái hoạt động / khóa ghi Nợ / khóa toàn bộ / đóng |
| Tài khoản sổ cái (Ledger account) | Tài khoản kế toán, gồm tài khoản KH và tài khoản nội bộ (thu phí, trung gian NAPAS, chi lãi...) |
| Bút toán (Entry / Posting) | Một dòng Nợ hoặc Có trên một tài khoản sổ cái |
| Giao dịch (Transaction) | Lệnh nghiệp vụ chuyển tiền (nạp/rút/chuyển…) có trạng thái pending/succeeded/failed/unknown; khi hạch toán sinh một giao dịch kế toán |
| Giao dịch kế toán (Journal) | Nhóm bút toán cân (tổng Nợ = tổng Có), ghi nguyên tử, thuộc đúng một giao dịch |
| Sổ cái kép (Double-entry ledger) | Mọi biến động tiền ghi bằng giao dịch kế toán cân; số dư suy ra từ bút toán |
| Số dư (Balance) | Tổng bút toán của tài khoản |
| Số dư khả dụng (Available balance) | Số dư trừ phần đang tạm giữ |
| Tạm giữ (Hold) | Phong tỏa một phần số dư cho giao dịch đang xử lý |
| Idempotency key | Khóa do client gửi; cùng key → cùng kết quả, không tạo giao dịch thứ hai |
| Chuyển nội bộ (Internal transfer) | Giữa hai tài khoản trong banking-go |
| Chuyển liên ngân hàng (Interbank transfer) | Qua NAPAS mock |
| Giao dịch chưa rõ kết quả (unknown) | Đối tác timeout hoặc không callback trước hạn; chỉ tra soát mới chốt kết quả cuối; khác `pending` (đang xử lý bình thường) |
| Tra soát (Status inquiry) | Hỏi lại đối tác trạng thái một giao dịch `unknown` (BF-5); code: `reconcile_transaction`, `recon_*` trong module `payment` |
| Hạn mức (Limit) | Giới hạn số tiền theo giao dịch/ngày |
| Ngưỡng OTP | Số tiền trở lên phải xác thực OTP |
| Maker-checker | Thao tác nhạy cảm do người A tạo, người B (khác A) duyệt |
| Audit log | Nhật ký append-only: ai, lúc nào, làm gì, trước/sau |
| Đối soát (Reconciliation, R3, module `recon`) | So khớp giao dịch nội bộ với file của đối tác, ra danh sách lệch |
| EOD (End of day) | Chốt sổ cuối ngày: khóa ngày kế toán, tính lãi dồn tích, báo cáo cân đối |
| Ngày kế toán (Business date) | Ngày mà giao dịch được hạch toán, đổi khi chạy EOD |
| Sổ tiết kiệm (Term deposit) | Khoản gửi có kỳ hạn và lãi suất |
| Lãi dồn tích (Accrued interest) | Lãi tính hằng ngày, chưa trả |
| Sao kê (Statement) | Danh sách bút toán theo khoảng thời gian, kèm số dư sau mỗi dòng |
| Tất toán (Settlement / Close) | Đóng sổ tiết kiệm, trả gốc + lãi (trước hạn: toàn bộ thời gian tính lãi không kỳ hạn, đảo lãi đã dồn tích) |
| Mock service | Giả lập đối tác ngoài, có chế độ lỗi cấu hình được |
| GDV (operator) | Giao dịch viên: tra cứu KH/TK, khóa/mở TK, duyệt eKYC, tra soát |
| KSV (supervisor) | Kiểm soát viên: đọc, xem audit; (R2) duyệt maker-checker |
| Kế toán / đối soát (accountant) | Đọc TK/giao dịch, tra soát; (R3) đối soát, EOD |
| Quản trị hệ thống (administrator) | Quản lý user admin và vai, xem audit |
