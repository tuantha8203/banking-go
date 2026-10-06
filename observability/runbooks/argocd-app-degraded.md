# ArgoCDAppDegraded
- Mức / NFR / AD: warning · NFR-A5 · AD-14 · ADR 0011

## Ý nghĩa
Application Argo CD (`argocd_app_info`) ở `Degraded` hoặc `Missing` 15 phút: rollout kẹt quá `progressDeadlineSeconds`, PreSync migration fail, hoặc add-on không healthy.

## Tác động
Phiên bản mới không lên (bản cũ vẫn chạy nếu migration fail); add-on hỏng có thể ảnh hưởng mọi app.

## Kiểm tra (chỉ đọc)
- `bin/kubectl -n argocd get applications`; `bin/kubectl -n argocd get application <name> -o jsonpath='{.status.conditions}'`
- UI `https://argocd.kind.localhost` → app → resource đỏ, Events.
- Migration: `bin/kubectl -n banking logs job/<svc>-migrate`.
- Commit gây ra: `git log --oneline -5 -- deploy/`.

## Xử lý
- Digest lỗi → owner chạy `rollback.yml -f env=kind -f revert_sha=<bump_sha>`.
- Config lỗi → PR revert commit config.

## Không được làm
- Sync tay với `--force`/`--replace`, tắt auto-sync/selfHeal để "chạy tạm", `kubectl apply` tay.

## Đóng sự cố
Mọi Application `Synced/Healthy` (`deploy/kind/wait-argocd.sh`), `make kind-smoke` pass.
