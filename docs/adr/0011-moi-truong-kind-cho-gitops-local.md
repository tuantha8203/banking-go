# 0011. Môi trường `kind` để thử GitOps, Helm và observability trước staging

- Trạng thái: Accepted (2026-10-06)
- Liên quan: AD-13, AD-14, ADR 0007, feature `platform` v1

## Bối cảnh
Staging (VPS kubeadm) và prod (AWS) chưa có hạ tầng. Feature `platform` v1 cần kiểm chứng chart Helm, Argo CD app-of-apps,
add-on platform, pipeline digest bump, rollback và observability ngay, không phụ thuộc VPS/AWS. Môi trường "Local dev"
hiện là docker compose, không chạy Kubernetes.

## Các phương án đã cân nhắc
1. Môi trường `kind` riêng (deploy/argocd/kind, values-kind.yaml, deploy/releases/kind.yaml) — chọn.
2. Cho kind tạm đóng vai `staging` — values-staging phải vừa nhẹ cho máy dev vừa đủ cho VPS; staging.yaml trỏ vào máy cá nhân.
3. Không coi kind là môi trường, sync tay — không kiểm chứng được luồng bot bump + Argo CD + rollback.

## Quyết định
Thêm môi trường `kind`: kind 1.36 trên máy dev (1 CP + 2 worker), add-on platform giống staging bản nhẹ (1 replica, không ECK,
Jaeger in-memory, log Collector ra debug). `main.yml` bump `deploy/releases/kind.yaml` cùng digest với staging; Argo CD trên kind
kéo GitHub bằng deploy key chỉ đọc. `rollback.yml` nhận `env=kind`. Không cam kết SLO/HA trên kind.

## Hệ quả
- Mỗi chart có thêm `values-kind.yaml`; lib chart và add-on dùng chung với staging, v2 chủ yếu đổi values + dựng VPS.
- Máy dev cần ~6–7 GB RAM trống khi bật kind.
- Sealed Secrets key của kind sống theo cluster; bootstrap backup/khôi phục key ngoài repo.
