# Foundation changelog

| Version | Ngày | Phần đổi | Tóm tắt | ADR |
|---|---|---|---|---|
| v1 | 2026-10-06 | Tất cả (tạo mới) | Product, glossary, business flows, design system, architecture (spine AD-1..AD-26), data model, API contracts, NFR, constitution, deployment, observability | 0001–0010 |
| v2 | 2026-10-06 | deployment (+ spine AD-14) | Thêm môi trường `kind` (GitOps/Helm/observability trên máy dev) cho feature platform v1 | 0011 |
| v3 | 2026-10-06 | deployment | Cập nhật phiên bản: cosign v3; URL chart Sealed Secrets `bitnami.github.io/sealed-secrets` (không đổi quyết định) | — |
| v4 | 2026-10-09 | deployment | Repo GitHub public, package GHCR public (bỏ pull secret `ghcr-pull`, D-31 sửa), thêm D-37 (repo public trên gói Free), D-38 (cấm `pull_request_target`, fork PR không nhận secret) | 0012 |
