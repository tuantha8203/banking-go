# 0008. Observability qua OTel Collector theo môi trường

- Trạng thái: Accepted (2026-10-05)
- Liên quan: AD-13, AD-14

## Bối cảnh
Cần metrics, logs, traces cho cả hai môi trường với backend khác nhau (tự dựng trên staging, managed AWS trên prod) mà không đổi code. Lựa chọn ban đầu
của user: metrics → Prometheus/Grafana; logs → Logstash → Elasticsearch → Kibana; traces → Jaeger. Jaeger v1 đã EOL (12/2025). Alert phải giống nhau
giữa hai môi trường; invariant FR-13 và `recon_conflict` là critical.

## Các phương án đã cân nhắc
1. **SDK riêng từng backend trong code** (Prometheus client, ES client, Jaeger client) — khóa vendor, hai môi trường lệch instrumentation. Bị loại.
2. **Giữ Logstash trong pipeline log** — thêm một thành phần JVM nặng trên VPS mà Collector đã làm được (parse, export thẳng ES). Bị loại.
3. **Prod tự dựng cùng stack staging** — trái nguyên tắc prod dùng managed service. Bị loại.
4. **App chỉ gửi OTLP tới OTel Collector (contrib); Collector chọn backend theo môi trường** (chọn).

## Quyết định
- Service dùng OpenTelemetry Go SDK, xuất OTLP tới otelcol-contrib; không SDK riêng của backend. Trace context truyền qua HTTP, gRPC metadata và header
  RabbitMQ. Log JSON qua `log/slog` + otelslog, có `trace_id`, `span_id`, `service`, `env`.
- Staging: Prometheus 3 + Grafana pin 12.4 (kube-prometheus-stack), Elasticsearch/Kibana 9.5 (ECK), Jaeger v2 (storage ES). Bỏ Logstash.
- Prod: `otlphttp` + `sigv4auth` tới X-Ray (Transaction Search) và OpenSearch Ingestion → OpenSearch Service; remote write tới AMP; dashboard trên AMG 12.4.
- Alert rule dạng Prometheus trong `observability/alerts/`, nạp vào Prometheus/Alertmanager (staging) và AMP ruler (prod); nhãn `critical|warning`.
  Dashboard theo schema Grafana 12.4 dùng chung hai môi trường.

## Hệ quả
- Đổi backend chỉ là đổi config Collector; code không biết backend.
- Grafana staging bị pin 12.4 (không lên 13.x) để dùng chung dashboard với AMG; nâng khi AMG hỗ trợ bản mới.
- otelslog bridge còn 0.x, có thể breaking khi nâng.
- Elasticsearch/Jaeger single-replica trên staging: mất node có thể mất telemetry, chấp nhận vì không phải dữ liệu nghiệp vụ.
- Alert receiver theo môi trường (đã chốt: critical → Telegram + email, warning → email — `observability.md`).
