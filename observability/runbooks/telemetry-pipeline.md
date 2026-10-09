# TelemetryPipelineDegraded
- Mức / NFR / AD: warning · NFR-M (quan sát được) · AD-13 · O-7, O-8

## Ý nghĩa
OpenTelemetry Collector (`observability/otel-collector`) đang lỗi khi export (metric/trace/log) hoặc không còn được scrape (`up{job="otel-collector"}` mất) trong 10 phút.

## Tác động
Mất metric RED/trace: alert SLO không còn đáng tin, dashboard trống; ứng dụng vẫn chạy.

## Kiểm tra (chỉ đọc)
- `bin/kubectl -n observability get pods`; `bin/kubectl -n observability logs deploy/otel-collector | tail -50`
- PromQL: `sum by (exporter) (rate({__name__=~"otelcol_exporter_send_failed_.*"}[5m]))`, `otelcol_exporter_queue_size`
- Backend: Prometheus (`kube-prometheus-stack-prometheus`) và Jaeger (`jaeger`) có Running?
- `make collector-validate` với config hiện tại.

## Xử lý
- Sửa `deploy/collector/kind.yaml` hoặc values backend qua PR (chạy `make collector-validate` trước) → Argo CD sync.

## Không được làm
- Cho service gửi thẳng tới backend (bỏ Collector, trái AD-13); tắt processor `redaction`.

## Đóng sự cố
Không còn `send_failed` 15 phút, `up{job="otel-collector"} == 1`, kind-smoke phần telemetry pass.
