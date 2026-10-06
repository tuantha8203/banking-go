# 0005. Hợp đồng API: REST code-first Huma v2 ở edge, gRPC/protobuf nội bộ và event

- Trạng thái: Accepted (2026-10-05)
- Liên quan: AD-6, AD-9, AD-12

## Bối cảnh
Hai SPA cần client TypeScript luôn khớp server; hai edge gọi core đồng bộ; event qua RabbitMQ cần schema có kiểm tra breaking change. Mã lỗi nghiệp vụ
phải ổn định từ core tới UI (SPA dịch theo `code`, AD-9). Mock đối tác phải giống đối tác thật (HTTP/JSON + webhook), không dùng giao thức nội bộ.

## Các phương án đã cân nhắc
1. **OpenAPI contract-first** (viết YAML, sinh server bằng oapi-codegen/ogen) — hợp đồng rõ trước code, nhưng tốn công đồng bộ YAML và handler; user chọn
   code-first thay thế.
2. **Connect (connectrpc) cho cả SPA và nội bộ** — một schema protobuf cho tất cả, nhưng API công khai kém tự nhiên với REST/OpenAPI và hệ sinh thái
   client admin. Bị loại.
3. **REST nội bộ giữa edge và core** — mất kiểu mạnh và `buf breaking`. Bị loại.
4. **REST code-first (Huma v2 trên chi, xuất OpenAPI 3.1) ở edge + gRPC/protobuf (buf) nội bộ và cho payload event** (chọn).

## Quyết định
- Mỗi edge xuất `api/openapi/<service>.yaml` (OpenAPI 3.1) từ code Huma, commit vào repo; CI fail nếu có diff chưa commit. SPA sinh client bằng
  openapi-typescript + openapi-fetch.
- gRPC service và payload event là protobuf trong `/proto`, build bằng buf; `buf breaking` chạy trong CI so với nhánh mặc định.
- REST lỗi theo RFC 9457 với `code` ổn định. Core đặt mã nghiệp vụ trong `google.rpc.ErrorInfo.reason` (domain `banking-go`); edge chép nguyên vào problem
  `code`, không ánh xạ lại.
- REST: `/v1/...`, camelCase JSON, cursor pagination; mutating call bắt buộc `Idempotency-Key`, edge chuyển tiếp qua gRPC metadata.
- Đối tác (mock) dùng REST/JSON + webhook HMAC; gRPC chỉ giữa các service của mình.

## Hệ quả
- OpenAPI luôn phản ánh code thật; người review thấy thay đổi hợp đồng qua diff YAML.
- Hai công cụ schema (OpenAPI + protobuf) cần giữ ánh xạ field/mã lỗi nhất quán ở edge adapter.
- Thay đổi breaking ở proto bị chặn sớm; thay đổi breaking ở REST cần review diff YAML (chưa có breaking checker tự động cho OpenAPI).
- Option proto đánh dấu field nghiệp vụ được dùng để tính `request_hash` (AD-6) và `requires_approval` (AD-20).
