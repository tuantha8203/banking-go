# PodCrashLooping
- Mức / NFR / AD: warning · NFR-A5 · AD-26

## Ý nghĩa
Một container ở trạng thái `CrashLoopBackOff` liên tục 15 phút (kube-state-metrics).

## Tác động
Rollout mới kẹt (pod cũ vẫn phục vụ nhờ `maxUnavailable: 0`) hoặc add-on mất khả dụng.

## Kiểm tra (chỉ đọc)
- `bin/kubectl -n <namespace> describe pod <pod>`; `bin/kubectl -n <namespace> logs <pod> -c <container> --previous`
- Config/Secret thiếu (`CreateContainerConfigError`, env `BG_<SVC>_*`), OOMKilled (`lastState.terminated.reason`).
- Deploy gần nhất (`git log -- deploy/releases/kind.yaml deploy/helm`).

## Xử lý
- Do image/config mới → đề xuất `rollback.yml` (digest) hoặc PR revert values.
- OOMKilled → tăng `resources.limits.memory` trong `values-kind.yaml` qua PR.

## Không được làm
- `kubectl delete pod` lặp lại để "cho qua"; sửa Deployment bằng `kubectl edit`.

## Đóng sự cố
Pod Ready ổn định 15 phút, restart không tăng; nguyên nhân là bug → test tái hiện + fix.
