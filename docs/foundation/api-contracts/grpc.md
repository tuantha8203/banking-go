# gRPC core (R1) — banking-go

> Contract-first trong `/proto` (buf; `buf lint` + `buf breaking` trong CI). Package `banking.core.v1`; audit `banking.audit.v1` (AD-9, AD-11).
> Chỉ public-api và admin-api gọi, qua mTLS + `x-actor` (AD-10). core-worker không gọi gRPC core — dùng cùng `app` use case in-process.
> Mã lỗi: [README.md](README.md#bảng-mã-lỗi-chung).

## Metadata
| Key | Bắt buộc | Nội dung |
|---|---|---|
| `x-actor` | mọi RPC | Internal JWT EdDSA, `exp` ≤ 60 s; claims `iss`, `aud=core`, `kid`, `jti`, `iat`, `exp`, `rpc` (full method), `actor_type`, `sub`, `roles`, `session_id`, `client_ip`, `user_agent`, `request_id`; (R2) `approval` |
| `idempotency-key` | RPC mutating | Key gốc từ REST `Idempotency-Key`; riêng `RegisterCustomer` = `reg:<Idempotency-Key>` |
| `traceparent`, `tracestate` | tự động | OTel propagator (AD-13) |

Core từ chối (`unauthenticated`) khi `aud` ≠ core, `rpc` ≠ method đang gọi, `kid` không biết, hoặc `actor_type` không được phép cho `kid`:
| `kid` của | `actor_type` cho phép |
|---|---|
| public-api | `customer` (roles `[customer]`); `anonymous` **chỉ** cho `CustomerService.RegisterCustomer` `[A-49]` |
| admin-api | `staff` |

## Proto option (`banking/core/v1/options.proto`)
| Option | Gắn vào | Ý nghĩa |
|---|---|---|
| `(banking.core.v1.mutating)` | method | Bắt buộc `idempotency-key`; idempotency record ở core (AD-6) |
| `(banking.core.v1.business_field)` | field | Field đưa vào `request_hash` (canonical encoding) |
| `(banking.core.v1.requires_approval)` | method | (R2) bắt buộc claim `approval` (AD-20); R1: `BlockAccount`, `UnblockAccount` gắn option nhưng chưa bật `[A-50]` |
| `(banking.core.v1.allowed_actors)` | method | `customer` / `staff` / `anonymous`; kiểm trước use case |

## Lỗi
- `status.code` theo cột gRPC trong bảng lỗi; detail `google.rpc.ErrorInfo{ reason: <code>, domain: "banking-go", metadata: params }`.
- Validation nhiều field: thêm `google.rpc.BadRequest` (edge map sang `errors[]`).
- Edge copy `reason` → problem `code` nguyên văn, không map lại (AD-9).

## Message dùng chung
Tiền: `int64 amount` (VND đồng) + `string currency = "VND"`, không có message `Money`.

| Message | Field chính |
|---|---|
| `Account` | `account_id`, `account_number`, `owner_customer_id`, `status`, `is_default`, `balance`, `available_balance`, `version`, `opened_at`, `closed_at` |
| `Transaction` | `transaction_id`, `kind`, `status`, `version`, `amount`, `source_account_id`, `destination_account_id`, `counterparty_account_number_masked`, `description`, `failure_code`, `business_date`, `created_at`, `finalized_at` |
| `TransactionTransition` | `version`, `from_status`, `to_status`, `reason_code`, `trigger`, `occurred_at` |
| `PartnerAttempt` | `attempt_no`, `kind`, `outcome`, `partner_status`, `sent_at`, `completed_at` (chỉ trả cho staff) |
| `PageRequest` / `PageResponse` | `cursor`, `limit` / `next_cursor` |
| `CustomerSummary` | `customer_id`, `full_name`, `phone_masked`, `national_id_masked`, `status`, `created_at` |

Enum proto mirror đúng enum DB (`CustomerStatus`, `AccountStatus`, `TransactionStatus`, `TransactionKind`, `HoldStatus`); giá trị `*_UNSPECIFIED = 0` bị từ chối.

## Services

### `banking.core.v1.CustomerService`
| RPC | Actor | Mut | Request (business field) | Response | Edge | Lỗi riêng |
|---|---|---|---|---|---|---|
| `RegisterCustomer` | anonymous | ✓ | `registration_id`, **`phone`**, **`national_id`**, **`full_name`**, **`kyc_documents{kind, object_key}`** | `customer_id`, `status` | public P-1 | `phone_already_registered`, `national_id_already_registered` |
| `GetOnboardingStatus` | customer (mọi trạng thái) | | — (`sub`) | `customer_id`, `status`, `reason_code`, `updated_at` | public P-2 | — |
| `SearchCustomers` | staff `customer.read` | | oneof `phone` \| `national_id` \| `account_number` | `repeated CustomerSummary` | admin ADM-16 | `account_number_invalid` |
| `GetCustomer` | staff `customer.read` | | `customer_id` | `CustomerSummary`, `status_reason_code`, `repeated Account` | admin ADM-17 | `not_found` |
| `ListEkycReviews` | staff `ekyc.review`/`customer.read` | | `PageRequest` | items (`CustomerSummary`, `last_check_status`, `queued_at`), `PageResponse` | admin ADM-23 | — |
| `GetEkycReview` | staff `ekyc.review`/`customer.read` | | `customer_id` | `CustomerSummary`, `repeated EkycCheck`, `document_kinds` | admin ADM-24 | `not_found` |
| `GetKycDocument` | staff `ekyc.review` | | `customer_id`, `kind` | **server stream** `{content_type, chunk bytes}` | admin ADM-25 | `not_found` |
| `DecideEkycReview` | staff `ekyc.review` | ✓ | `customer_id`, **`decision`**, **`reason_code`**, **`note`** (bắt buộc, ≥ 10 ký tự) | `customer_id`, `status` | admin ADM-26 | `invalid_customer_state`, `validation_failed` (`note`) |

`RegisterCustomer` (AD-19): UoW tạo `customers` + `kyc_documents` + outbox `verify_ekyc` + event `phone_changed`/`status_changed`; cùng SĐT + CCCD với KH chưa có credential (`credential_bound_at IS NULL`), tạo < 24 h → trả `customer_id` cũ (không tạo ảnh/eKYC mới) `[A-8]`.

### `banking.core.v1.AccountService`
| RPC | Actor | Mut | Request (business field) | Response | Edge | Lỗi riêng |
|---|---|---|---|---|---|---|
| `ListAccounts` | customer (của mình) / staff `account.read` (`customer_id`) | | `customer_id` (staff) | `repeated Account` | P-6, ADM-17 | `customer_not_active` |
| `GetAccount` | customer (owner) / staff `account.read` | | `account_id` | `Account` | P-8, ADM-19 | `not_found` |
| `FindAccountByNumber` | staff `account.read` | | `account_number` | `Account` | ADM-18 | `account_number_invalid`, `not_found` |
| `OpenAccount` | customer | ✓ | — | `Account` | P-7 | `customer_not_active`, `account_limit_reached` |
| `SetDefaultAccount` | customer (owner) | ✓ | **`account_id`** | `Account` | P-9 | `not_found`, `account_closed` |
| `CloseAccount` | customer (owner) | ✓ | **`account_id`** | `Account` | P-10 | `account_closed`, `invalid_status_transition` (TK `debit_blocked`/`blocked`, phải mở khóa trước), `account_balance_not_zero`, `account_has_active_holds`, `account_has_inflight_transactions`, `default_account_close_forbidden` |
| `GetBalance` | customer (owner) / staff `account.read` | | `account_id` | `balance`, `available_balance`, `as_of` | P-11 | `not_found` |
| `GetStatement` | customer (owner) / staff `account.read` | | `account_id`, `from_date`, `to_date`, `PageRequest` | `repeated StatementLine{seq, transaction_id, kind, side, amount, balance_after, created_at, business_date, description, counterparty_account_number_masked}`, `PageResponse` | P-12, ADM-20 | `not_found` |
| `BlockAccount` | staff `account.block` | ✓ | **`account_id`**, **`level`**, **`reason_code`**, **`note`** (bắt buộc, ≥ 10 ký tự) | `Account` | ADM-21 | `invalid_status_transition`, `account_closed`, `validation_failed` (`note`) |
| `UnblockAccount` | staff `account.block` | ✓ | **`account_id`**, **`reason_code`**, **`note`** (bắt buộc, ≥ 10 ký tự) | `Account` | ADM-22 | `invalid_status_transition`, `account_closed`, `validation_failed` (`note`) |

Customer actor: core kiểm `owner_customer_id == sub` trong UoW; sai → `not_found`. Customer khác `active` → `customer_not_active` (trừ `GetOnboardingStatus`).

### `banking.core.v1.PaymentService`
| RPC | Actor | Mut | Request (business field) | Response | Edge | Lỗi riêng |
|---|---|---|---|---|---|---|
| `CreateDeposit` | customer (owner) | ✓ | **`account_id`**, **`amount`**, **`description`** | `Transaction` (`pending`/`failed`) | P-13 | `amount_invalid`, `not_found` |
| `CreateInternalTransfer` | customer (owner nguồn) | ✓ | **`source_account_id`**, **`destination_account_number`**, **`amount`**, **`description`** | `Transaction` (`succeeded`/`failed`) | P-14 | `amount_invalid`, `same_account_transfer`, `account_number_invalid`, `account_number_not_found`, `not_found` |
| `CreateWithdrawal` | customer (owner) | ✓ | **`account_id`**, **`amount`**, **`description`** | `Transaction` (`pending`/`failed`) | P-15 | `amount_invalid`, `not_found` |
| `GetTransaction` | customer (owner nguồn/đích) / staff `transaction.read` | | `transaction_id` | `Transaction`, `repeated TransactionTransition`; staff thêm `repeated PartnerAttempt`, `partner`, `partner_deadline_at`, `recon_attempts`, `next_recon_at` | P-16, ADM-28 | `not_found` |
| `ListTransactions` | staff `transaction.read` | | `status`, `kind`, `account_id`, `customer_id`, `created_from`, `created_to`, `PageRequest` | `repeated Transaction`, `PageResponse` | ADM-27 | — |
| `RequestReconciliation` | staff `transaction.reconcile` | ✓ | **`transaction_id`** | `transaction_id`, `recon_attempt_no`, `enqueued_at` | ADM-29 | `transaction_not_unknown`, `not_found` |

`failure_code` của `Transaction` lấy từ bảng lỗi (cột FC). Lệnh bị từ chối nghiệp vụ trả **OK** + `Transaction{status: FAILED}` và được lưu idempotency (AD-6) `[A-37]`.

### `banking.core.v1.AuditService`
| RPC | Actor | Request | Response | Edge |
|---|---|---|---|---|
| `SearchAuditRecords` | staff `audit.read` | `actor_type`, `actor_sub`, `action`, `target_type`, `target_id`, `outcome`, `from`, `to`, `PageRequest` | `repeated banking.audit.v1.AuditRecord`, `PageResponse` | ADM-30 |

Ingest audit event của edge đi qua RabbitMQ ([events.md](events.md)), không qua gRPC.

### `banking.core.v1.OpsService`
| RPC | Actor | Request | Response | Edge |
|---|---|---|---|---|
| `GetOverview` | staff `ops.read` | — | `business_date`, `pending_count`, `unknown_count`, `oldest_unknown_age_seconds`, `ekyc_review_queue_count`, `last_invariant_check{at, ok}` | ADM-31 |

Health: `grpc.health.v1.Health` chuẩn (không qua `x-actor`), ngoài ra `/livez`, `/readyz` trên admin port (AD-26).

## R2 (bổ sung)
- `PaymentService.CreatePaymentDraft`, `ConfirmPaymentDraft` (step-up assertion trong metadata `x-step-up`), `InquireName` (đồng bộ, NAPAS mock, không mở DB transaction) `[A-51]`.
- `LedgerService.AdjustBalance`, `PaymentService.CreateReversal` — `requires_approval`.
- `PricingService.GetLimits`, `GetFeeSchedule`, `UpdateLimits`, `UpdateFeeSchedule` — update `requires_approval`.
- Bật `requires_approval` cho `BlockAccount`/`UnblockAccount`; key luôn `mc:<request_id>:execute`.

## Giả định
| ID | Giả định |
|---|---|
| A-49 | **Spine gap (AD-10)**: đăng ký chưa có `customer_id`, nên public-api được dùng `actor_type=anonymous` (`sub` = `registration_id`) **chỉ** cho `RegisterCustomer`; đã amend AD-10 (2026-10-06) |
| A-50 | Option `requires_approval` gắn sẵn từ R1 cho block/unblock nhưng chỉ enforce từ R2 |
| A-51 | Step-up assertion R2 truyền qua metadata `x-step-up` |
