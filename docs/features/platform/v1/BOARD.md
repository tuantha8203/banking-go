# Board — platform v1 — sprint S3

Tiến độ: **1/4 done** · 0 doing · 1 blocked · 0 dropped

## Doing

## Todo
- [ ] T20: `rollback.yml` (env=kind, revert_sha)
- [ ] T21: Argo CD app-of-apps `deploy/argocd/kind/` + bootstrap GitOps + nghiệm thu tiêu chí 1–6

## Blocked
- [ ] T19: `main.yml`: build → Trivy → push → SBOM + cosign → bot bump `deploy/releases/kind.yaml` — Chờ owner (Owner trước, plan T19): tạo repo GitHub public, `git remote add origin`, push; GitHub App bg-release-bot + var BG_RELEASE_BOT_CLIENT_ID + secret BG_RELEASE_BOT_PRIVATE_KEY; ruleset main (PR + ci, bypass bot); Workflow permissions = Read; sau push đầu đặt 6 package GHCR public; `gh auth login` trên máy để AI theo dõi run. Code + test local đã xong.

## Done
- [x] T18: `ci.yml`: build 6 image (không push), deploy lint/test, observability test, actionlint

## Dropped

