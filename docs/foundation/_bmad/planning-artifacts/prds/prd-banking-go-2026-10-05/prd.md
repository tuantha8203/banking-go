---
title: "PRD: banking-go"
status: final
created: 2026-10-05
updated: 2026-10-05
inputs: [../../briefs/brief-banking-go-2026-10-05/brief.md, ../../briefs/brief-banking-go-2026-10-05/addendum.md]
---

# PRD: banking-go

## 0. Mục đích tài liệu
PRD cho tác giả (vừa là PM vừa là dev) và các bước sau: UX, kiến trúc, `/brainstorm` từng feature. Dựa trên brief
`brief-banking-go-2026-10-05`. Thuật ngữ theo `docs/foundation/glossary.md` (bắt buộc dùng đúng). R1 có FR chi tiết;
R2–R4 ở mức feature + journey, chi tiết hóa khi tới release. Giả định gắn `[ASSUMPTION]`, tổng hợp ở §9.

## 1. Vision
Core banking tối giản chuẩn kỹ thuật production bằng Go: đúng tiền tuyệt đối, bảo mật + audit, vận hành thật, chịu tải + HA.
Không có khách hàng thật; tác giả đóng mọi vai; đối tác ngoài là mock có lỗi giống thật. Giá trị là chiều sâu và bằng chứng
(test, báo cáo) để học và làm portfolio.

## 2. Người dùng

### 2.1 Jobs To Be Done
- Tác giả: hiểu end-to-end cách tiền di chuyển trong ngân hàng và chứng minh được hệ thống đúng, an toàn, vận hành được.
- Người đánh giá portfolio: trong 5 phút thấy demo chạy thật và bằng chứng chất lượng.

### 2.2 Non-users
KH doanh nghiệp, người dùng mobile app, đối tác thật.

### 2.3 User journeys

**R1**
- **UJ-1. An mở tài khoản.** An gọi API đăng ký (SĐT, CCCD, ảnh giấy tờ + khuôn mặt, mật khẩu). eKYC mock trả kết quả.
  Đạt → tạo Khách hàng + tự mở Tài khoản thanh toán VND mặc định, số dư 0, trả số tài khoản.
  *Ngoại lệ:* eKYC timeout → hồ sơ "chờ eKYC", hệ thống tự hỏi lại; eKYC "nghi ngờ" → hàng chờ GDV duyệt tay; "không đạt" → từ chối kèm lý do.
- **UJ-2. An nạp 5 triệu.** An tạo yêu cầu nạp qua cổng nạp mock (kèm idempotency key). Cổng callback thành công → ghi giao dịch
  kế toán Nợ TK trung gian cổng / Có TK của An. *Ngoại lệ:* callback trùng → chỉ ghi 1 lần; callback không đến → giao dịch
  `unknown`, job tra soát hỏi lại cổng.
- **UJ-3. An chuyển 1 triệu cho Bình (nội bộ).** Kiểm số dư khả dụng và trạng thái hai TK → một giao dịch kế toán cân →
  `succeeded`, cả hai thấy trong sao kê. *Ngoại lệ:* 100 request đồng thời → không âm số dư, không ghi đôi; client retry cùng key → trả lại kết quả cũ.
- **UJ-4. An rút 2 triệu về nguồn ngoài.** Tạm giữ → gọi cổng rút mock → thành công: hạch toán + giải phóng tạm giữ; thất bại: hủy tạm giữ.
  *Ngoại lệ:* timeout → giữ nguyên tạm giữ, `unknown`, tra soát sau.
- **UJ-5. GDV Chi xử lý.** Đăng nhập admin (mật khẩu + TOTP), tra cứu An theo CCCD/số TK, xem sao kê, khóa ghi Nợ hoặc khóa toàn bộ
  TK kèm lý do, duyệt hồ sơ eKYC "nghi ngờ", xem và tra soát lại giao dịch `unknown`. Mọi thao tác vào audit log.
- **UJ-6. Quản trị Dũng.** Tạo user admin, gán vai, khóa user admin, xem audit log.

**R2–R4 (khung)**
- **UJ-7. An chuyển liên ngân hàng qua web KH** (R2): tra tên người nhận qua NAPAS mock → nhập số tiền → trên ngưỡng thì OTP →
  tính phí → tạm giữ tiền + phí → NAPAS mock xử lý → `succeeded`/`failed`/`unknown` (timeout, tra soát).
- **UJ-8. Bình (GDV) điều chỉnh số dư, Chi (KSV) duyệt** (R2): maker ≠ checker; chưa duyệt thì chưa hạch toán.
- **UJ-9. Quản trị cấu hình hạn mức, ngưỡng OTP, bảng phí** (R2): thay đổi cấu hình cũng qua maker-checker.
- **UJ-10. Kế toán Em đối soát + chạy EOD** (R3): nhận file đối soát NAPAS mock → ra danh sách khớp / lệch → xử lý lệch →
  chạy EOD (khóa ngày kế toán, dồn tích lãi, báo cáo cân đối).
- **UJ-11. An gửi tiết kiệm 12 tháng, tất toán** (R4): mở sổ từ TK thanh toán → lãi dồn tích hằng ngày qua EOD → đến hạn tất toán
  (gốc + lãi vào TK) hoặc trước hạn (toàn bộ thời gian tính lãi không kỳ hạn, đảo lãi đã dồn tích).

## 3. Glossary
Xem `docs/foundation/glossary.md`. Không dùng từ đồng nghĩa ngoài danh sách đó.

## 4. Features

### 4.1 Khách hàng & eKYC (R1)
Realizes UJ-1, UJ-5.

#### FR-1: Đăng ký khách hàng
Người dùng có thể đăng ký bằng SĐT, CCCD, ảnh giấy tờ + khuôn mặt, mật khẩu.
- SĐT và số CCCD là duy nhất; trùng → lỗi 409, không tạo bản ghi.
- Mật khẩu theo chính sách (≥ 10 ký tự, không nằm trong danh sách mật khẩu phổ biến), lưu bằng hàm băm chậm (argon2id/bcrypt).
- Ảnh không lưu trong DB nghiệp vụ; chỉ lưu tham chiếu tới kho object.

#### FR-2: eKYC
Hệ thống gửi hồ sơ tới eKYC mock và xử lý 4 kết quả: đạt / nghi ngờ / không đạt / timeout.
- Đạt → Khách hàng `active` và mở TK mặc định (FR-6).
- Nghi ngờ → hồ sơ `pending_review`, vào hàng chờ GDV.
- Không đạt → `rejected` kèm mã lý do.
- Timeout → `pending_ekyc`, tự hỏi lại với backoff, tối đa 3 lần gọi (1 + 2 lần hỏi lại); timeout ở lần thứ 3 → `pending_review` (hàng chờ GDV).

#### FR-3: GDV duyệt eKYC
GDV có thể duyệt / từ chối hồ sơ `pending_review` kèm lý do. Ghi audit log.

#### FR-4: Đăng nhập khách hàng
Khách hàng đăng nhập bằng SĐT + mật khẩu → access JWT 15 phút + refresh token (xoay vòng, thu hồi được).
- Sai 5 lần liên tiếp → khóa đăng nhập 15 phút.
- Đăng xuất thu hồi refresh token.
- Trạng thái được đăng nhập: `active`, `pending_ekyc`, `pending_review` (chưa active chỉ xem trạng thái hồ sơ); `rejected`/`expired` bị chặn. (bổ sung 2026-10-05 từ architecture)

### 4.2 Tài khoản (R1)
Realizes UJ-1, UJ-5.

#### FR-5: Số tài khoản
Số TK duy nhất, có chữ số kiểm tra để bắt lỗi gõ. Định dạng: 12 chữ số, chữ số cuối là Luhn check digit.

#### FR-6: Mở tài khoản
Khách hàng `active` có thể mở TK thanh toán VND; tối đa 5 TK; TK đầu tiên là mặc định; đổi được TK mặc định.

#### FR-7: Khóa / mở khóa
GDV có thể đặt TK ở `debit_blocked` (không ghi Nợ, vẫn nhận tiền) hoặc `blocked` (chặn hai chiều), và mở lại, kèm lý do.
- Giao dịch ghi Nợ vào TK `debit_blocked`/`blocked` bị từ chối; ghi Có vào `blocked` bị từ chối.
- Ghi audit log. (R2: thao tác này qua maker-checker.)

#### FR-8: Đóng tài khoản
Khách hàng có thể đóng TK khi số dư = 0, không có tạm giữ và không có giao dịch `pending`/`unknown` liên quan; không đóng được TK mặc định khi còn TK khác (phải đổi mặc định trước).

#### FR-9: Số dư và sao kê
Khách hàng xem số dư sổ sách, số dư khả dụng, và sao kê theo khoảng thời gian (phân trang, mỗi dòng có số dư sau giao dịch).
- Số dư bằng tổng bút toán của TK (kiểm chứng được bằng truy vấn đối chiếu).

### 4.3 Sổ cái kép (R1)
Realizes UJ-2, UJ-3, UJ-4.

#### FR-10: Giao dịch kế toán cân
Mọi biến động tiền ghi bằng giao dịch kế toán gồm ≥ 2 bút toán, tổng Nợ = tổng Có, ghi nguyên tử.
- Không có API sửa/xóa bút toán; sai thì ghi giao dịch đảo.
- Bút toán bất biến (append-only).

#### FR-11: Tài khoản nội bộ
Hệ thống có tài khoản sổ cái nội bộ: trung gian cổng nạp, trung gian cổng rút (R1); thu phí, trung gian NAPAS (R2); chi lãi, lãi phải trả (R4).

#### FR-12: Tạm giữ
Hệ thống có thể tạm giữ một phần số dư; số dư khả dụng = số dư − tổng tạm giữ; tạm giữ được giải phóng hoặc chuyển thành hạch toán.

#### FR-13: Bất biến
Có job kiểm bất biến định kỳ: tổng Nợ = tổng Có toàn hệ thống; số dư mỗi TK = tổng bút toán; không TK khách hàng nào âm.
Vi phạm → alert mức critical.

### 4.4 Dòng tiền (R1)

#### FR-14: Idempotency
Mọi API tạo giao dịch yêu cầu idempotency key. Cùng key + cùng nội dung → trả kết quả cũ; cùng key + khác nội dung → 422.
Key được giữ ≥ 24 giờ.

#### FR-15: Nạp tiền
Khách hàng tạo yêu cầu nạp qua cổng nạp mock. Callback thành công → hạch toán (Nợ trung gian cổng nạp / Có TK KH).
- Callback trùng → bỏ qua, không ghi đôi. Callback có chữ ký; sai chữ ký → từ chối.
- Không có callback sau thời hạn → `unknown`, tra soát (FR-19).

#### FR-16: Chuyển nội bộ
Khách hàng chuyển từ TK của mình tới TK khác trong banking-go. Đồng bộ: kiểm trạng thái hai TK + số dư khả dụng → hạch toán → `succeeded`.
- Số tiền > 0, số nguyên VND. Không chuyển cho chính TK nguồn.
- 100 request đồng thời từ một TK → không âm số dư, tổng tiền không đổi.

#### FR-17: Rút tiền
Tạm giữ → gọi cổng rút mock → thành công: hạch toán (Nợ TK KH / Có trung gian cổng rút) + giải phóng tạm giữ; thất bại: hủy tạm giữ, `failed`; timeout: `unknown`.

#### FR-18: Trạng thái giao dịch
Giao dịch có trạng thái `pending` / `succeeded` / `failed` / `unknown`; chỉ chuyển theo máy trạng thái đã định
(xem business-flows.md); `succeeded` và `failed` là trạng thái cuối.

#### FR-19: Tra soát giao dịch unknown
Job tự hỏi lại đối tác cho giao dịch `unknown` theo lịch backoff; GDV có thể bấm tra soát lại. Kết quả về → chuyển trạng thái cuối và hạch toán/hủy tạm giữ tương ứng.

### 4.5 Admin & bảo mật (R1)
Realizes UJ-5, UJ-6.

#### FR-20: Đăng nhập admin
Mật khẩu + TOTP bắt buộc; phiên hết hạn sau 30 phút không thao tác. Tách hoàn toàn với auth KH.

#### FR-21: Vai và quyền
Vai: GDV/vận hành, KSV, kế toán/đối soát, quản trị. Mỗi API admin kiểm quyền theo vai; mặc định từ chối.

#### FR-22: Quản lý user admin
Quản trị tạo/khóa user admin, gán vai. Không ai tự gán vai cho chính mình.

#### FR-23: Audit log
Mọi thao tác admin và sự kiện bảo mật (đăng nhập, sai mật khẩu, đổi quyền) ghi audit log append-only: ai, khi nào, IP, hành động,
đối tượng, trước/sau. Quản trị xem và lọc được; KSV xem được (bổ sung 2026-10-06). Không lộ mật khẩu/token/ảnh trong log.

#### FR-24: Tra cứu
GDV tra cứu khách hàng theo SĐT/CCCD/số TK, xem TK, sao kê, giao dịch `unknown`.

### 4.6 R2 — Liên ngân hàng, OTP, hạn mức, phí, maker-checker, web KH (khung)
Realizes UJ-7, UJ-8, UJ-9. Gồm: tra tên người nhận qua NAPAS mock; chuyển liên NH bất đồng bộ có tạm giữ; OTP khi vượt ngưỡng;
hạn mức theo giao dịch/ngày; bảng phí cấu hình được, hạch toán vào TK thu phí; maker-checker cho điều chỉnh số dư, khóa/mở TK,
đổi cấu hình; web khách hàng (đăng nhập, số dư, sao kê, chuyển tiền, nạp/rút). FR chi tiết khi tới R2.

### 4.7 R3 — Đối soát, EOD, báo cáo (khung)
Realizes UJ-10. Gồm: nhận file đối soát NAPAS mock, so khớp, danh sách lệch và cách xử lý; EOD (khóa ngày kế toán, dồn tích lãi,
báo cáo cân đối); báo cáo kế toán cho vai kế toán. Load test 500 TPS + failover test.

### 4.8 R4 — Tiết kiệm (khung)
Realizes UJ-11. Gồm: sản phẩm tiết kiệm (kỳ hạn, lãi suất cấu hình được); mở sổ từ TK thanh toán; lãi dồn tích hằng ngày qua EOD;
tất toán đúng hạn (gốc + lãi) và trước hạn (lãi không kỳ hạn cho toàn bộ thời gian, đảo lãi đã dồn tích).
Đến hạn mà KH không tất toán → tự tất toán về TK mặc định, không tự tái tục.

## 5. Non-goals
Thẻ; cho vay/tín dụng; đa tiền tệ/FX; mobile app; KH doanh nghiệp; đối tác thật; cam kết tuân thủ pháp lý.

## 6. Phạm vi theo release
| Release | Feature | Ghi chú |
|---|---|---|
| R1 | 4.1–4.5 + CI/CD, observability, chaos test cơ bản | Chưa có web KH (KH dùng API); load test đo baseline |
| R2 | 4.6 | Maker-checker phủ lại các thao tác admin R1 |
| R3 | 4.7 | 500 TPS + failover bắt buộc |
| R4 | 4.8 | |

## 7. Success metrics
- **SM-1** Đúng tiền: chaos test trong CI → 0 lệch, 0 ghi đôi; job bất biến (FR-13) không vi phạm trên staging. Validates FR-10, FR-12–FR-17.
- **SM-2** Hiệu năng: chuyển nội bộ 500 TPS, p95 < 200ms (k6) — bắt buộc từ R3. Validates FR-16.
- **SM-3** Sẵn sàng: SLO 99.9%; failover DB primary dưới tải → không mất giao dịch đã `succeeded`, phục hồi < 1 phút — từ R3.
- **SM-4** Bảo mật: không lỗi Critical/High theo OWASP Top 10 (scan + review); 100% thao tác admin có audit log. Validates FR-20–FR-23.
- **SM-5** Portfolio: mỗi release có demo E2E trên staging ≤ 5 phút.
- **SM-C1** (không tối ưu) Số feature: không thêm nghiệp vụ ngoài phạm vi để "trông đầy đủ" — đi ngược SM-1/SM-4.

## 8. Open questions
1. Hạn mức và ngưỡng OTP mặc định (R2) — chốt khi /brainstorm R2.
2. Định dạng file đối soát NAPAS mock (R3).
3. Lãi suất mặc định và cách làm tròn tiền lãi (R4).

## 9. Assumptions index
Tất cả giả định dưới đây đã được user xác nhận ngày 2026-10-05.
- FR-2: eKYC tối đa 3 lần gọi (1 + 2 lần hỏi lại).
- FR-4: khóa đăng nhập 15 phút sau 5 lần sai.
- FR-5: số TK 12 chữ số, chữ số kiểm tra Luhn.
- FR-14: giữ idempotency key ≥ 24 giờ.
- FR-20: phiên admin hết hạn sau 30 phút không thao tác.
- 4.8: đến hạn tự tất toán về TK mặc định, không tự tái tục.
