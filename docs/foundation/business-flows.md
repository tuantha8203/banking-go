# Business flows — banking-go

> Nguồn: PRD `_bmad/planning-artifacts/prds/prd-banking-go-2026-10-05/prd.md`. Thuật ngữ theo `glossary.md`.
> R1 chi tiết; R2–R4 khung, chi tiết hóa khi `/brainstorm` release đó (qua `/foundation update business-flows`).

## Mục lục
| ID | Flow | Release | FR | UJ |
|---|---|---|---|---|
| BF-1 | Đăng ký + eKYC | R1 | FR-1..3, FR-6 | UJ-1 |
| BF-2 | Nạp tiền | R1 | FR-14, FR-15 | UJ-2 |
| BF-3 | Chuyển nội bộ | R1 | FR-14, FR-16 | UJ-3 |
| BF-4 | Rút tiền | R1 | FR-12, FR-14, FR-17 | UJ-4 |
| BF-5 | Tra soát giao dịch unknown | R1 | FR-19 | UJ-2, UJ-4, UJ-5 |
| BF-6 | Khóa / đóng tài khoản | R1 | FR-7, FR-8 | UJ-5 |
| BF-7 | Đăng nhập KH / admin | R1 | FR-4, FR-20 | UJ-5, UJ-6 |
| BF-8 | Chuyển liên ngân hàng | R2 | — | UJ-7 |
| BF-9 | Maker-checker | R2 | — | UJ-8, UJ-9 |
| BF-10 | Đối soát + EOD | R3 | — | UJ-10 |
| BF-11 | Tiết kiệm | R4 | — | UJ-11 |

FR-9, FR-13, FR-21–24 (UJ-6) là đọc/CRUD admin, không có luồng riêng — xem `api-contracts/admin-api.md`.

## Quy tắc chung (mọi flow tạo giao dịch)
1. Yêu cầu có idempotency key. Cùng key + cùng nội dung → trả kết quả cũ; khác nội dung → 422 (FR-14).
2. Mọi biến động tiền = một giao dịch kế toán cân, ghi nguyên tử; không sửa/xóa bút toán, sai thì đảo (FR-10).
3. Gọi đối tác ngoài **không** nằm trong transaction DB. Trước khi gọi: ghi trạng thái + tạm giữ; sau khi có kết quả: hạch toán.
4. Timeout từ đối tác → `unknown`, **không** tự coi là thất bại; chỉ tra soát mới quyết định kết quả cuối.
5. Số tiền: số nguyên VND, > 0.

## Máy trạng thái

### Giao dịch (FR-18)
```mermaid
stateDiagram-v2
  [*] --> pending: tạo (đã tạm giữ nếu ghi Nợ ra ngoài)
  pending --> succeeded: đối tác/hạch toán thành công
  pending --> failed: bị từ chối (số dư, trạng thái TK, đối tác từ chối)
  pending --> unknown: timeout / không có callback
  unknown --> succeeded: tra soát → thành công
  unknown --> failed: tra soát → thất bại
  succeeded --> [*]
  failed --> [*]
```
Chuyển nội bộ (BF-3) không qua đối tác nên không bao giờ `unknown`.

### Khách hàng (FR-2, FR-3)
```mermaid
stateDiagram-v2
  [*] --> pending_ekyc: đăng ký
  pending_ekyc --> active: eKYC đạt
  pending_ekyc --> pending_review: eKYC nghi ngờ / timeout ở lần thứ 3
  pending_ekyc --> rejected: eKYC không đạt
  pending_review --> active: GDV duyệt
  pending_review --> rejected: GDV từ chối
  pending_ekyc --> expired: chưa có credential sau 24h
  pending_review --> expired: chưa có credential sau 24h
  active --> expired: chưa có credential sau 24h (đóng TK active số dư 0)
```
Đăng nhập được: `active`, `pending_ekyc`, `pending_review` (chưa `active` chỉ xem trạng thái hồ sơ). `rejected`, `expired`: không đăng nhập.
`expired` giải phóng SĐT/CCCD để đăng ký lại; trong 24h đăng ký lại cùng SĐT + CCCD → hoàn tất hồ sơ cũ (idempotent).

### Tài khoản thanh toán (FR-6..8)
```mermaid
stateDiagram-v2
  [*] --> active: mở
  active --> debit_blocked: GDV khóa ghi Nợ
  active --> blocked: GDV khóa toàn bộ
  debit_blocked --> active: GDV mở khóa
  blocked --> active: GDV mở khóa
  debit_blocked --> blocked
  active --> closed: KH đóng (số dư 0, không tạm giữ)
  closed --> [*]
```
| Trạng thái | Ghi Nợ | Ghi Có |
|---|---|---|
| active | được | được |
| debit_blocked | từ chối | được |
| blocked | từ chối | từ chối |
| closed | từ chối | từ chối |

## R1

### BF-1. Đăng ký + eKYC
```mermaid
sequenceDiagram
  actor KH as Khách hàng
  participant API as banking-go
  participant EK as eKYC mock
  actor GDV
  KH->>API: đăng ký (SĐT, CCCD, ảnh, mật khẩu)
  API->>API: kiểm trùng SĐT/CCCD, băm mật khẩu, lưu ảnh vào object store
  API-->>KH: 202 pending_ekyc
  API->>EK: xác thực (bất đồng bộ)
  alt đạt
    EK-->>API: pass
    API->>API: Customer active + mở TK mặc định
  else nghi ngờ
    EK-->>API: suspicious
    API->>API: pending_review → hàng chờ GDV
    GDV->>API: duyệt / từ chối + lý do (audit log)
  else không đạt
    EK-->>API: fail → rejected + mã lý do
  else timeout
    API->>EK: hỏi lại (backoff, tối đa 3 lần gọi = 1 + 2 lần hỏi lại) → timeout ở lần thứ 3: pending_review
  end
```
Ngoại lệ: SĐT/CCCD trùng → 409, không tạo bản ghi; ảnh đã upload dọn theo lifecycle `kyc/`.

### BF-2. Nạp tiền
```mermaid
sequenceDiagram
  actor KH as Khách hàng
  participant API as banking-go
  participant GW as Cổng nạp mock
  KH->>API: tạo yêu cầu nạp (số tiền, idempotency key)
  API->>API: giao dịch pending
  API->>GW: tạo phiên nạp
  GW-->>API: callback có chữ ký (thành công / thất bại)
  alt chữ ký sai
    API-->>GW: 401, bỏ qua
  else callback lần đầu, thành công
    API->>API: hạch toán Nợ TT-cổng-nạp / Có TK KH → succeeded
  else callback trùng
    API-->>GW: 200, không ghi lại
  end
  Note over API: Không có callback sau thời hạn → unknown → BF-5
```

### BF-3. Chuyển nội bộ
```mermaid
sequenceDiagram
  actor KH as Khách hàng
  participant API as banking-go
  participant DB as Ledger (DB)
  KH->>API: chuyển (TK nguồn, TK đích, số tiền, idempotency key)
  API->>API: idempotency: key đã có → trả kết quả cũ
  API->>DB: BEGIN, khóa 2 TK theo thứ tự cố định
  API->>DB: kiểm trạng thái (nguồn ghi Nợ được, đích ghi Có được), số dư khả dụng ≥ số tiền
  alt hợp lệ
    API->>DB: ghi giao dịch kế toán Nợ nguồn / Có đích, COMMIT
    API-->>KH: succeeded
  else không hợp lệ
    API->>DB: payment.Transition(pending → failed, failure_code), COMMIT (không hạch toán)
    API-->>KH: failed (insufficient_funds / account_blocked / ...)
  end
```
Ngoại lệ: TK nguồn = TK đích → 422. Request đồng thời trên cùng TK được tuần tự hóa; không âm số dư.

### BF-4. Rút tiền
```mermaid
sequenceDiagram
  actor KH as Khách hàng
  participant API as banking-go
  participant GW as Cổng rút mock
  KH->>API: rút (số tiền, idempotency key)
  API->>API: kiểm TK + số dư khả dụng → tạo tạm giữ, giao dịch pending (một transaction DB)
  API->>GW: yêu cầu chi
  alt thành công
    GW-->>API: ok
    API->>API: hạch toán Nợ TK KH / Có TT-cổng-rút, giải phóng tạm giữ → succeeded
  else bị từ chối
    GW-->>API: reject
    API->>API: hủy tạm giữ → failed
  else timeout
    API->>API: giữ tạm giữ → unknown → BF-5
  end
```

### BF-5. Tra soát giao dịch unknown
```mermaid
sequenceDiagram
  participant JOB as Job tra soát
  actor GDV
  participant API as banking-go
  participant P as Đối tác mock
  loop theo backoff (hoặc GDV bấm tra soát)
    JOB->>P: hỏi trạng thái theo mã giao dịch
    alt có kết quả
      P-->>JOB: thành công / thất bại
      JOB->>API: chuyển trạng thái cuối + hạch toán hoặc hủy tạm giữ (idempotent)
    else vẫn chưa rõ
      P-->>JOB: unknown / timeout
    end
  end
  Note over JOB,GDV: Quá ngưỡng thời gian vẫn unknown → alert + hiện trong hàng chờ GDV
```

### BF-6. Khóa / đóng tài khoản
- Khóa/mở: GDV chọn mức (`debit_blocked` / `blocked`) + lý do → cập nhật trạng thái → audit log. Giao dịch đang `pending`/`unknown`
  vẫn đi tới kết quả cuối; giao dịch mới tuân theo bảng Ghi Nợ/Ghi Có.
- Đóng: KH yêu cầu → kiểm TK đang `active` (TK `debit_blocked`/`blocked` → `invalid_status_transition`, phải mở khóa trước), số dư = 0, không tạm giữ, không có giao dịch `pending`/`unknown` liên quan (cả tiền đến), không phải TK mặc định khi còn TK khác → `closed`.

### BF-7. Đăng nhập
- KH: SĐT + mật khẩu → access JWT 15 phút + refresh token xoay vòng. Sai 5 lần liên tiếp → khóa 15 phút. Đăng xuất → thu hồi refresh token. Chỉ trạng thái KH `active`/`pending_ekyc`/`pending_review` đăng nhập được; mọi lệnh tiền cần `active`.
- Admin: mật khẩu + TOTP → phiên, hết hạn sau 30 phút không thao tác. Mọi lần đăng nhập (đúng/sai) vào audit log.

## R2–R4 (khung)

### BF-8. Chuyển liên ngân hàng (R2)
Tra tên người nhận (NAPAS mock) → kiểm hạn mức → OTP nếu vượt ngưỡng → tính phí → tạm giữ tiền + phí → gửi NAPAS mock →
callback: thành công (hạch toán Nợ TK KH / Có TT-NAPAS + Có TK thu phí), thất bại (hủy tạm giữ), timeout (`unknown` → BF-5).

### BF-9. Maker-checker (R2)
Maker tạo yêu cầu (điều chỉnh số dư, khóa/mở TK, đổi hạn mức/phí) → `waiting_approval` → checker (≠ maker, đúng vai) duyệt → thực hiện;
từ chối → đóng kèm lý do; quá hạn → hết hiệu lực. Chưa duyệt thì chưa có hiệu lực.

### BF-10. Đối soát + EOD (R3)
Nhận file đối soát NAPAS mock → so khớp theo mã giao dịch → khớp / chỉ có bên ta / chỉ có bên đối tác / lệch số tiền → kế toán xử lý
(qua maker-checker) → EOD: khóa ngày kế toán, dồn tích lãi, kiểm bất biến, báo cáo cân đối, mở ngày kế toán mới.

### BF-11. Tiết kiệm (R4)
Mở sổ (Nợ TK thanh toán / Có TK tiết kiệm) → EOD dồn tích lãi hằng ngày → đến hạn tự tất toán về TK mặc định (gốc + lãi) →
trước hạn: đảo lãi đã dồn tích, tính lãi không kỳ hạn cho toàn bộ thời gian gửi.
