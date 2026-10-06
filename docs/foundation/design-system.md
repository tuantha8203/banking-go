# Design system — banking-go

> Bản gộp ngắn. Chi tiết đầy đủ (token YAML, mọi pattern, key flows):
> `_bmad/planning-artifacts/ux-designs/ux-banking-go-2026-10-05/DESIGN.md` (giao diện) và `EXPERIENCE.md` (hành vi).
> Mock tham chiếu: cùng thư mục, `mockups/`. Spine thắng khi mâu thuẫn với mock.

## Nền tảng
- Ant Design 6 cho cả web KH và web admin; theme qua `ConfigProvider` (light `defaultAlgorithm`, dark `darkAlgorithm` + override).
- Web KH: responsive, mobile web là chính (< 768px bottom tab; ≥ 768px top nav, nội dung ≤ 960px). Web KH có từ R2; R1 KH dùng API.
- Web admin: desktop ≥ 1280px, sider 232px, mật độ AntD mặc định; mỗi vai chỉ thấy mục có quyền.
- i18n VI + EN từ đầu, không hard-code chuỗi. Sáng/tối theo OS, đổi được. WCAG 2.1 AA.
- Font: Inter (self-host), số tiền `tabular-nums`; admin dùng mono cho mã giao dịch/số tài khoản.

## Token màu — "Hải quân Định chế"
| Vai | Light | Dark |
|---|---|---|
| primary / hover | `#1F3A68` / `#2C4F8A` | `#4170C0` / `#3866B2` (hover tối hơn để giữ AA) |
| surface base / elevated | `#F3F5F9` / `#FFFFFF` | `#0C1424` / `#142038` |
| border | `#D3DAE6` | `#283851` |
| text / secondary | `#13203A` / `#4A5772` | `#E6ECF5` / `#A4B0C6` |
| success · warning · error · info | `#1D7A4C` · `#8F5B00` · `#B42318` · `#1F5FAD` | `#5FC290` · `#E5B045` · `#F08A7E` · `#7FB0EE` |
| money-in / money-out | `#1D7A4C` / `#A0392A` | `#5FC290` / `#F0A08E` |

AntD: `colorPrimary`, `colorSuccess`, `colorWarning`, `colorError`, `colorInfo`, `colorBgBase`, `colorBgContainer`, `colorBorder`,
`colorTextBase`, `colorTextSecondary`, `borderRadius: 4`. Token riêng ngân hàng (`money-*`, `status-*`) đặt trong theme của app.

## Trạng thái
| Giao dịch | Màu | Chữ VI | Ghi chú |
|---|---|---|---|
| pending | info | Đang xử lý | icon đồng hồ |
| succeeded | success | Thành công | icon tích |
| failed | error | Thất bại | icon x |
| unknown | warning | Chưa rõ kết quả | icon hỏi, **viền đứt nét**; không bao giờ gộp vào pending |

Tài khoản: Hoạt động = success; Khóa ghi Nợ = warning, viền liền + icon khóa; Khóa toàn bộ = error.

## Quy tắc bắt buộc
- Số tiền: tabular, theo locale (VI `12.450.000 ₫`, EN `₫12,450,000`); đã hạch toán thì có `+`/`−` + màu money-in/out;
  số đề xuất/tạm giữ không dấu. Ô nhập tự chèn phân cách + đọc bằng chữ.
- Mỗi màn tối đa **một** nút primary. Thao tác hủy hoại: nút viền đỏ mở dialog; nút xác nhận màu error.
- Badge/tag luôn có icon + chữ, không chỉ dựa vào màu. Phẳng: viền thay bóng (trừ dialog/drawer/dropdown).
- Mọi giao dịch ghi Nợ của KH qua bước **Xác nhận** (Nhập → Xác nhận → Kết quả). Nút gửi khóa sau khi bấm; một idempotency key mỗi lần xác nhận.
- Unknown với KH (rút/chuyển): "Ngân hàng đang xác minh với đối tác. Số tiền đang được tạm giữ, kết quả trong tối đa 30 phút.";
  nạp: "Khoản nạp đang được ngân hàng xác minh với đối tác, kết quả trong tối đa 30 phút." + timeline; tự cập nhật
  (polling 5s trong 2 phút, sau đó 30s).
- Admin: thao tác nhạy cảm qua dialog có tóm tắt trước → sau + chọn mã lý do + ghi chú ≥ 10 ký tự; không thao tác hàng loạt; bộ lọc trên URL;
  chi tiết trong drawer (`detail=` trên URL).
- Voice KH: lịch sự, ngắn, "Quý khách", không emoji. Admin: trung tính, đúng thuật ngữ glossary.
- Accessibility: focus rõ, dialog giữ focus, `aria-live` cho đổi trạng thái giao dịch, vùng chạm ≥ 44px, zoom 200%.

## Không làm
Gradient, ảnh nền, minh họa trang trí; màu đỏ cho tiền ra thông thường; nhiều nút primary trên một màn; ẩn `unknown` vào `pending`.
