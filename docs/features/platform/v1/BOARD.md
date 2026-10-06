# Board — platform v1 — sprint S2

Tiến độ: **5/6 done** · 0 doing · 1 blocked · 0 dropped

## Doing

## Todo

## Blocked
- [ ] T16: Alertmanager → Telegram (critical + Watchdog) từ Sealed Secret + `amtool` test — Chờ owner: thêm TELEGRAM_BOT_TOKEN và TELEGRAM_CHAT_ID vào deploy/secrets/kind.env (bot @BotFather + chat id; không dán token vào chat). `make seal` hiện in skip monitoring/alertmanager-kind-config. Đã xong (commit part 1): template observability/alertmanager/kind.yaml, scripts/render-alertmanager.sh, wiring seal-kind.sh; make alertmanager-test ok. Còn lại sau khi có env: make seal (tạo deploy/secrets/kind/monitoring-alertmanager-kind-config.sealed.yaml) → thêm configSecret: alertmanager-kind-config vào kube-prometheus-stack values-kind.yaml (plan Step 3; chưa thêm vì thiếu Secret sẽ làm Alertmanager hỏng) → kind-platform → kind-smoke §7. Owner kiểm deploy/secrets/kind.env.example đã có dòng TELEGRAM_* chưa (AI không được đọc deploy/secrets/; file đã chứa chữ TELEGRAM nên AI không sửa).

## Done
- [x] T22: Sửa lỗi nhỏ sau review S1 (R1, R2, R3, R4, F5, F6 — `review.md`)
- [x] T13: kube-prometheus-stack + Jaeger v2 + OTel Collector (`deploy/collector/kind.yaml`) + route vận hành + smoke telemetry
- [x] T14: Alert rule v1 + recording rule SLI + promtool unit test + `PrometheusRule` sinh ra
- [x] T15: Dashboard `service-overview` + `platform` + scrape CNPG/RabbitMQ/Argo CD + test
- [x] T17: Runbook + `make kind-watch`

## Dropped

