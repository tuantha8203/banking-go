# 0003. Sổ cái kép append-only, chiến lược khóa, Unit of Work và payment.Transition

- Trạng thái: Accepted (2026-10-05)
- Liên quan: AD-4, AD-5, AD-16, AD-17, AD-18, AD-22, AD-23

## Bối cảnh
Tiêu chí số một là đúng tiền: không tạo/mất tiền, không sửa lịch sử, không số dư âm, không nhân đôi khi retry, kể cả khi callback, timeout, quét
`unknown` và tra soát tay cùng chạm một giao dịch. Đồng thời phải đạt 500 TPS từ R3; mọi giao dịch đều chạm tài khoản nội bộ (tiền trung gian,
thu phí...), nên khóa tài khoản nội bộ sẽ tuần tự hóa toàn hệ thống. Reviewer gate chỉ ra các rủi ro: bút toán và idempotency/outbox commit ở
transaction khác nhau, số dư và trạng thái nằm ở nhiều dòng, nhiều writer ghi đè trạng thái giao dịch.

## Các phương án đã cân nhắc
1. **Số dư là cột cập nhật trực tiếp, không bút toán** — nhanh nhưng không kiểm toán được. Bị loại.
2. **Sổ cái kép, khóa mọi tài khoản liên quan (cả nội bộ)** — đúng nhưng hot account nội bộ thành nút cổ chai. Bị loại.
3. **SERIALIZABLE cho mọi giao dịch** — đơn giản về lý thuyết, nhưng tỉ lệ retry cao dưới tải. Bị loại.
4. **Sổ cái kép append-only, chỉ khóa dòng TK khách hàng theo thứ tự cố định, TK nội bộ chỉ append** (chọn).

## Quyết định
- Mỗi biến động tiền = 1 journal ≥ 2 entry, ΣNợ = ΣCó, `BIGINT` VND > 0, chiều nằm ở side D/C. Journal thuộc đúng một transaction và mang `business_date`
  (ngày mở của `business_day` lúc hạch toán). Không UPDATE/DELETE entry/journal; sửa sai bằng transaction `reversal` mới (AD-23).
- Một dòng `ledger.ledger_accounts` mỗi tài khoản giữ `normal_side`, `status`, `balance`, `available_balance`, `version`. Chỉ `ledger` (`Post`, `PlaceHold`,
  `ReleaseHold`, `CaptureHold`) đổi số dư; hold `active → captured | released`, không hết hạn theo thời gian. CHECK `balance ≥ 0`, `available_balance ≥ 0`.
- Khóa: `SELECT … FOR UPDATE` dòng TK khách hàng trước mọi đọc trạng thái/số dư khả dụng. Thứ tự: idempotency → transaction → TK khách hàng theo `id`
  tăng → limit usage → share lock `business_day`. READ COMMITTED, `lock_timeout` 2 s, `statement_timeout` 5 s.
- TK nội bộ (hot account) không khóa, không cập nhật số dư trên hot path; số dư lấy từ snapshot định kỳ của core-worker.
- **Unit of Work**: chỉ entry use case gọi `uow.Do`; mọi port method nhận `tx`; idempotency, outbox, inbox, audit cùng handle. Một use case = một UoW.
- **`payment.Transition(ctx, tx, txn_id, expected_from, to, evidence)`** là đường duy nhất đổi trạng thái giao dịch: khóa dòng giao dịch, CAS theo
  `expected_from`, posting/capture/release chỉ xảy ra bên trong. Lặp lại cùng trạng thái cuối = no-op; bằng chứng mâu thuẫn → `recon_conflict` (critical).
- Job bất biến (FR-13) chạy ở REPEATABLE READ: ΣNợ = ΣCó, số dư = Σ entry, khả dụng = số dư − Σ hold active, không hold active của giao dịch đã kết thúc.

## Hệ quả
- Throughput giới hạn bởi tranh chấp trên từng TK khách hàng, không bởi TK nội bộ; hai giao dịch khác khách hàng chạy song song.
- Số dư TK nội bộ trên dashboard có độ trễ bằng chu kỳ snapshot; đối soát kế toán dùng entry, không dùng cột số dư.
- `entries` chỉ tăng; partition/archival để hoãn đến sau load test R3.
- Mọi handler (callback, timeout, scan, recon) dùng chung `Transition`, nên race giữa chúng là CAS thất bại có kiểm soát thay vì ghi đè.
- Kỷ luật UoW phải giữ bằng lint + review gate; lỗi gọi `Begin` trong adapter là lỗi chặn merge.
