# API contracts — banking-go

> Danh mục **ràng buộc**: feature phải khớp endpoint, RPC, event, mã lỗi ở đây. Nguồn: spine AD-6, AD-8, AD-9, AD-10, AD-11, AD-20, AD-21.
> Thay đổi (thêm/sửa/bỏ) đi qua `/foundation update api`, không sửa ngầm trong PR feature. Dữ liệu theo [`../data-model.md`](../data-model.md).

| File | Nội dung |
|---|---|
| [public-api.md](public-api.md) | REST cho khách hàng (`web-customer`, client API R1) |
| [admin-api.md](admin-api.md) | REST cho staff (`web-admin`), vai theo endpoint |
| [grpc.md](grpc.md) | gRPC core `banking.core.v1.*` mà edge gọi |
| [events.md](events.md) | RabbitMQ: topology, event, command, webhook đối tác |

## Nguồn sự thật (AD-9)
| Loại | Cách | Artifact | CI gate |
|---|---|---|---|
| REST ngoài | **Code-first**: Huma v2 trên chi, struct Go là nguồn | `services/<svc>/api/openapi/<svc>.yaml` (OpenAPI 3.1), generate + commit | Generate lại, `git diff --exit-code` fail nếu chưa commit; SPA client sinh bằng openapi-typescript + openapi-fetch (`packages/api-client-*`) |
| gRPC + payload event + audit | **Contract-first**: protobuf trong `/proto` (buf module) | Go code sinh từ `buf generate` | `buf lint`, `buf breaking` so với default branch |

- Catalog này là **đặc tả mức hợp đồng**; OpenAPI/proto là **hiện thực máy đọc**. Lệch nhau = bug, sửa theo catalog (hoặc update catalog trước).
- Thay đổi phá vỡ: REST thêm `/v2`; proto/event bump `v<major>`, producer dual-publish khi chuyển (AD-8).

## Quy ước REST chung
| Mục | Quy ước |
|---|---|
| Path | `/v1/...`, danh từ số nhiều, kebab-case; id trong path là UUID |
| JSON | camelCase; tiền = số nguyên VND (`int64`), không chuỗi, không thập phân; thời gian RFC 3339 UTC; ngày `YYYY-MM-DD` (Asia/Ho_Chi_Minh) |
| Địa chỉ TK | TK của mình: `accountId` (UUID); TK đối ứng: `accountNumber` (12 số, Luhn kiểm ở edge + core) |
| Phân trang | `?cursor=&limit=` (mặc định 50, tối đa 200); response `{ "items": [...], "nextCursor": "…" \| null }`; cursor opaque base64 `[A-31]` |
| Idempotency | Header `Idempotency-Key` (UUID) **bắt buộc** cho mọi request mutating, trừ endpoint phiên (login, refresh, logout, bước TOTP của login) `[A-6]` `[A-32]`. Edge chuyển nguyên key sang gRPC metadata `idempotency-key` |
| Replay | Cùng key + cùng nội dung → trả lại kết quả cũ (cùng status code, body); header `Idempotent-Replayed: true` `[A-33]` |
| Trace | Response luôn có header `traceparent`; problem có `traceId` |
| i18n | Backend chỉ trả `code` + `params`; SPA dịch |

## Problem details (RFC 9457)
```json
{
  "type": "urn:banking-go:error:insufficient_funds",
  "title": "Insufficient funds",
  "status": 422,
  "detail": "available balance is lower than amount",
  "code": "insufficient_funds",
  "params": { "accountId": "0192…" },
  "errors": [ { "field": "amount", "code": "amount_invalid" } ],
  "traceId": "4bf92f3577b34da6a3ce929d0e0e4736"
}
```
- `code` lấy **nguyên văn** từ `google.rpc.ErrorInfo.reason` (domain `banking-go`) khi lỗi từ core; `params` = `ErrorInfo.metadata`. Edge không đổi mã nghiệp vụ.
- HTTP status suy ra từ `code` theo bảng dưới (trong `pkg/problem`), không từ gRPC status.
- `type` = `urn:banking-go:error:<code>`; `params`, `errors` là extension member `[A-34]`. Không bao giờ có SQL, stack trace, PII.

## Bảng mã lỗi chung
Một bảng cho REST `code`, gRPC `ErrorInfo.reason`, và `failure_code` của giao dịch `failed` (cột **FC** = có thể là `failure_code`).
Mã snake_case thường (spine) `[A-35]`.

### Chung
| `code` | HTTP | gRPC | Nguồn | Retry | Nghĩa |
|---|---|---|---|---|---|
| `validation_failed` | 400 | INVALID_ARGUMENT | tất cả | không | Sai định dạng/thiếu field; chi tiết trong `errors[]`; không tạo bản ghi idempotency |
| `idempotency_key_required` | 400 | INVALID_ARGUMENT | edge | không | Thiếu/sai định dạng `Idempotency-Key` |
| `idempotency_in_progress` | 409 | ABORTED | tất cả | **có** | Cùng key đang xử lý, chờ quá `lock_timeout` |
| `idempotency_conflict` | 422 | FAILED_PRECONDITION | tất cả | không | Cùng key, khác nội dung (FR-14) |
| `unauthenticated` | 401 | UNAUTHENTICATED | tất cả | không | Thiếu/sai/hết hạn access token, session, hoặc `x-actor` |
| `permission_denied` | 403 | PERMISSION_DENIED | tất cả | không | Policy `pkg/authz` từ chối (staff); core ghi audit `denied` |
| `not_found` | 404 | NOT_FOUND | tất cả | không | Không tồn tại **hoặc** không thuộc `sub` (chống IDOR, AD-10) |
| `rate_limited` | 429 | RESOURCE_EXHAUSTED | edge | **có** | Kèm `Retry-After` |
| `resource_busy` | 409 | ABORTED | core | **có** | `lock_timeout`/`statement_timeout` hủy UoW (AD-5); không có hiệu ứng |
| `service_unavailable` | 503 | UNAVAILABLE | edge | **có** | Core/DB/broker không sẵn sàng |
| `internal_error` | 500 | INTERNAL | tất cả | có (cùng key) | Lỗi không lường trước |

### Danh tính & phiên (edge)
| `code` | HTTP | gRPC | Nguồn | Retry | Nghĩa |
|---|---|---|---|---|---|
| `weak_password` | 422 | — | public-api | không | < 10 ký tự hoặc trong danh sách phổ biến (FR-1) |
| `kyc_image_invalid` | 422 | — | public-api | không | Ảnh sai loại/quá cỡ (JPEG/PNG, ≤ 5 MB mỗi ảnh) `[A-36]` |
| `invalid_credentials` | 401 | — | edge | không | Sai SĐT/username hoặc mật khẩu (không phân biệt) |
| `login_locked` | 423 | — | edge | sau `lockedUntil` | 5 lần sai liên tiếp → khóa 15 phút; `params.lockedUntil` |
| `customer_login_not_allowed` | 403 | — | public-api | không | KH `rejected`/`expired` (AD-19) |
| `invalid_refresh_token` | 401 | — | public-api | không | Refresh token sai/hết hạn/đã revoke |
| `refresh_token_reused` | 401 | — | public-api | không | Dùng lại token đã xoay → revoke cả family |
| `invalid_totp` | 401 | — | admin-api | không | Mã TOTP sai hoặc đã dùng |
| `totp_enrollment_required` | 403 | — | admin-api | không | Chưa enrol TOTP; phải làm bước enrolment |
| `password_change_required` | 403 | — | admin-api | không | Đang dùng mật khẩu tạm |
| `session_expired` | 401 | — | admin-api | không | Idle 30 phút / hạn tuyệt đối / bị revoke (FR-20) |
| `admin_user_locked` | 403 | — | admin-api | không | User admin bị quản trị khóa |
| `username_taken` | 409 | — | admin-api | không | Trùng username |
| `self_action_forbidden` | 403 | — | admin-api | không | Tự gán vai / tự khóa / tự reset chính mình (FR-22) |

### Khách hàng & eKYC (core)
| `code` | HTTP | gRPC | Retry | Nghĩa |
|---|---|---|---|---|
| `phone_already_registered` | 409 | ALREADY_EXISTS | không | SĐT đã thuộc KH khác chưa `expired` (FR-1) |
| `national_id_already_registered` | 409 | ALREADY_EXISTS | không | CCCD đã thuộc KH khác chưa `expired` |
| `customer_not_active` | 403 | FAILED_PRECONDITION | không | Lệnh/đọc cần KH `active` (AD-10, AD-19) |
| `invalid_customer_state` | 409 | FAILED_PRECONDITION | không | Vd quyết định eKYC khi KH không ở `pending_review` |

### Tài khoản (core)
| `code` | HTTP | gRPC | FC | Nghĩa |
|---|---|---|---|---|
| `account_limit_reached` | 422 | FAILED_PRECONDITION | | Đã có 5 TK chưa đóng (FR-6) |
| `account_number_invalid` | 422 | INVALID_ARGUMENT | | Sai định dạng/Luhn (FR-5) |
| `account_number_not_found` | 422 | NOT_FOUND | | Số TK đối ứng không tồn tại |
| `account_debit_blocked` | 422 | FAILED_PRECONDITION | ✓ | TK nguồn `debit_blocked` |
| `account_blocked` | 422 | FAILED_PRECONDITION | ✓ | TK `blocked` |
| `account_closed` | 422 | FAILED_PRECONDITION | ✓ | TK `closed` |
| `destination_account_unavailable` | 422 | FAILED_PRECONDITION | ✓ | TK đích không nhận Có (`blocked`/`closed`); không lộ lý do cụ thể của TK người khác |
| `account_balance_not_zero` | 422 | FAILED_PRECONDITION | | Đóng TK khi số dư ≠ 0 (FR-8) |
| `account_has_active_holds` | 422 | FAILED_PRECONDITION | | Đóng TK khi còn tạm giữ |
| `account_has_inflight_transactions` | 422 | FAILED_PRECONDITION | | Đóng TK khi còn giao dịch `pending`/`unknown` liên quan |
| `default_account_close_forbidden` | 422 | FAILED_PRECONDITION | | Đóng TK mặc định khi còn TK khác |
| `invalid_status_transition` | 409 | FAILED_PRECONDITION | | Chuyển trạng thái TK không có trong state machine (vd `blocked → debit_blocked`; đóng TK `debit_blocked`/`blocked` — phải mở khóa trước) |

### Giao dịch (core)
| `code` | HTTP | gRPC | FC | Nghĩa |
|---|---|---|---|---|
| `amount_invalid` | 422 | INVALID_ARGUMENT | | Số tiền ≤ 0 hoặc vượt `int64` |
| `same_account_transfer` | 422 | INVALID_ARGUMENT | | TK nguồn = TK đích (FR-16) |
| `insufficient_funds` | 422 | FAILED_PRECONDITION | ✓ | Số dư khả dụng < số tiền |
| `partner_rejected` | — | — | ✓ | Đối tác từ chối (chỉ là `failure_code`, không phải lỗi REST) |
| `transaction_not_unknown` | 409 | FAILED_PRECONDITION | | Tra soát thủ công khi giao dịch không `unknown` |

Giao dịch bị từ chối nghiệp vụ **vẫn tạo** giao dịch `failed`: REST trả `201` với `status: "failed"` + `failureCode`, không trả problem `[A-37]`. Problem chỉ dùng khi không có bản ghi giao dịch.

### Dành cho R2 (đã giữ chỗ)
| `code` | HTTP | gRPC | Nghĩa |
|---|---|---|---|
| `approval_required` | 403 | PERMISSION_DENIED | Lệnh `requires_approval` thiếu claim `approval` (AD-20) |
| `approval_invalid` | 403 | PERMISSION_DENIED | Sai kid, maker = checker, sai vai, sai `request_hash` |
| `approval_expired` | 409 | FAILED_PRECONDITION | Quá `expires_at` |
| `approval_stale` | 409 | FAILED_PRECONDITION | Target version ≠ `expected_target_version` |
| `limit_exceeded` | 422 | FAILED_PRECONDITION | Vượt hạn mức giao dịch/ngày (AD-21) |
| `draft_expired` | 409 | FAILED_PRECONDITION | Draft hết hạn |
| `step_up_required` | 403 | FAILED_PRECONDITION | Cần OTP, thiếu assertion |
| `step_up_invalid` | 401 | UNAUTHENTICATED | Assertion sai/hết hạn/đã dùng |
| `otp_invalid` | 401 | — | Mã OTP sai (public-api) |
| `name_inquiry_unavailable` | 503 | UNAVAILABLE | NAPAS mock tra tên timeout |

### Mã nội bộ (không trả client)
| Mã | Ở đâu | Nghĩa |
|---|---|---|
| `recon_conflict` | `partner_attempts.outcome = conflict`, alert critical | Bằng chứng đối tác ≠ trạng thái cuối đã ghi (AD-18) |
| `callback_mismatch` | `partner_attempts.outcome = mismatch`, alert critical | Callback lệch `(our_txn_id, amount)`; `pending → unknown` |
| `invariant_violation` | `ledger.invariant_checks.violations`, alert critical | FR-13 vi phạm |

## Giả định
| ID | Giả định |
|---|---|
| A-6 | `Idempotency-Key` là UUID (client sinh); `registration_id` = UUIDv5 của key |
| A-31 | Cursor opaque base64; limit mặc định 50, tối đa 200 |
| A-32 | Bước TOTP verify/enrolment của login admin tính là endpoint phiên, không cần `Idempotency-Key`; đổi mật khẩu vẫn cần |
| A-33 | Replay trả header `Idempotent-Replayed: true` |
| A-34 | `type` = `urn:banking-go:error:<code>`; thêm extension `params`, `errors` vào shape spine |
| A-35 | Mã lỗi là snake_case thường |
| A-36 | Ảnh eKYC JPEG/PNG ≤ 5 MB mỗi ảnh, 3 ảnh (`idFront`, `idBack`, `selfie`) |
| A-37 | Lệnh tạo giao dịch bị từ chối nghiệp vụ trả `201` + giao dịch `failed`, không trả problem |
