# Public API (R1) — banking-go

> REST của **public-api** cho khách hàng. Quy ước chung, mã lỗi: [README.md](README.md). RPC core: [grpc.md](grpc.md).
> OpenAPI máy đọc: `services/public-api/api/openapi/public-api.yaml` (Huma, generate + commit).

## Xác thực
| Scheme | Dùng cho | Ghi chú |
|---|---|---|
| none | Đăng ký, login, refresh, logout | Rate limit theo IP (+ SĐT với login) |
| `bearer` | Còn lại | Access JWT EdDSA, `exp` 15 phút, `sub` = `customer_id`; status projection phải cho đăng nhập (AD-19) |

- Refresh token trả trong JSON body (R1 chưa có web KH) `[A-38]`; cách lưu ở SPA/CSRF quyết ở security conventions (spine Deferred).
- KH chưa `active` chỉ gọi được `GET /v1/me/onboarding`; endpoint khác core trả `customer_not_active`.
- public-api ký internal token `x-actor` (`actor_type=customer`, `rpc` = method) cho mỗi lời gọi core (AD-10).

## Danh mục
| # | Method | Path | Auth | Idem-Key | Core RPC | FR / BF |
|---|---|---|---|---|---|---|
| P-1 | POST | `/v1/registrations` | none | **bắt buộc** | `CustomerService.RegisterCustomer` | FR-1, FR-2 / BF-1 |
| P-2 | GET | `/v1/me/onboarding` | bearer (mọi trạng thái đăng nhập được) | — | `CustomerService.GetOnboardingStatus` | FR-2 / BF-1 |
| P-3 | POST | `/v1/sessions` | none | — | — (local) | FR-4 / BF-7 |
| P-4 | POST | `/v1/sessions/refresh` | refresh token | — | — | FR-4 / BF-7 |
| P-5 | POST | `/v1/sessions/logout` | refresh token | — | — | FR-4 / BF-7 |
| P-6 | GET | `/v1/accounts` | bearer | — | `AccountService.ListAccounts` | FR-6, FR-9 |
| P-7 | POST | `/v1/accounts` | bearer | **bắt buộc** | `AccountService.OpenAccount` | FR-5, FR-6 |
| P-8 | GET | `/v1/accounts/{accountId}` | bearer | — | `AccountService.GetAccount` | FR-9 |
| P-9 | POST | `/v1/accounts/{accountId}/default` | bearer | **bắt buộc** | `AccountService.SetDefaultAccount` | FR-6 |
| P-10 | POST | `/v1/accounts/{accountId}/close` | bearer | **bắt buộc** | `AccountService.CloseAccount` | FR-8 / BF-6 |
| P-11 | GET | `/v1/accounts/{accountId}/balance` | bearer | — | `AccountService.GetBalance` | FR-9, FR-12 |
| P-12 | GET | `/v1/accounts/{accountId}/statement` | bearer | — | `AccountService.GetStatement` | FR-9 |
| P-13 | POST | `/v1/deposits` | bearer | **bắt buộc** | `PaymentService.CreateDeposit` | FR-14, FR-15 / BF-2 |
| P-14 | POST | `/v1/internal-transfers` | bearer | **bắt buộc** | `PaymentService.CreateInternalTransfer` | FR-14, FR-16 / BF-3 |
| P-15 | POST | `/v1/withdrawals` | bearer | **bắt buộc** | `PaymentService.CreateWithdrawal` | FR-14, FR-17 / BF-4 |
| P-16 | GET | `/v1/transactions/{transactionId}` | bearer | — | `PaymentService.GetTransaction` | FR-18, FR-19 |

Mọi endpoint còn có lỗi chung: `validation_failed`, `unauthenticated`, `rate_limited`, `resource_busy`, `service_unavailable`, `internal_error`; endpoint có Idem-Key thêm `idempotency_key_required`, `idempotency_in_progress`, `idempotency_conflict`.

## Resource dùng chung
**Account**
```json
{ "accountId": "uuid", "accountNumber": "012345678903", "status": "active|debit_blocked|blocked|closed",
  "isDefault": true, "currency": "VND", "balance": 5000000, "availableBalance": 3000000, "openedAt": "RFC3339", "closedAt": null }
```
**Transaction**
```json
{ "transactionId": "uuid", "kind": "deposit|withdrawal|internal_transfer", "status": "pending|succeeded|failed|unknown",
  "direction": "outgoing|incoming", "amount": 1000000, "currency": "VND", "accountId": "uuid",
  "counterpartyAccountNumberMasked": "********8903", "description": "string|null", "failureCode": "string|null",
  "businessDate": "YYYY-MM-DD|null", "createdAt": "RFC3339", "finalizedAt": "RFC3339|null",
  "timeline": [ { "status": "pending", "at": "RFC3339", "reasonCode": null } ] }
```
`direction`/`accountId` tính theo người xem: chủ TK nguồn thấy `outgoing`, chủ TK đích thấy `incoming` `[A-39]`. `timeline` chỉ có ở P-16.

## Chi tiết

### P-1 `POST /v1/registrations`
- Body `multipart/form-data`: `phone`, `nationalId`, `fullName` `[A-7]`, `password`, `idFront`, `idBack`, `selfie` (file).
- public-api: kiểm chính sách mật khẩu → argon2id → upload `kyc/<registration_id>/…` (write-only) → `RegisterCustomer` (key `reg:<Idempotency-Key>`) → insert credential theo `customer_id` + outbox `credential.created` (AD-19).
- `202` `{ "customerId", "status": "pending_ekyc" }`. Retry cùng key → replay cùng `customerId`.
- Đăng ký lại cùng SĐT + CCCD trong 24 h khi KH cũ chưa có credential → trả lại `customerId` cũ (AD-19).
- Lỗi: `weak_password`, `kyc_image_invalid`, `phone_already_registered`, `national_id_already_registered`.

### P-2 `GET /v1/me/onboarding`
- `200` `{ "customerId", "status": "pending_ekyc|pending_review|active", "reasonCode": null, "updatedAt" }`.
- Đọc từ core (nguồn thật), không từ projection `[A-40]`.

### P-3 `POST /v1/sessions` (login)
- Body `{ "phone", "password" }`; header tùy chọn `X-Device-Id` `[A-23]`.
- `200` `{ "accessToken", "tokenType": "Bearer", "expiresIn": 900, "refreshToken", "refreshExpiresIn": 604800, "customerStatus" }`.
- Lỗi: `invalid_credentials` (cũng trả khi projection chưa có SĐT), `login_locked`, `customer_login_not_allowed`.
- Mọi lần đúng/sai, lockout → audit event qua outbox (AD-11).

### P-4 `POST /v1/sessions/refresh`
- Body `{ "refreshToken" }` → `200` cặp token mới (xoay vòng; token cũ `rotated`).
- Lỗi: `invalid_refresh_token`, `refresh_token_reused`, `customer_login_not_allowed`.

### P-5 `POST /v1/sessions/logout`
- Body `{ "refreshToken" }` → `204`; revoke token đó (`revoke_reason = logout`). Token không hợp lệ cũng `204` (không lộ thông tin).

### P-6 `GET /v1/accounts`
- `200` `{ "items": [Account] }` (≤ 5 TK chưa đóng + TK đã đóng; không phân trang).
- Lỗi: `customer_not_active`.

### P-7 `POST /v1/accounts`
- Body `{}` → `201` Account (`balance: 0`; TK đầu tiên tự là mặc định).
- Lỗi: `customer_not_active`, `account_limit_reached`.

### P-8 `GET /v1/accounts/{accountId}` · P-11 `GET /v1/accounts/{accountId}/balance`
- P-8 `200` Account. P-11 `200` `{ "accountId", "balance", "availableBalance", "asOf" }`.
- Lỗi: `not_found` (không tồn tại hoặc không phải của mình), `customer_not_active`.

### P-9 `POST /v1/accounts/{accountId}/default`
- Body `{}` → `200` Account (`isDefault: true`); TK mặc định cũ thành `false` cùng UoW.
- Lỗi: `not_found`, `account_closed`, `customer_not_active`.

### P-10 `POST /v1/accounts/{accountId}/close`
- Body `{}` → `200` Account (`status: closed`).
- Chỉ đóng được TK `active`; TK `debit_blocked`/`blocked` → `invalid_status_transition` (phải mở khóa trước).
- Lỗi: `not_found`, `account_closed`, `invalid_status_transition`, `account_balance_not_zero`, `account_has_active_holds`, `account_has_inflight_transactions`, `default_account_close_forbidden`, `customer_not_active`.

### P-12 `GET /v1/accounts/{accountId}/statement`
- Query: `fromDate`, `toDate` (`YYYY-MM-DD`, Asia/Ho_Chi_Minh, tối đa 92 ngày `[A-41]`), `cursor`, `limit`.
- `200` `{ "items": [ { "seq", "transactionId", "kind", "side": "debit|credit", "amount", "balanceAfter", "createdAt", "businessDate", "description", "counterpartyAccountNumberMasked" } ], "nextCursor" }`.
- Sắp theo `seq` giảm dần (mới nhất trước) `[A-41]`; `balanceAfter` là giá trị lưu, không tính lại (FR-9).
- Lỗi: `not_found`, `customer_not_active`, `validation_failed` (khoảng ngày).

### P-13 `POST /v1/deposits`
- Body `{ "accountId", "amount", "description"? }` → `201` Transaction `pending` (hoặc `failed`).
- Cổng nạp mock tự xử lý theo chế độ cấu hình, không có bước redirect KH trong R1 `[A-42]`; client theo dõi bằng P-16.
- `failureCode` có thể: `account_blocked`, `account_closed`, `partner_rejected`. Lỗi: `not_found`, `amount_invalid`, `customer_not_active`.

### P-14 `POST /v1/internal-transfers`
- Body `{ "sourceAccountId", "destinationAccountNumber", "amount", "description"? }` → `201` Transaction `succeeded` hoặc `failed` (đồng bộ, không bao giờ `unknown`).
- `failureCode` có thể: `insufficient_funds`, `account_debit_blocked`, `account_blocked`, `account_closed`, `destination_account_unavailable`.
- Lỗi: `not_found` (TK nguồn), `account_number_invalid`, `account_number_not_found`, `same_account_transfer`, `amount_invalid`, `customer_not_active`.

### P-15 `POST /v1/withdrawals`
- Body `{ "accountId", "amount", "description"? }` → `201` Transaction `pending` (đã tạm giữ) hoặc `failed`.
- Đích rút là nguồn ngoài giả lập bởi cổng rút mock; R1 không nhận thông tin đích `[A-43]`.
- `failureCode` có thể: `insufficient_funds`, `account_debit_blocked`, `account_blocked`, `account_closed`, `partner_rejected`. Lỗi: như P-13.

### P-16 `GET /v1/transactions/{transactionId}`
- `200` Transaction kèm `timeline` (từ `payment.transaction_transitions`).
- Xem được nếu là chủ TK nguồn hoặc TK đích; khác → `not_found`.
- KH nhận `status: unknown` nguyên văn; SPA hiển thị "Chưa rõ kết quả" (không gộp vào `pending`, design-system); KH không thấy `partner_attempts`.

## R2 (bổ sung, chi tiết khi `/brainstorm` R2)
- `POST /v1/name-inquiries` — tra tên người nhận liên NH qua NAPAS mock (đồng bộ, rate limit + audit, trả tên đã mask).
- `POST /v1/payment-drafts` — tạo draft (liên NH / có phí, hạn mức): trả `fee`, `stepUpRequired`, `expiresAt` (AD-21); thay cho "fees preview".
- `POST /v1/otp-challenges` · `POST /v1/otp-challenges/{id}/verify` — OTP step-up với mock-otp, trả step-up assertion.
- `POST /v1/interbank-transfers` — xác nhận draft (`draftId` + assertion nếu cần) → Transaction `pending`.
- `GET /v1/transactions?accountId=&status=&cursor=` — danh sách giao dịch cho web KH.

## Giả định
| ID | Giả định |
|---|---|
| A-38 | Refresh token trả trong body JSON ở R1 |
| A-39 | Transaction trả `direction` + `accountId` theo góc nhìn người xem; số TK đối ứng mask trừ 4 số cuối |
| A-40 | Onboarding status đọc trực tiếp từ core, yêu cầu đã đăng nhập (không có endpoint ẩn danh theo `registrationId`) |
| A-41 | Sao kê tối đa 92 ngày mỗi truy vấn, sắp `seq` giảm dần |
| A-42 | Nạp tiền R1 không có trang thanh toán/redirect; mock-gateway tự callback |
| A-43 | Rút tiền R1 không nhận thông tin đích ngoài |
