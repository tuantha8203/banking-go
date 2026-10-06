# 0006. AuthN ở edge, AuthZ ở core, internal token ký riêng từng edge + mTLS

- Trạng thái: Accepted (2026-10-05)
- Liên quan: AD-10, AD-11, AD-19, AD-20, AD-21, AD-25

## Bối cảnh
Hai edge xác thực theo cách khác nhau (khách hàng: mật khẩu + JWT; nhân viên: session + TOTP). Core phải biết ai đang gọi để kiểm tra quyền và ownership,
ghi audit đúng actor. Reviewer gate chỉ ra rủi ro: edge bị chiếm hoặc lỗi có thể tự xưng actor không thuộc nó; IDOR trên tài nguyên khách hàng;
token bị phát lại sang RPC khác; credential không gắn được với customer của core.

## Các phương án đã cân nhắc
1. **Core tự xác thực token người dùng cuối** — core phải biết cả JWT khách hàng lẫn session admin, trộn hai miền danh tính vào core. Bị loại.
2. **Tin header danh tính chỉ nhờ mạng nội bộ / mTLS** — không chống được edge bị lỗi xưng actor khác. Bị loại.
3. **Một khóa ký chung cho mọi edge** — một edge lộ khóa là giả được nhân viên. Bị loại.
4. **AuthN ở edge, internal token EdDSA ký riêng từng edge, mTLS, AuthZ + ownership ở core** (chọn).

## Quyết định
- Edge xác thực rồi gọi core với `x-actor` = EdDSA JWT `exp` ≤ 60 s, `aud=core`, `kid`, `jti`, `rpc` (đúng gRPC method), `actor_type`, `sub`, `roles`,
  `session_id`, `client_ip` (chỉ từ forwarded header tin cậy của Gateway), `user_agent`, `request_id`. Kênh gRPC dùng mTLS (cert-manager internal CA).
- Mỗi edge một signing key; JWKS mount vào core dạng Secret, xoay khóa bằng `kid` chồng lấp. Core pin `kid → (issuer, actor types)`: public-api:
  `customer` (roles `[customer]`) và `anonymous` chỉ cho `RegisterCustomer` (`sub` = `registration_id`); admin-api chỉ `staff`. Actor `system:<job>` chỉ tồn tại in-process.
- **`customer_id` do core cấp** (UUIDv7) là danh tính khách hàng duy nhất; credential ở public-api khóa theo `customer_id`; `sub` = `customer_id`.
  Mọi use case kiểm `owner_customer_id == sub` trong UoW trước hiệu ứng; sai trả `not_found`. Lệnh tiền còn yêu cầu trạng thái `active`.
- Nhân viên: policy vai → quyền trong `pkg/authz` (default deny, test dạng bảng), admin-api dùng cho use case của mình, core dùng cho use case core.
  Khóa ký admin-api là secret Tier-0. Lệnh maker-checker còn cần approval proof (AD-20); step-up OTP là assertion riêng có `kid` public-api (AD-21).
- TLS công khai kết thúc ở Gateway (Traefik + cert-manager / ALB + ACM).

## Hệ quả
- Edge bị lỗi không thể xưng actor ngoài phạm vi `kid` của nó; token không dùng lại được cho RPC khác và hết hạn nhanh.
- Core là nơi duy nhất quyết định quyền cho dữ liệu core → một mô hình quyền, audit `denied` được ghi tại chỗ.
- Thêm vận hành: CA nội bộ, xoay khóa ký, JWKS Secret; clock skew giữa pod phải nhỏ so với 60 s.
- public-api phải giữ projection trạng thái khách hàng từ event để chặn login/refresh (AD-19); core vẫn kiểm `active` độc lập.
