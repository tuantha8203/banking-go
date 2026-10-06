# Board — platform v1 — sprint S1

Tiến độ: **10/12 done** · 0 doing · 0 blocked · 0 dropped

## Doing

## Todo
- [ ] T11: `make kind-load kind-apps` — 10 chart chạy trên kind, Job migration Completed
- [ ] T12: `make kind-smoke` (4 host qua Traefik, Job migration, digest vs `deploy/releases/kind.yaml`)

## Blocked

## Done
- [x] T1: Pin CLI k8s/devops vào `./bin` (`make tools-k8s`)
- [x] T2: Subcommand `migrate up` (goose, migration embed) cho core/public-api/admin-api
- [x] T3: Dockerfile Go (core + core-worker, public-api, admin-api, mocks × 4) + `make images` + `make image-smoke`
- [x] T4: Dockerfile SPA + nginx + `config.js` runtime (`@banking-go/runtime-config`)
- [x] T5: Library chart phần 1 (Deployment, Service, ServiceAccount, ConfigMap) + helm-unittest
- [x] T6: Library chart phần 2 (HTTPRoute, PDB, migration PreSync Job, Certificate mTLS) + helm-unittest
- [x] T7: 10 chart mỏng + `values-kind.yaml` + `make helm-lint helm-test` (kubeconform k8s 1.36 + CRD catalog)
- [x] T8: kind config + `bootstrap.sh` (idempotent, khôi phục key Sealed Secrets, Argo CD) + `make kind-up kind-down`
- [x] T9: Add-on wave -30/-20/-19/-18 (Gateway API, cert-manager + ClusterIssuer, Sealed Secrets, Traefik, CNPG op, RabbitMQ ops) + catalog + `make kind-platform kind-ca`
- [x] T10: Data wave -15/-14 (CNPG `Cluster pg`, `RabbitmqCluster`, topology, SeaweedFS + bucket) + Sealed Secrets + `make seal`

## Dropped

