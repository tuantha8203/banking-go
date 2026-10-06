# 0004. Transactional outbox + RabbitMQ

- Trạng thái: Accepted (2026-10-05)
- Liên quan: AD-7, AD-8, AD-15, AD-16

## Bối cảnh
Gọi đối tác không được nằm trong DB transaction (AD-7), nên sau tx1 cần một cơ chế bất đồng bộ tin cậy để core-worker thực hiện lệnh. Các service
cũng cần event chéo nhau (core → public-api: trạng thái/SĐT khách hàng; edge → core: audit event; admin-api: lệnh maker-checker). Yêu cầu: không mất
message sau commit, không publish khi chưa commit, xử lý trùng an toàn, event cũ không ghi đè trạng thái mới. Prod dùng managed service.

## Các phương án đã cân nhắc
1. **River (job queue trên PostgreSQL)** — transactional tự nhiên, không cần broker; nhưng là 0.x, chỉ dùng được trong một DB, không phục vụ event
   giữa các service có DB riêng. User chọn không dùng.
2. **Kafka** — mạnh cho event streaming, nhưng nặng cho staging VPS và vượt nhu cầu (không cần replay log dài hạn). Bị loại.
3. **Publish thẳng lên broker sau commit** — mất message nếu crash giữa commit và publish. Bị loại.
4. **Transactional outbox trong DB mỗi service + RabbitMQ 4.3** (chọn); prod Amazon MQ for RabbitMQ (managed, hỗ trợ 4.3, quorum queue).

## Quyết định
- Service ghi message vào bảng `outbox` của chính nó trong cùng UoW với thay đổi trạng thái. Relay của core chỉ chạy ở core-worker; mỗi edge chạy relay
  in-process. Relay claim bằng `FOR UPDATE SKIP LOCKED` theo `(aggregate_id, seq)`, publish rồi đánh dấu đã gửi.
- At-least-once: consumer ghi `message_id` vào `inbox` cùng UoW với hiệu ứng, bỏ trùng, ack sau commit; `Qos(prefetch, 0, false)`; quorum queue durable.
- Event `banking.<context>.<entity>.<past_verb>.v<major>` trên topic exchange `banking.events`, CloudEvents `subject` + `aggregateversion`; consumer giữ
  version cuối theo subject, bỏ bản cũ. Command `banking.<module>.<command_verb>.v<major>` trên direct exchange `banking.commands`, một queue mỗi loại.
- Retry qua `banking.retry.<n>` → `<queue>.dlq`; độ sâu DLQ có alert. Topology khai báo một lần trong `deploy/messaging`.
- Staging: RabbitMQ Cluster Operator, 3 replica; prod: Amazon MQ `mq.m7g.large`, `CLUSTER_MULTI_AZ`.

## Hệ quả
- Không mất và không publish "ma"; đổi lại có độ trễ relay và phải vận hành thêm broker.
- Mọi consumer phải idempotent và không giả định thứ tự; test chaos phải bao gồm redelivery và message trùng.
- Bảng `outbox`/`inbox` tăng dần → cần job purge trong service sở hữu.
- Đổi nghĩa event phải bump `<major>` và dual-publish trong lúc chuyển; `buf breaking` bảo vệ payload (ADR 0005).
