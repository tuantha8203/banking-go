# 0010. Object store ảnh eKYC và mã hóa PII (envelope + blind index)

- Trạng thái: Accepted (2026-10-05)
- Liên quan: AD-19, AD-24, AD-25

## Bối cảnh
Đăng ký cần lưu ảnh CCCD + selfie cho eKYC (mock-ekyc đọc ảnh để xác thực); R3 cần lưu file đối soát. Ảnh không được nằm trong DB nghiệp vụ, log, event
hay audit. SĐT và CCCD là PII phải mã hóa at rest, nhưng vẫn cần tra cứu và ràng buộc unique (đăng ký, đăng nhập, tra cứu nhân viên). Staging cần
object store S3-compatible tự dựng; MinIO CE đã archive (04/2026).

## Các phương án đã cân nhắc
1. **Lưu ảnh trong PostgreSQL (bytea)** — phình DB, backup nặng, ảnh lẫn vào dữ liệu nghiệp vụ. Bị loại.
2. **MinIO CE trên staging** — bản cộng đồng đã archive, không còn bản vá. Bị loại.
3. **Mã hóa PII bằng pgcrypto / mã hóa cột trong DB** — khóa nằm cạnh dữ liệu, tra cứu phải giải mã từng dòng. Bị loại.
4. **SeaweedFS (staging) / S3 SSE-KMS (prod) qua S3 API; PII envelope encryption + HMAC blind index trong `pkg/crypto`** (chọn).

## Quyết định
- Object store truy cập chỉ qua S3 API, endpoint từ config: staging SeaweedFS 4.48 (chart chính thức), prod Amazon S3 SSE-KMS; một bucket mỗi môi trường.
  Core sở hữu bucket, prefix, lifecycle, retention.
- Prefix `kyc/`: public-api chỉ có quyền ghi (upload lúc đăng ký, khóa theo `registration_id`); core và core-worker chỉ đọc `kyc/`; core-worker cấp
  presigned GET TTL ngắn cho mock-ekyc; core stream ảnh cho admin-api (không presigned URL ra trình duyệt). Prefix `recon/` (R3) do core sở hữu. DB chỉ lưu object key.
- SĐT, CCCD (hồ sơ core và bản `login_phone` của public-api) và TOTP secret mã hóa envelope: data key AES-256-GCM, bọc bằng KEK (prod KMS, staging Sealed
  Secret); ciphertext mang key id để xoay khóa không cần ghi lại.
- Tra cứu/unique trên SĐT/CCCD dùng cột blind index HMAC-SHA256 trên giá trị chuẩn hóa, khóa HMAC riêng mỗi service; unique constraint đặt trên blind index.
- Mật khẩu argon2id; refresh token, session id lưu dạng hash; log che SĐT/CCCD còn 4 số cuối.

## Hệ quả
- Ảnh tách khỏi DB và backup DB; quyền truy cập theo prefix giới hạn thiệt hại khi một service bị lộ.
- Unique và tra cứu không cần giải mã; đổi lại không tìm kiếm gần đúng/tiền tố trên SĐT/CCCD được.
- Xoay KEK an toàn nhờ key id; xoay khóa HMAC blind index cần tính lại cột (chưa có kế hoạch, ít khi cần).
- Thời hạn lưu/xóa ảnh eKYC (đã chốt: 5 năm kể từ khi KH `rejected`/`expired` hoặc TK cuối cùng `closed` — `nfr.md`), thực thi bằng lifecycle bucket.
- Backup CNPG cũng dùng SeaweedFS → object store staging là thành phần cần giám sát dung lượng.
