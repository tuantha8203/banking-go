# 0014. Argo CD kéo Git qua HTTPS không credential (thay deploy key SSH)

- Trạng thái: Accepted (2026-10-09)
- Thay thế: câu "Argo CD trên kind kéo GitHub bằng deploy key chỉ đọc" của ADR 0011
- Liên quan: D-44 (repo public), D-46 (`deployment.md`), ADR 0011, ADR 0012, feature `platform` v1 (T21)

## Bối cảnh
ADR 0011 cho Argo CD trên kind kéo GitHub bằng deploy key SSH chỉ đọc; `deployment.md` có secret "Argo CD repo deploy key"
cho mọi env. Mạng công ty chặn SSH tới GitHub (owner đã thử `github.com:22` và `ssh.github.com:443`: timeout). Từ foundation
v4 repo là public (D-44), nên Git đọc được qua HTTPS mà không cần credential. Pod trong kind không có proxy công ty.

## Các phương án đã cân nhắc
1. HTTPS không credential (repo public) + proxy cho argocd-repo-server từ env máy — chọn.
2. HTTPS + PAT/GitHub App token — thêm secret phải xoay vòng mà repo public không cần.
3. Giữ SSH deploy key qua bastion/tunnel — phức tạp, phụ thuộc mạng công ty.

## Quyết định
Argo CD ở mọi môi trường dùng `repoURL: https://github.com/<owner>/banking-go.git`, không repo Secret. Trên kind,
`deploy/kind/bootstrap.sh` tạo ConfigMap `argocd/argocd-repo-server-proxy` (`HTTPS_PROXY`/`HTTP_PROXY` từ `ARGOCD_PROXY_URL`
hoặc `HTTPS_PROXY` của máy; `NO_PROXY` = no_proxy của máy + dải service/pod/docker network của kind, `.svc`,
`.cluster.local`, `kind.localhost`); values Argo CD trong Git chỉ tham chiếu bằng `envFrom` `optional: true`. Tên proxy nội bộ
không vào repo public.

## Hệ quả
- Bỏ secret "Argo CD repo deploy key" ở staging/prod/kind; ít secret phải xoay vòng.
- Kéo Git ẩn danh chịu rate limit của GitHub cho git/HTTPS (đủ cho chu kỳ reconcile 60 s của một repo).
- Nếu sau này repo trở lại private: cần credential HTTPS (token GitHub App chỉ đọc) — quyết định mới.
- Máy không có proxy: không tạo ConfigMap (hoặc `ARGOCD_PROXY_URL=`), repo-server kết nối trực tiếp.
