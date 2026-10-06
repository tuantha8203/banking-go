---
title: "EXPERIENCE: banking-go"
status: final
created: 2026-10-05
updated: 2026-10-05
sources: [../../prds/prd-banking-go-2026-10-05/prd.md, ../../../../business-flows.md, DESIGN.md]
---

# EXPERIENCE — banking-go

## Foundation
- Hai bề mặt: **web KH** (responsive, mobile web là chính) và **web admin** (desktop ≥ 1280px).
- UI system: Ant Design 6; chỉ ghi phần khác biệt so với hành vi mặc định của AntD. Visual: `DESIGN.md`.
- Ngôn ngữ VI + EN từ đầu (mọi chuỗi qua i18n, không hard-code); chọn ngôn ngữ trong Cài đặt, nhớ theo tài khoản.
- Light/dark: theo hệ điều hành mặc định, đổi được trong Cài đặt.
- Release: R1 chỉ có web admin + API cho KH; web KH từ R2. Màn thuộc release sau được đánh dấu (Rn).

## Information Architecture

### Web KH
| Mục | Nội dung | Release |
|---|---|---|
| Tổng quan | Thẻ các tài khoản (số dư khả dụng, ẩn/hiện), giao dịch gần đây, lối tắt Chuyển tiền / Nạp / Rút | R2 |
| Chuyển tiền | Nội bộ + liên ngân hàng, 3 bước | R2 |
| Nạp / Rút | Qua cổng mock | R2 |
| Lịch sử & sao kê | Lọc theo tài khoản, khoảng thời gian, trạng thái; chi tiết giao dịch có timeline | R2 |
| Tiết kiệm | Danh sách sổ, mở sổ, tất toán | R4 |
| Cài đặt | Ngôn ngữ, giao diện sáng/tối, đổi mật khẩu, thiết bị đăng nhập | R2 |

Mobile (< 768px): bottom tab bar — Tổng quan · Chuyển tiền · Lịch sử · Tiết kiệm · Khác (Nạp/Rút, Cài đặt, Đăng xuất).
Trước R4, tab Tiết kiệm ẩn.

### Web admin (sider, mỗi vai chỉ thấy mục có quyền)
| Mục | Vai | Release |
|---|---|---|
| Tổng quan vận hành | tất cả | R1 |
| Khách hàng | GDV, KSV | R1 |
| Tài khoản | GDV, KSV, kế toán | R1 |
| Giao dịch (lọc `unknown`) | GDV, KSV, kế toán | R1 |
| Hàng chờ eKYC | GDV | R1 |
| Phê duyệt | KSV | R2 |
| Đối soát & EOD | kế toán | R3 |
| Cấu hình hạn mức / phí / sản phẩm | quản trị | R2 |
| Người dùng & vai | quản trị | R1 |
| Audit log | quản trị, KSV | R1 |

Đăng nhập / enrol TOTP / đổi mật khẩu (ngoài sider), R1.

Tổng quan vận hành: số giao dịch `unknown` (và cái lâu nhất), hồ sơ eKYC chờ duyệt, cảnh báo bất biến ledger, (R2) yêu cầu chờ duyệt.

## Voice and Tone
- KH: lịch sự, ngắn, xưng "Quý khách". Câu chủ động, nói việc cần làm: "Quý khách vui lòng kiểm tra lại số tài khoản."
  EN: lịch sự trung tính, "you". Không đùa, không emoji.
- Lỗi: nói chuyện gì xảy ra + làm gì tiếp; không đổ lỗi; không lộ chi tiết kỹ thuật. Kèm mã tham chiếu để tra cứu.
- Admin: trung tính, chính xác, dùng đúng thuật ngữ glossary ("khóa ghi Nợ", "tạm giữ", "tra soát").
- Số tiền trong chữ xác nhận: "Mười hai triệu bốn trăm năm mươi nghìn đồng" (VI) / "Twelve million four hundred fifty thousand dong" (EN).

## Component Patterns (hành vi)
| Pattern | Hành vi |
|---|---|
| Ô nhập số tiền | Chỉ nhận số; tự chèn phân cách theo locale khi gõ; dòng dưới đọc bằng chữ; báo ngay nếu vượt số dư khả dụng (R2: vượt hạn mức) |
| Ẩn/hiện số dư | Mặc định hiện; nhớ lựa chọn theo thiết bị; khi ẩn hiển thị "••••••" |
| Số tài khoản | Hiển thị nhóm 4 số; nút sao chép; nhập chấp nhận có/không dấu cách |
| Badge trạng thái | 4 trạng thái theo DESIGN; không bao giờ gộp `unknown` vào `pending` |
| Timeline giao dịch | Các mốc: tạo → (tạm giữ) → gửi đối tác → kết quả / chờ tra soát; mỗi mốc có giờ |
| Dialog thao tác nhạy cảm (admin) | Tóm tắt đối tượng + trạng thái trước → sau; bắt buộc chọn mã lý do + ghi chú ≥ 10 ký tự; nút xác nhận chỉ bật khi đủ; không có thao tác hàng loạt |
| Bảng admin | AntD Table, phân trang server, bộ lọc giữ trên URL (chia sẻ link được), cột số tiền căn phải |
| Tên người nhận (K1) | Sau khi nhập số TK: dấu tích + tên người nhận + "Quý khách vui lòng đối chiếu tên người nhận."; không tra được → lỗi tại ô |
| Bước chuyển tiền (K2) | AntD Steps (Nhập · Xác nhận · Kết quả); Segmented Nội bộ / Liên ngân hàng (R2); Alert màu `status-unknown-*` cho thông điệp unknown |
| Dấu số tiền (K3) | Số tiền đề xuất (Xác nhận) và số tiền đang tạm giữ: không dấu; giao dịch đã hạch toán: `+`/`−` + màu money-in/out |
| Phạm vi ẩn số dư (K4) | Chỉ che số dư khả dụng và sổ sách; số tiền từng giao dịch vẫn hiện |
| Đếm unknown trên menu (D1) | Mục Giao dịch có huy hiệu số giao dịch `unknown`, viền đứt nét |
| Breadcrumb (D2) | Giữ nguồn điều hướng (vd. Tổng quan vận hành → Giao dịch) |
| Bộ lọc tức thì (D3) | Lọc áp dụng ngay khi đổi, không có nút "Lọc"; trạng thái lọc trên URL |
| Drawer chi tiết (D4) | Chi tiết giao dịch mở trong drawer; URL thêm `detail=<mã>` để chia sẻ |
| Lịch sử tra soát (D5) | Bảng nhỏ các lần tra soát (tự động/tay, giờ, kết quả); mốc "Chờ tra soát" ghi giờ lần kế tiếp; có kết quả cuối → ẩn "Tra soát lại" |
| Nút thao tác hủy hoại (D7) | Nút mở dialog khóa/từ chối là nút viền đỏ (danger, không primary); nút xác nhận trong dialog dùng `error` |
| Lý do + audit (D8) | Bộ đếm "x / 10 tối thiểu", dòng "Đủ độ dài" khi đạt; thông báo thành công kèm dòng "ai · lúc nào · đã ghi audit log" |

## State Patterns
| Trạng thái | KH | Admin |
|---|---|---|
| Đang tải | Skeleton đúng hình khối, không spinner toàn trang | Skeleton bảng |
| Rỗng | Câu ngắn + hành động: "Quý khách chưa có giao dịch nào. Nạp tiền" | "Không có giao dịch phù hợp bộ lọc" + xóa lọc |
| Lỗi mạng | Banner + nút thử lại; dữ liệu cũ vẫn hiển thị kèm giờ cập nhật | Như KH |
| Giao dịch `pending` | "Đang xử lý" + timeline | Như KH + mã giao dịch |
| Giao dịch `unknown` | Rút/chuyển: "Ngân hàng đang xác minh với đối tác. Số tiền đang được tạm giữ, kết quả trong tối đa 30 phút." Nạp: "Khoản nạp đang được ngân hàng xác minh với đối tác, kết quả trong tối đa 30 phút." + timeline; tự cập nhật | Badge + thời gian đã chờ + nút "Tra soát lại" |
| Giao dịch `failed` | Lý do dễ hiểu + gợi ý; số tiền đã hoàn (nếu có tạm giữ) | Mã lý do kỹ thuật |
| Phiên hết hạn | Dialog đăng nhập lại, giữ dữ liệu form chưa gửi (trừ OTP) | Về trang đăng nhập, quay lại đúng trang cũ |

## Interaction Primitives
- **Chống bấm hai lần**: nút gửi giao dịch khóa ngay sau khi bấm; client tạo idempotency key một lần cho mỗi lần xác nhận, retry dùng lại key.
- **Tự cập nhật trạng thái**: màn kết quả/chi tiết giao dịch hỏi lại trạng thái định kỳ khi còn `pending`/`unknown`. Polling 5 giây trong 2 phút đầu, sau đó 30 giây.
- **Xác nhận trước khi ghi Nợ**: mọi giao dịch ghi Nợ của KH đi qua bước Xác nhận.
- **Bàn phím**: mọi thao tác dùng được bằng bàn phím; Enter gửi form; Esc đóng dialog (không gửi).

## Accessibility Floor (WCAG 2.1 AA)
- Tương phản theo DESIGN (cả dark). Không truyền đạt thông tin chỉ bằng màu (badge có chữ, số tiền có dấu).
- Focus nhìn thấy rõ; thứ tự tab theo thứ tự đọc; dialog giữ focus bên trong và trả focus khi đóng.
- Ô nhập có label thật; lỗi gắn với ô bằng `aria-describedby`; thay đổi trạng thái giao dịch thông báo qua `aria-live="polite"`.
- Vùng chạm ≥ 44×44px trên mobile. Hỗ trợ zoom 200% không vỡ bố cục.
- Số tiền đọc bằng chữ có sẵn cho screen reader.

## Responsive & Platform
- Web KH: < 768px một cột + bottom tab; ≥ 768px top nav, nội dung tối đa 960px.
- Admin: tối thiểu 1280px; dưới mức đó hiện thông báo "Vui lòng dùng màn hình rộng hơn".

## Key Flows

### KF-1. An chuyển 1 triệu cho Bình (BF-3, R2 web)
1. An mở tab **Chuyển tiền**, chọn TK nguồn (mặc định TK mặc định, hiện số dư khả dụng).
2. Nhập số tài khoản Bình → hệ thống hiện tên người nhận "NGUYEN VAN BINH" để An đối chiếu.
3. Nhập 1.000.000 → dòng dưới hiện "Một triệu đồng"; nội dung chuyển khoản tự gợi ý "AN chuyen tien".
4. **Xác nhận**: TK nguồn, người nhận, số tiền bằng số và bằng chữ, phí (R2), (R2) OTP nếu vượt ngưỡng → "Xác nhận chuyển".
5. **Climax — Kết quả**: "Thành công" + số tiền + mã giao dịch + giờ; nút "Chia sẻ biên lai" và "Về Tổng quan".
- *Ngoại lệ:* số dư không đủ → báo ngay ở bước 3. Mất mạng sau khi bấm → giữ màn chờ, retry cùng idempotency key, không tạo giao dịch thứ hai.

### KF-2. An rút tiền và gặp timeout (BF-4)
1–4 như KF-1 với cổng rút. 5. Kết quả **"Chưa rõ kết quả"** với thông điệp xác minh + số tiền đang tạm giữ + timeline.
6. **Climax**: vài phút sau màn tự cập nhật thành "Thành công" (hoặc "Thất bại — số tiền đã được hoàn vào tài khoản").

### KF-3. GDV Chi xử lý giao dịch unknown (BF-5, R1)
1. Chi đăng nhập (mật khẩu + TOTP) → **Tổng quan vận hành** thấy "3 giao dịch chưa rõ kết quả, lâu nhất 24 phút".
2. Bấm vào → **Giao dịch** đã lọc `unknown`, sắp theo thời gian chờ.
3. Mở chi tiết: timeline, mã đối tác, lịch sử tra soát tự động.
4. **Climax**: bấm "Tra soát lại" → kết quả về → badge đổi sang Thành công/Thất bại, dòng mới trong timeline, audit log ghi nhận.

### KF-4. GDV Chi khóa ghi Nợ tài khoản (BF-6, R1)
1. Tra cứu theo CCCD → mở **Tài khoản**.
2. "Khóa tài khoản" → dialog chọn mức (Khóa ghi Nợ / Khóa toàn bộ), tóm tắt "Hoạt động → Khóa ghi Nợ", chọn mã lý do + nhập ghi chú ≥ 10 ký tự.
3. **Climax**: xác nhận → trạng thái đổi, banner "Đã khóa ghi Nợ. Tài khoản vẫn nhận tiền đến." (R2: thành yêu cầu chờ KSV duyệt).

## Mockups
Spine thắng khi mâu thuẫn với mock (vd. mock có tab Tiết kiệm, spine ẩn tới R4).
- [Tổng quan KH (mobile, sáng/tối, ẩn số dư)](mockups/key-kh-tong-quan.html) — IA Web KH, Ẩn/hiện số dư, Badge
- [Chuyển tiền 3 bước + unknown + lỗi số dư](mockups/key-kh-chuyen-tien.html) — KF-1, KF-2, Ô nhập số tiền, K1–K3
- [Admin Giao dịch unknown + drawer + tra soát](mockups/key-admin-giao-dich.html) — KF-3, D1–D5
- [Admin Khóa tài khoản](mockups/key-admin-khoa-tk.html) — KF-4, Dialog thao tác nhạy cảm, D6–D8
