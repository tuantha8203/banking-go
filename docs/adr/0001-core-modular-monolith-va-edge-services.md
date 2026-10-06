# 0001. core modular monolith + edge services có nghiệp vụ riêng

- Trạng thái: Accepted (2026-10-05)
- Liên quan: AD-1, AD-2, AD-3, AD-16

## Bối cảnh
banking-go cần chứng minh "đúng tiền" bằng số liệu: tổng Nợ = tổng Có mọi lúc, chaos test 0 lệch, 0 nhân đôi. Chuyển nội bộ phải ghi nợ một tài khoản và
ghi có tài khoản khác nguyên tử. Đồng thời sản phẩm có hai nhóm người dùng (khách hàng, nhân viên) với cơ chế xác thực và quy trình rất khác nhau
(JWT + OTP so với session + TOTP + maker-checker). Đây là dự án một người làm, cần độ phức tạp vận hành vừa phải nhưng vẫn thể hiện ranh giới service rõ.

## Các phương án đã cân nhắc
1. **Microservices theo bounded context** (customer, account, ledger, payment... mỗi cái một service + DB). Ranh giới đẹp trên giấy nhưng chuyển nội bộ
   thành saga phân tán; mỗi bước cần bù trừ, khó chứng minh 0 lệch. Bị loại.
2. **Ledger service tách riêng**, các service nghiệp vụ gọi ledger để hạch toán. Vẫn cần saga giữa giao dịch (payment) và bút toán (ledger), kiểm tra
   số dư + tạm giữ bị tách khỏi trạng thái giao dịch. Bị loại.
3. **Một binary với hai listener** (public + admin) trong cùng process. Đơn giản nhất, nhưng credential khách hàng, phiên admin và tiền nằm chung một
   process và một DB; một lỗi ở phần admin có thể chạm thẳng bảng tiền. Bị loại.
4. **core modular monolith + edge services mỏng nhưng có nghiệp vụ riêng** (chọn).

## Quyết định
- **core** là modular monolith hexagonal, sở hữu mọi thứ chạm tiền: `customer`, `account`, `ledger`, `payment`, `pricing`, `savings`, `eod`, `recon`, `audit`;
  mỗi module một Postgres schema, chỉ gọi nhau qua `app` port trong cùng Unit of Work (AD-16). depguard chặn import `domain`/`adapters` chéo module.
- **core-worker** cùng codebase, cùng DB với core (`cmd/` riêng): outbox relay, consumer, job định kỳ, webhook đối tác. Không phải owner thứ hai.
- **public-api** sở hữu credential KH, refresh token, thiết bị, lockout, rate limit, (R2) phiên OTP. **admin-api** sở hữu user admin, vai, TOTP,
  phiên admin, (R2) yêu cầu maker-checker. Edge không đọc DB core, không tính tiền (AD-2); tích hợp qua gRPC đồng bộ hoặc event.
- Mock đối tác (napas, ekyc, otp, gateway) là deployable riêng; core không import code mock.

## Hệ quả
- Mọi thao tác tiền nằm trong một transaction ACID của một DB → không có saga, invariant FR-13 kiểm được bằng một truy vấn snapshot.
- Ranh giới module trong core phải giữ bằng lint + review, không phải bằng mạng; vi phạm (SQL chạm schema module khác) làm fail CI.
- core là điểm scale chung cho mọi luồng tiền; đạt 500 TPS dựa vào nhiều replica core + chiến lược khóa (ADR 0003), không dựa vào tách service.
- Có thêm 2 DB và 2 deployable edge cần vận hành, nhưng đổi lại credential/phiên tách khỏi tiền và dễ minh họa ranh giới trust (ADR 0006).
- Nếu sau này cần tách module (vd. `recon`) thành service, port `app` đã là ranh giới sẵn; khi đó phải chấp nhận saga cho phần tách ra.
