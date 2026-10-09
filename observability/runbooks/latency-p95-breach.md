# LatencyP95Breach
- Mức / NFR / AD: warning · NFR-P1, NFR-P2, NFR-P3 · AD-13 · O-1

## Ý nghĩa
`sli:latency_p95:rate5m` của một `route_class` vượt ngưỡng SLO liên tục 10 phút: read 100 ms, write 300 ms, login 500 ms, transfer 200 ms.

## Tác động
Trải nghiệm chậm; transfer chậm kéo dài làm tăng timeout phía client.

## Kiểm tra (chỉ đọc)
- Dashboard Service overview, panel "Duration p95 (s)".
- PromQL: `histogram_quantile(0.95, sum by (http_route, le) (rate(http_server_request_duration_seconds_bucket{service_name="<svc>"}[5m])))`
- Trace chậm trong Jaeger (sắp theo duration); span DB/gRPC nào chiếm thời gian.
- core gRPC: `histogram_quantile(0.95, sum by (rpc_method, le) (rate(rpc_server_duration_milliseconds_bucket{service_name="core"}[5m])))`
- Deploy gần nhất (`git log -- deploy/releases/kind.yaml`), CPU throttling pod (`bin/kubectl -n banking top pods`).

## Xử lý
- Do deploy → đề xuất `rollback.yml` cho owner.
- Do tài nguyên kind → tăng `resources` trong `values-kind.yaml` qua PR.

## Không được làm
- Nới ngưỡng SLO/alert để tắt cảnh báo.

## Đóng sự cố
p95 dưới ngưỡng 30 phút liên tục; ghi nguyên nhân vào PR/`docs/incidents/` nếu ảnh hưởng demo.
