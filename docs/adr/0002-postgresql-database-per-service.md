# 0002. PostgreSQL 18, database-per-service trên một cluster

- Trạng thái: Accepted (2026-10-05)
- Liên quan: AD-3, AD-14, AD-26

## Bối cảnh
Ba service có dữ liệu riêng (core, public-api, admin-api) cần cách ly dữ liệu thật sự, nhưng chạy nhiều cluster DB trên staging VPS (RAM giới hạn)
là quá nặng. Staging tự dựng trên Kubernetes; prod dùng managed service của AWS, dựng/hủy theo release. Chỉ tiêu SM-3 yêu cầu kill DB primary dưới tải
không mất giao dịch `succeeded`, phục hồi < 1 phút.

## Các phương án đã cân nhắc
1. **Một DB chung, phân quyền bằng schema** — dễ, nhưng dễ trượt thành join chéo service; quyền DB khó tách sạch. Bị loại.
2. **Mỗi service một cluster** — cách ly tối đa, tốn tài nguyên gấp ba trên staging. Bị loại.
3. **Một cluster mỗi môi trường, mỗi service một database + role riêng** (chọn).
4. Prod: **RDS Multi-AZ DB cluster** (failover ~35 s) hoặc **Aurora** so với **RDS Multi-AZ DB instance** (failover ~60–120 s). Chọn instance cho đơn giản
   và rẻ vì prod là môi trường tạm thời; DB cluster để hoãn (spine Deferred).

## Quyết định
- PostgreSQL 18; staging CloudNativePG 1.30 (3 instance, ≥ 1 synchronous standby, anti-affinity trên 3 worker); prod RDS PostgreSQL 18.6 Multi-AZ DB instance.
  Image CNPG pin 18.x khớp engine RDS.
- Databases `core`, `public`, `admin`; mỗi database có `<svc>_migrator` (sở hữu schema, chạy goose) và `<svc>_app` (chỉ DML). Không service nào đọc DB của service khác.
- Trong core: một schema mỗi module; bảng hạ tầng `outbox`, `inbox`, `idempotency_keys` ở schema `platform`, chỉ ghi qua `pkg/*`.
- Trên `journals`, `entries`, `audit_records` role app chỉ có INSERT, SELECT; CI test khẳng định UPDATE/DELETE thất bại.
- Migration chạy bằng Argo CD PreSync Job, tương thích ngược một release (expand → deploy → contract).
- **SM-3 và SLO 99.9% chỉ cam kết và đo trên staging (CNPG).** Prod ghi nhận failover RDS 60–120 s, không cam kết SM-3.

## Hệ quả
- Cách ly thật ở mức database + role, chi phí chỉ một cluster mỗi môi trường.
- Truy vấn cần dữ liệu nhiều service phải đi qua gRPC hoặc projection từ event (vd. public-api giữ projection SĐT/trạng thái KH).
- Staging chịu được mất một worker; backup WAL + base backup về SeaweedFS, diễn tập PITR mỗi release.
- Báo cáo failover trong portfolio phải nói rõ là số đo trên staging, không phải prod.
- Hai môi trường khác engine vận hành (operator so với managed) → cần giữ version và tham số kết nối đồng bộ qua values file.
