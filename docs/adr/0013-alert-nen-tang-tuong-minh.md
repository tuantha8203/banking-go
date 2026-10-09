# 0013. Alert nền tảng khai báo tường minh thay `defaultRules` của kube-prometheus-stack

- Trạng thái: Accepted (2026-10-09)
- Liên quan: AD-13, ADR 0008, ADR 0011, `observability.md` § Alert catalog, § Runbooks, feature `platform` v1 (T14, T17)

## Bối cảnh
`observability.md` (v1) dự kiến staging giữ rule mặc định của kube-prometheus-stack (node, pod crashloop, PVC đầy) ở mức
warning. Rule mặc định không có nhãn `service`/`runbook_url` theo quy ước của dự án và không có runbook, nên không qua được
`make runbooks-test` và không có promtool unit test. platform v1 tắt `defaultRules` và cần cảnh báo crashloop + Argo CD Degraded.

## Các phương án đã cân nhắc
1. Khai báo tường minh trong `observability/alerts/platform.yaml`, mỗi alert có runbook + promtool test — chọn.
2. Bật `defaultRules` của chart — hàng chục rule không runbook, nhãn không thống nhất, nhiễu.
3. Bật `defaultRules` nhưng lọc bằng `disabled:` — vẫn không có runbook/test cho phần còn lại.

## Quyết định
Không dùng `defaultRules`. Alert nền tảng là rule tường minh trong `observability/alerts/`, có `severity`, `service`,
`runbook_url`, runbook theo khung và promtool unit test: hiện có `PodCrashLooping`, `ArgoCDAppDegraded` (cùng `Watchdog`,
`TelemetryPipelineDegraded`, `Certificate*`). Rule node/PVC đầy thêm theo cùng cách khi dựng staging (v2).

## Hệ quả
- Mọi alert đều có runbook và test; `make runbooks-test` bắt `runbook_url` treo.
- Phải tự viết rule cho node/PVC/kubelet khi cần (chưa có ở v1, kind không cam kết SLO).
