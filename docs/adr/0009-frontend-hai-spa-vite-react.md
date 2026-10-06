# 0009. Frontend: 2 SPA Vite + React 19 + Ant Design 6, monorepo pnpm

- Trạng thái: Accepted (2026-10-05)
- Liên quan: AD-2, AD-9, AD-14

## Bối cảnh
Có hai giao diện: internet banking cho khách hàng và web admin cho GDV/KSV/kế toán/quản trị. Hai bên gọi hai edge khác nhau (public-api, admin-api) với
cơ chế đăng nhập khác nhau. Không cần SEO hay render phía server; ưu tiên đơn giản khi deploy dạng static trong cluster. design-system.md chọn Ant Design;
bản hiện hành là v6. Backend trả `code` + params, SPA tự dịch (i18n).

## Các phương án đã cân nhắc
1. **Next.js (SSR)** — thêm server Node cần vận hành và một lớp BFF mới, không cần SEO. Bị loại.
2. **Một SPA chung có phân vai** — trộn bề mặt tấn công khách hàng và admin, bundle admin lộ ra internet. Bị loại.
3. **Client API viết tay** — dễ lệch hợp đồng. Bị loại.
4. **Hai SPA Vite + React 19 + Ant Design 6 trong monorepo pnpm, client sinh từ OpenAPI** (chọn).

## Quyết định
- `apps/web-customer`, `apps/web-admin` dùng Vite 8, React 19, Ant Design 6, TanStack Query 5, i18next.
- `packages/`: `theme`, `i18n`, `api-client-public`, `api-client-admin`; client sinh bằng openapi-typescript + openapi-fetch từ file OpenAPI mà edge commit.
- Node 24 LTS, pnpm 12.9 (`packageManager` trong `package.json` gốc).
- SPA chỉ hiển thị giá trị tiền core trả về, định dạng ở SPA; không tự tính phí, hạn mức hay quyết định OTP.
- Mỗi SPA là image web server tĩnh trong cluster, đọc API base URL từ file config runtime (cùng image cho hai môi trường).

## Hệ quả
- Đổi API ở edge → regenerate client → lỗi kiểu xuất hiện ngay ở build SPA.
- Theme và i18n dùng chung, giữ nhất quán giao diện hai app.
- Cách lưu token SPA, CSRF/CORS và cookie admin còn hoãn tới security conventions trước khi build public-api R1.
- Phiên bản Ant Design trong design-system.md (đã chốt: Ant Design 6 — `design-system.md` § Nền tảng).
