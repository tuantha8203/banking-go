# ErrorBudgetBurnFast / ErrorBudgetBurnSlow
- Mức / NFR / AD: critical (fast) · warning (slow) · NFR-A1 · AD-13, AD-26

## Ý nghĩa
Tỷ lệ lỗi (`sli:error_ratio:<window>`: 5xx / request không 4xx ở edge; mã gRPC lỗi server ở core) đốt error budget
30 ngày (SLO 99.9%) nhanh (14.4× trong 1 h, 6× trong 6 h) hoặc đều (3× trong 1 ngày, 1× trong 3 ngày).

## Tác động
Khách hàng/nhân viên gặp lỗi khi gọi API; tiếp diễn sẽ phá SLO tháng.

## Kiểm tra (chỉ đọc)
- Dashboard `banking-go / Service overview (RED)`: service nào, từ lúc nào, panel "Errors (5xx ratio)".
- PromQL: `sum by (service_name, http_route, http_response_status_code) (rate(http_server_request_duration_seconds_count{http_response_status_code=~"5.."}[5m]))`
- Trace lỗi trong Jaeger (`https://jaeger.kind.localhost`, service tương ứng, tag `error=true`).
- Deploy gần nhất: `git log --oneline -5 -- deploy/releases/kind.yaml`; Argo CD app có `Degraded`?
- Phụ thuộc: pod `pg-1`, `rmq-server-0`, Collector (`bin/kubectl -n banking-data get pods`).

## Xử lý
- Do deploy mới → owner chạy `gh workflow run rollback.yml -f env=kind -f revert_sha=<bump_sha>` (AI chỉ đề xuất lệnh).
- Do hạ tầng (DB, broker) → xử lý theo runbook tương ứng, sửa qua Git.

## Không được làm
- AI tự chạy rollback; tăng timeout hoặc nới SLO để che lỗi; `kubectl` sửa tay tài nguyên.

## Đóng sự cố
`sli:error_ratio:rate1h` < 0.001 trong 1 h và alert resolved. Nguyên nhân là bug → test tái hiện + fix qua PR (constitution II.1); ghi `docs/incidents/`.
