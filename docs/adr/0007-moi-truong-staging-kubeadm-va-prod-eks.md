# 0007. Môi trường: staging VPS kubeadm, prod AWS EKS ephemeral, GitOps Argo CD

- Trạng thái: Accepted (2026-10-05)
- Liên quan: AD-14, AD-26, AD-13

## Bối cảnh
Portfolio cần chứng minh cả hai kỹ năng: tự dựng và vận hành Kubernetes, và dùng managed cloud đúng cách. Ngân sách cá nhân không cho phép chạy AWS
liên tục. Staging phải chịu được mất một node để demo HA (CNPG 3 instance, RabbitMQ quorum). Không được có thay đổi ngoài Git, không fork manifest
theo môi trường. ingress-nginx đã retire (03/2026); MinIO CE đã archive; Bitnami chart/image không còn phù hợp.

## Các phương án đã cân nhắc
1. **Staging kubeadm 1 control-plane + 2 worker** (đề xuất ban đầu) — không đủ để 3 instance CNPG/RabbitMQ anti-affinity chịu mất một worker. Đã đổi.
2. **Prod chạy liên tục trên AWS** — tốn chi phí; bị loại. Prod dựng/hủy theo release/demo.
3. **CD dạng push (`helm upgrade` từ CI)** — đơn giản nhưng không có trạng thái mong muốn trong Git; user chọn GitOps Argo CD.
4. **Ingress API + ingress-nginx** — đã retire; chọn Gateway API v1.6 (Traefik staging, AWS Load Balancer Controller prod).
5. **Secrets**: prod theo nguyên tắc dùng dịch vụ AWS → External Secrets ← Secrets Manager. Staging ban đầu chỉ là giả định Sealed Secrets (user chưa
   chỉ định), sau đó được user chấp nhận.

## Quyết định
- Staging: VPS kubeadm, 1 control-plane (~4 GB, taint) + 3 worker (~8 GB); CNPG 3 instance và RabbitMQ 3 replica trải trên 3 worker bằng required
  anti-affinity; Elasticsearch, Kibana, Jaeger một replica, best-effort.
- Prod: EKS, RDS Multi-AZ, Amazon MQ, S3, KMS, Secrets Manager, OpenSearch, AMP/AMG, X-Ray — chỉ qua Terraform, dựng/hủy bằng job GitHub Actions sau
  environment có Required reviewers; version engine đặt tường minh.
- Một Helm chart mỗi deployable, values theo môi trường; SPA là image web server tĩnh trong cluster, đọc API base URL từ file config runtime.
- Argo CD sync cả hai cluster từ Git; không `kubectl apply` tay. Migration là PreSync Job.
- Kubernetes minor pin bằng nhau (1.36) trên hai cluster, nâng cùng lúc. Add-on chỉ cài qua operator/chart trong Stack; không Bitnami.
- App chỉ đọc config từ env var; secret đến dạng Kubernetes Secret (Sealed Secrets / External Secrets).

## Hệ quả
- Một bộ manifest cho hai môi trường; khác biệt nằm trong values file và Collector config.
- SLO/SM-3 đo liên tục trên staging; prod chỉ đo trong cửa sổ release/demo (ADR 0002).
- Dữ liệu prod là disposable khi destroy; chuỗi promote image staging → prod và registry (đã chốt: GHCR, promotion theo digest — `deployment.md`).
- Staging tự vận hành: patch OS, nâng kubeadm, backup etcd là việc của tác giả; capacity budget cần xem lại sau load test R3.
