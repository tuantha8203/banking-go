# Watchdog
- Mức / NFR / AD: none (dead man's switch) · NFR-S7 gián tiếp · AD-13 · O-14

## Ý nghĩa
Alert `vector(1)` luôn firing. Telegram nhận tin `Watchdog` mỗi `repeat_interval` (12 h). Không còn nhận nghĩa là chuỗi
Prometheus → Alertmanager → Telegram đã hỏng và mọi alert khác cũng không tới.

## Tác động
Không ảnh hưởng khách hàng trực tiếp; mất khả năng phát hiện sự cố trên kind.

## Kiểm tra (chỉ đọc)
- `bin/kubectl -n monitoring get pods` — Prometheus, Alertmanager có Running?
- PromQL: `ALERTS{alertname="Watchdog",alertstate="firing"}` có 1 series?
- PromQL: `sum(alertmanager_notifications_failed_total{integration="telegram"})` có tăng?
- `bin/kubectl -n monitoring logs statefulset/alertmanager-kube-prometheus-stack-alertmanager -c alertmanager | grep -i telegram`
- Secret `monitoring/alertmanager-kind-config` tồn tại? (`bin/kubectl -n monitoring get secret alertmanager-kind-config`)

## Xử lý
- Token/chat id sai hoặc bot bị chặn → sửa `deploy/secrets/kind.env`, `make seal`, commit `deploy/secrets/kind/monitoring-alertmanager-kind-config.sealed.yaml` qua PR → Argo CD sync.
- Pod Prometheus/Alertmanager lỗi → sửa `deploy/platform/kube-prometheus-stack/values-kind.yaml` qua PR.

## Không được làm
- Silence hoặc xóa `Watchdog`; sửa Secret bằng `kubectl edit`; dán bot token vào issue/chat.

## Đóng sự cố
Tin `Watchdog` tới lại Telegram và `alertmanager_notifications_failed_total` không tăng trong 15 phút. Mất alerting > 1 h → ghi `docs/incidents/<yyyy-mm-dd>-watchdog.md`.
