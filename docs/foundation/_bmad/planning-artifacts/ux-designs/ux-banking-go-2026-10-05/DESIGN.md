---
title: "DESIGN: banking-go"
status: final
created: 2026-10-05
updated: 2026-10-05
sources: [../../prds/prd-banking-go-2026-10-05/prd.md, ../../../../business-flows.md]
name: banking-go
description: Hệ thống thị giác "Hải quân Định chế" cho web khách hàng và web admin của banking-go, dựng trên Ant Design 6.
colors:
  primary: '#1F3A68'
  primary-hover: '#2C4F8A'
  on-primary: '#FFFFFF'
  surface-base: '#F3F5F9'
  surface-elevated: '#FFFFFF'
  border: '#D3DAE6'
  text: '#13203A'
  text-secondary: '#4A5772'
  success: '#1D7A4C'
  warning: '#8F5B00'
  error: '#B42318'
  info: '#1F5FAD'
  money-in: '#1D7A4C'
  money-out: '#A0392A'
  status-pending-bg: '#E9EFF7'
  status-pending-fg: '#1F5FAD'
  status-pending-border: '#9AB7DA'
  status-succeeded-bg: '#E8F2ED'
  status-succeeded-fg: '#1D7A4C'
  status-succeeded-border: '#99C3AE'
  status-failed-bg: '#F8E9E8'
  status-failed-fg: '#B42318'
  status-failed-border: '#DD9C97'
  status-unknown-bg: '#F4EFE6'
  status-unknown-fg: '#8F5B00'
  status-unknown-border: '#CDB58C'
  primary-dark: '#4170C0'
  primary-hover-dark: '#3866B2'
  on-primary-dark: '#FFFFFF'
  surface-base-dark: '#0C1424'
  surface-elevated-dark: '#142038'
  border-dark: '#283851'
  text-dark: '#E6ECF5'
  text-secondary-dark: '#A4B0C6'
  success-dark: '#5FC290'
  warning-dark: '#E5B045'
  error-dark: '#F08A7E'
  info-dark: '#7FB0EE'
  money-in-dark: '#5FC290'
  money-out-dark: '#F0A08E'
  status-pending-bg-dark: '#253755'
  status-pending-fg-dark: '#7FB0EE'
  status-pending-border-dark: '#44618A'
  status-succeeded-bg-dark: '#203A46'
  status-succeeded-fg-dark: '#5FC290'
  status-succeeded-border-dark: '#366960'
  status-failed-bg-dark: '#373143'
  status-failed-fg-dark: '#F08A7E'
  status-failed-border-dark: '#775058'
  status-unknown-bg-dark: '#35373A'
  status-unknown-fg-dark: '#E5B045'
  status-unknown-border-dark: '#72613E'
typography:
  font-family: { fontFamily: "Inter, -apple-system, 'Segoe UI', Roboto, sans-serif" }
  amount-hero: { fontSize: 32px, fontWeight: 600, lineHeight: 1.2, note: 'font-variant-numeric: tabular-nums' }
  amount: { fontSize: 16px, fontWeight: 600, note: 'tabular-nums' }
  heading-1: { fontSize: 24px, fontWeight: 600, lineHeight: 1.3 }
  heading-2: { fontSize: 20px, fontWeight: 600, lineHeight: 1.35 }
  body: { fontSize: 14px, fontWeight: 400, lineHeight: 1.57, note: 'AntD fontSize mặc định' }
  body-mobile: { fontSize: 16px, fontWeight: 400, lineHeight: 1.5 }
  caption: { fontSize: 12px, fontWeight: 400, lineHeight: 1.5 }
  mono: { fontFamily: "'JetBrains Mono', ui-monospace, monospace", fontSize: 13px, note: 'mã giao dịch, số tài khoản trong admin' }
rounded:
  DEFAULT: 4px
  sm: 2px
  lg: 8px
  full: 9999px
spacing:
  note: 'Dùng thang AntD (4px base): 4, 8, 12, 16, 24, 32, 48'
  page-margin-mobile: 16px
  page-margin-desktop: 24px
  admin-sider-width: 232px
components:
  button-primary: { background: '{colors.primary}', hover: '{colors.primary-hover}', text: '{colors.on-primary}', rounded: '{rounded.DEFAULT}' }
  account-card: { background: '{colors.surface-elevated}', border: '{colors.border}', amount: '{typography.amount-hero}', rounded: '{rounded.lg}' }
  status-badge: { rounded: '{rounded.sm}', border: 'solid 1px; unknown: dashed 1px', note: 'luôn icon + chữ' }
  amount-text: { in: '{colors.money-in}', out: '{colors.money-out}', typography: '{typography.amount}' }
---

# DESIGN — banking-go

## Brand & Style
"Hải quân Định chế": vững chãi, chuẩn mực, như sảnh giao dịch của một ngân hàng lâu đời. Ít trang trí, không gradient, không minh họa
trang trí; con số là nhân vật chính. Cùng một hệ token cho web KH và web admin; admin chỉ khác ở mật độ và bố cục.
Nền tảng: Ant Design 6 qua `ConfigProvider` (light: `defaultAlgorithm`, dark: `darkAlgorithm` + override token `*-dark`).
Bản gốc so sánh: [mockups/color-themes-1.html](mockups/color-themes-1.html) (biến thể 1). Mock màn hình: xem EXPERIENCE.md § Mockups.

## Colors
- `{colors.primary}` — hành động chính duy nhất trên mỗi màn (Chuyển tiền, Xác nhận). Không dùng cho trang trí hay nền lớn.
- `{colors.surface-base}` / `{colors.surface-elevated}` — nền trang / thẻ, bảng, dialog.
- `{colors.money-in}` / `{colors.money-out}` — chỉ cho số tiền vào/ra; luôn kèm dấu `+` / `−`, không dựa vào màu.
- `status-*` — badge 4 trạng thái giao dịch: pending = info, succeeded = success, failed = error, unknown = warning.
- `error` chỉ cho lỗi và trạng thái thất bại, không dùng cho số tiền ra.
- Dark mode: token hậu tố `-dark`. Hover của primary ở dark **tối hơn** base để giữ chữ trắng ≥ 4.5:1.
- Mọi cặp chữ/nền đạt WCAG 2.1 AA (chữ thường ≥ 4.5:1, primary vs surface ≥ 3:1).

## Typography
Inter, self-host. Số tiền luôn `tabular-nums` để cột thẳng hàng. `{typography.amount-hero}` cho số dư trên thẻ tài khoản;
`{typography.amount}` cho số tiền trong danh sách. Admin dùng `{typography.mono}` cho mã giao dịch và số tài khoản.
Web KH trên mobile dùng `{typography.body-mobile}` (16px, tránh iOS tự zoom ô nhập).

## Layout & Spacing
Thang 4px của AntD. Web KH: một cột, lề `{spacing.page-margin-mobile}`; ≥ 768px dùng khung nội dung tối đa 960px, giữa màn.
Bottom tab bar trên mobile (< 768px), top nav trên desktop. Admin: desktop ≥ 1280px, `Layout` có sider `{spacing.admin-sider-width}`,
nội dung lề `{spacing.page-margin-desktop}`, mật độ AntD mặc định.

## Elevation & Depth
Phẳng. Thẻ và bảng phân tầng bằng nền `surface-elevated` + viền `border`, không đổ bóng. Chỉ dialog/drawer/dropdown có bóng mặc định AntD.

## Shapes
Bo `{rounded.DEFAULT}` cho nút, ô nhập, bảng; `{rounded.lg}` cho thẻ tài khoản; `{rounded.sm}` cho badge. Không dùng nút tròn hoàn toàn trừ icon button.

## Components
- **Nút chính**: `{components.button-primary}`; mỗi màn tối đa một nút chính.
- **Thẻ tài khoản**: tên + số TK (nhóm 4 số), số dư khả dụng `amount-hero`, nút ẩn/hiện số dư, số dư sổ sách ở dòng phụ.
- **Badge trạng thái**: nền/viền/chữ `status-*`; icon (đồng hồ / dấu tích / dấu x / dấu hỏi) + chữ; unknown viền đứt nét.
- **Số tiền**: `{components.amount-text}`; dấu `+`/`−` bắt buộc; đơn vị theo locale.
- **Tag trạng thái tài khoản (D6)**: Hoạt động = success; Khóa ghi Nợ = chữ warning trên nền `status-unknown-bg`, viền **liền** + icon khóa (phân biệt với unknown); Khóa toàn bộ = error. Khác badge giao dịch.
- **Dialog thao tác nhạy cảm (admin)**: tiêu đề hành động, tóm tắt trước/sau, bắt buộc chọn mã lý do + ghi chú ≥ 10 ký tự, nút xác nhận dùng `error` nếu là khóa/từ chối.

## Do's and Don'ts
- Do: số tiền tabular, có dấu, đúng locale. Do: badge luôn có chữ. Do: kiểm tương phản cả light và dark.
- Don't: dùng màu đỏ cho tiền ra thông thường (dùng `money-out`). Don't: nhiều nút primary trên một màn.
- Don't: gradient, ảnh nền, minh họa trang trí. Don't: ẩn trạng thái `unknown` vào `pending`.
