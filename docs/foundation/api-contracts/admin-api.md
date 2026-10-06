# Admin API (R1) — banking-go

> REST của **admin-api** cho staff (`web-admin`). Quy ước chung, mã lỗi: [README.md](README.md). RPC core: [grpc.md](grpc.md).
> OpenAPI máy đọc: `services/admin-api/api/openapi/admin-api.yaml`. Tách hoàn toàn với auth KH (FR-20).

## Xác thực & phiên
- Login 2 bước: mật khẩu → phiên `mfa_pending` → TOTP → phiên `active`. Idle 30 phút (FR-20), tuyệt đối 8 h `[A-29]`.
- Phiên qua cookie HttpOnly `bg_admin_session` (lưu hash ở `backoffice.admin_sessions`) `[A-44]`; cờ cookie, CSRF, CORS chốt ở security conventions (spine Deferred).
- Lệnh tới core: admin-api ký `x-actor` (`actor_type=staff`, `sub` = admin user id, `roles`, `session_id`) (AD-10).
- AuthZ: admin-api kiểm policy `pkg/authz` cho use case của nó; core kiểm lại cùng policy cho use case core. Mặc định từ chối.

## Vai → quyền (`pkg/authz`) `[A-28]` `[A-45]`
| Quyền | `operator` (GDV/vận hành) | `supervisor` (KSV) | `accountant` (kế toán/đối soát) | `administrator` (quản trị) |
|---|---|---|---|---|
| `customer.read` | ✓ | ✓ | | |
| `account.read` (TK + sao kê) | ✓ | ✓ | ✓ | |
| `account.block` | ✓ | | | |
| `ekyc.review` | ✓ | | | |
| `transaction.read` | ✓ | ✓ | ✓ | |
| `transaction.reconcile` | ✓ | | ✓ | |
| `audit.read` | | ✓ | | ✓ |
| `admin_user.manage` | | | | ✓ |
| `ops.read` | ✓ | ✓ | ✓ | ✓ |
| (R2) `*.approve` | | ✓ | | |

Mọi user đã đăng nhập: `GET /v1/me`, `GET /v1/roles`, đổi mật khẩu, logout.

Thao tác nhạy cảm có lý do (ADM-13, ADM-14, ADM-21, ADM-22, ADM-26): body bắt buộc `reasonCode` (chọn từ danh mục) + `note` (≥ 10 ký tự); core kiểm cho RPC core (ADM-21/22/26), admin-api kiểm cho ADM-13/14 (không qua core); thiếu/ngắn → `validation_failed`.

## Danh mục
| # | Method | Path | Quyền | Idem-Key | Core RPC | FR |
|---|---|---|---|---|---|---|
| ADM-1 | POST | `/v1/auth/login` | none | — | — | FR-20 |
| ADM-2 | POST | `/v1/auth/totp/verify` | phiên `mfa_pending` | — | — | FR-20 |
| ADM-3 | POST | `/v1/auth/totp/enrollment` | phiên `mfa_pending`, chưa enrol | — | — | FR-20 |
| ADM-4 | POST | `/v1/auth/totp/enrollment/confirm` | phiên `mfa_pending` | — | — | FR-20 |
| ADM-5 | POST | `/v1/auth/password` | phiên (`mfa_pending` nếu bắt đổi, hoặc `active`) | **bắt buộc** | — | FR-20 |
| ADM-6 | POST | `/v1/auth/logout` | phiên | — | — | FR-20 |
| ADM-7 | GET | `/v1/me` | phiên `active` | — | — | FR-21 |
| ADM-8 | GET | `/v1/roles` | phiên `active` | — | — | FR-21 |
| ADM-9 | GET | `/v1/admin-users` | `admin_user.manage` | — | — | FR-22 |
| ADM-10 | POST | `/v1/admin-users` | `admin_user.manage` | **bắt buộc** | — | FR-22 |
| ADM-11 | GET | `/v1/admin-users/{adminUserId}` | `admin_user.manage` | — | — | FR-22 |
| ADM-12 | PUT | `/v1/admin-users/{adminUserId}/roles` | `admin_user.manage`, ≠ chính mình | **bắt buộc** | — | FR-21, FR-22 |
| ADM-13 | POST | `/v1/admin-users/{adminUserId}/lock` | `admin_user.manage`, ≠ chính mình | **bắt buộc** | — | FR-22 |
| ADM-14 | POST | `/v1/admin-users/{adminUserId}/unlock` | `admin_user.manage`, ≠ chính mình | **bắt buộc** | — | FR-22 |
| ADM-15 | POST | `/v1/admin-users/{adminUserId}/reset-credentials` | `admin_user.manage`, ≠ chính mình | **bắt buộc** | — | FR-22 |
| ADM-16 | POST | `/v1/customers/search` | `customer.read` | — (đọc) | `CustomerService.SearchCustomers` | FR-24 |
| ADM-17 | GET | `/v1/customers/{customerId}` | `customer.read` | — | `CustomerService.GetCustomer` | FR-24 |
| ADM-18 | GET | `/v1/accounts?accountNumber=` | `account.read` | — | `AccountService.FindAccountByNumber` | FR-24 |
| ADM-19 | GET | `/v1/accounts/{accountId}` | `account.read` | — | `AccountService.GetAccount` | FR-24 |
| ADM-20 | GET | `/v1/accounts/{accountId}/statement` | `account.read` | — | `AccountService.GetStatement` | FR-9, FR-24 |
| ADM-21 | POST | `/v1/accounts/{accountId}/block` | `account.block` | **bắt buộc** | `AccountService.BlockAccount` | FR-7 / BF-6 |
| ADM-22 | POST | `/v1/accounts/{accountId}/unblock` | `account.block` | **bắt buộc** | `AccountService.UnblockAccount` | FR-7 / BF-6 |
| ADM-23 | GET | `/v1/ekyc-reviews` | `ekyc.review` hoặc `customer.read` | — | `CustomerService.ListEkycReviews` | FR-3 |
| ADM-24 | GET | `/v1/ekyc-reviews/{customerId}` | `ekyc.review` hoặc `customer.read` | — | `CustomerService.GetEkycReview` | FR-3 |
| ADM-25 | GET | `/v1/ekyc-reviews/{customerId}/documents/{kind}` | `ekyc.review` | — | `CustomerService.GetKycDocument` | FR-3 |
| ADM-26 | POST | `/v1/ekyc-reviews/{customerId}/decision` | `ekyc.review` | **bắt buộc** | `CustomerService.DecideEkycReview` | FR-3 / BF-1 |
| ADM-27 | GET | `/v1/transactions` | `transaction.read` | — | `PaymentService.ListTransactions` | FR-19, FR-24 |
| ADM-28 | GET | `/v1/transactions/{transactionId}` | `transaction.read` | — | `PaymentService.GetTransaction` | FR-18 |
| ADM-29 | POST | `/v1/transactions/{transactionId}/reconcile` | `transaction.reconcile` | **bắt buộc** | `PaymentService.RequestReconciliation` | FR-19 / BF-5 |
| ADM-30 | GET | `/v1/audit-records` | `audit.read` | — | `AuditService.SearchAuditRecords` | FR-23 |
| ADM-31 | GET | `/v1/ops/overview` | `ops.read` | — | `OpsService.GetOverview` | FR-13, FR-19 |

Lỗi chung mọi endpoint (ngoài ADM-1): `unauthenticated`, `session_expired`, `permission_denied`, `validation_failed`, `rate_limited`, `resource_busy`, `service_unavailable`, `internal_error`; có Idem-Key thêm 3 mã idempotency.

## Chi tiết

### Phiên
| # | Request | Response | Lỗi riêng |
|---|---|---|---|
| ADM-1 | `{ "username", "password" }` | `200` `{ "stage": "mfa_pending", "totpEnrolled": bool, "passwordMustChange": bool }` + cookie | `invalid_credentials`, `login_locked`, `admin_user_locked` |
| ADM-2 | `{ "code" }` | `200` `{ "stage": "active", "me": Me }` | `invalid_totp`, `totp_enrollment_required`, `password_change_required`, `login_locked` |
| ADM-3 | `{}` | `200` `{ "otpauthUri", "secretBase32" }` (chỉ trả một lần, không log) | `validation_failed` nếu đã enrol |
| ADM-4 | `{ "code" }` | `200` `{ "stage": "active", "me": Me }` | `invalid_totp` |
| ADM-5 | `{ "currentPassword", "newPassword" }` | `204` | `invalid_credentials`, `weak_password` |
| ADM-6 | — | `204`; revoke phiên | — |

`Me` = `{ "adminUserId", "username", "displayName", "roles": [], "permissions": [] }`. Mọi lần đăng nhập đúng/sai, lockout, enrol TOTP, logout, hết phiên → audit event `banking.backoffice.audit_record.created.v1` (AD-11).

### User admin & vai
- ADM-8 `200` `{ "items": [ { "role", "permissions": [] } ] }` — đọc từ `pkg/authz`, không CRUD (vai là code) `[A-28]`.
- ADM-9 query `status`, `role`, `cursor`, `limit` → `{ items: [AdminUser], nextCursor }`; `AdminUser` = `{ adminUserId, username, displayName, status, roles, totpEnrolled, createdAt }`.
- ADM-10 `{ "username", "displayName", "roles": [] }` → `201` `{ "adminUser", "temporaryPassword" }` (mật khẩu tạm trả **một lần**) `[A-25]`. Lỗi `username_taken`.
- ADM-12 `{ "roles": [] }` (thay toàn bộ) → `200` AdminUser. Lỗi `self_action_forbidden`.
- ADM-13 `{ "reasonCode", "note" }` → `200`; revoke mọi phiên của user đó. ADM-14 `{ "reasonCode", "note" }` → `200`.
- ADM-15 `{}` → `200` `{ "temporaryPassword" }`; xóa TOTP (phải enrol lại), revoke phiên.
- Lỗi chung nhóm: `not_found`, `self_action_forbidden`. Thay đổi user/vai → audit event (edge-owned fact).

### Khách hàng & tài khoản
- ADM-16 body `{ "phone" } | { "nationalId" } | { "accountNumber" }` (đúng một) → `200` `{ "items": [CustomerSummary] }`. Dùng POST để PII không nằm trên URL/log `[A-46]`; core tra bằng blind index và ghi audit lượt tra `[A-47]`.
- `CustomerSummary` = `{ customerId, fullName, phoneMasked, nationalIdMasked, status, createdAt }` (mask còn 4 số cuối).
- ADM-17 `200` `{ ...CustomerSummary, statusReasonCode, accounts: [Account] }`.
- ADM-18/ADM-19 `200` Account + `ownerCustomerId`. ADM-20 giống P-12 (public) cộng `transactionId` dẫn tới ADM-28.
- ADM-21 `{ "level": "debit_blocked|blocked", "reasonCode", "note" }` → `200` Account. ADM-22 `{ "reasonCode", "note" }` → `200` Account (`active`).
  - Lỗi: `not_found`, `invalid_status_transition`, `account_closed`.
  - R1 thực hiện trực tiếp; từ R2 thành yêu cầu maker-checker (BF-9, AD-20).

### eKYC review
- ADM-23 query `cursor`, `limit` → `{ items: [ { customerId, fullName, phoneMasked, nationalIdMasked, lastCheckStatus, lastReasonCode, queuedAt } ], nextCursor }` (KH `pending_review`, cũ trước).
- ADM-24 `200` `{ customer: CustomerSummary, checks: [ { attemptNo, status, reasonCode, requestedAt, completedAt } ], documents: ["id_front","id_back","selfie"] }`.
- ADM-25 stream ảnh (`image/jpeg|png`, `Cache-Control: no-store`) do core đọc từ object store và trả qua gRPC stream `[A-48]`. Không log, không cache.
- ADM-26 `{ "decision": "approve|reject", "reasonCode", "note" }` → `200` `{ customerId, status }` (`active` + mở TK mặc định, hoặc `rejected`). Lỗi `invalid_customer_state`.
  - Động từ API `approve|reject` ánh xạ sang giá trị DB `customer.ekyc_reviews.decision` = `approved|rejected`.

### Giao dịch & tra soát
- ADM-27 query `status` (vd `unknown`), `kind`, `accountId`, `customerId`, `createdFrom`, `createdTo`, `cursor`, `limit` → `{ items: [TransactionStaff], nextCursor }`.
- ADM-28 `200` `TransactionStaff` = Transaction (public) + `sourceAccountId`, `destinationAccountId`, `partner`, `partnerDeadlineAt`, `reconAttempts`, `nextReconAt`, `timeline`, `partnerAttempts: [ { attemptNo, kind, outcome, sentAt, completedAt, partnerStatus } ]`.
- ADM-29 `{}` → `202` `{ transactionId, reconAttemptNo, enqueuedAt }`; core chỉ enqueue command, core-worker mới hỏi đối tác (AD-18). Lỗi `not_found`, `transaction_not_unknown`.

### Audit & vận hành
- ADM-30 query `actorSub`, `actorType`, `action`, `targetType`, `targetId`, `outcome`, `from`, `to`, `cursor`, `limit` → `{ items: [AuditRecord], nextCursor }` (field theo `banking.audit.v1.AuditRecord`, `occurred_at` giảm dần).
- ADM-31 `200` `{ businessDate, pendingCount, unknownCount, oldestUnknownAgeSeconds, ekycReviewQueueCount, lastInvariantCheck: { at, ok } }`.

## R2 (bổ sung)
- `GET /v1/maker-checker-requests` · `POST /v1/maker-checker-requests` (maker tạo: điều chỉnh số dư, khóa/mở TK, đổi hạn mức/phí, reversal) · `GET /v1/maker-checker-requests/{id}`.
- `POST /v1/maker-checker-requests/{id}/approve` · `POST /v1/maker-checker-requests/{id}/reject` (checker ≠ maker, đúng vai).
- ADM-21/ADM-22 chuyển thành tạo yêu cầu maker-checker; thực thi bằng outbox admin-api → core với claim `approval` (AD-20).
- `GET /v1/config/limits` · `GET /v1/config/fees` (đọc từ core); thay đổi chỉ qua maker-checker request.

## Giả định
| ID | Giả định |
|---|---|
| A-44 | Phiên admin dùng cookie HttpOnly mang session id (hash ở DB) |
| A-45 | Bảng vai → quyền R1 như trên (operator khóa TK + duyệt eKYC + tra soát; supervisor đọc + xem audit ở R1 (xem audit bổ sung 2026-10-06); accountant đọc + tra soát; administrator quản lý user + audit) |
| A-46 | Tra cứu KH theo SĐT/CCCD dùng `POST /v1/customers/search` để PII không vào URL |
| A-47 | Core ghi audit cho lượt tra cứu PII và lượt xem ảnh eKYC (dù không đổi trạng thái) |
| A-48 | Ảnh eKYC cho GDV đi qua core gRPC stream → admin-api (không presigned URL ra trình duyệt); core server cần credential object store read-only `kyc/` như core-worker |
