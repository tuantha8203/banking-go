---
review: rubric-walk
target: ../ARCHITECTURE-SPINE.md
inputs: [../../../../../business-flows.md, ../../../../../product.md, ../../../prds/prd-banking-go-2026-10-05/prd.md, ../.memlog.md]
reviewer: rubric walker (good-spine checklist)
date: 2026-10-05
verdict: revise-before-build
---

# Rubric review: ARCHITECTURE-SPINE (banking-go)

## Verdict

The money core is well specified. AD-4, AD-5, AD-6, AD-7 and AD-8 are concrete, mostly enforceable, and match business-flows.md's general rules. The weak spots are the edge/core seams. Several flows cross the public-api / admin-api / core boundary, and no AD fixes how they work: registration, authorization of admin-owned use cases, maker-checker enforcement, OTP step-up, and the transaction shared across module ports inside core. The security and operations parts of the operational envelope are also thin: sensitive-data encryption, object storage, backups, migrations, probes, and whether the staging topology can pass the failover tests. **Revise before feature build.** 0 critical, 7 high, 11 medium, 7 low.

## Rubric scorecard

| Checklist item | Result | Notes |
| --- | --- | --- |
| Fixes the real divergence points for independently built units, misses none | Partial | Misses registration split (F-2), cross-module tx (F-1), admin-api authZ (F-3), maker-checker enforcement (F-4), business-day timezone (F-9), probes/migrations (F-11, F-12) |
| Every AD Rule is enforceable and prevents its stated divergence | Mostly | AD-4 grants are unenforceable without a role split (F-10); AD-5 omits hold placement (F-8); AD-10 contradicts its own "Prevents" (F-3); AD-15 conflicts with AD-1 (F-14) |
| Nothing under Deferred lets two units diverge | Mostly | "CDN/static hosting" deferral conflicts with AD-1/AD-14 (F-21). Maker-checker *shape* can be deferred, but its *enforcement point* cannot (F-4) |
| Covers PRD capabilities and business-flows rules | Partial | FR-1 object store absent (F-5); "mã hóa dữ liệu nhạy cảm" absent (F-6); BF-8 name inquiry and OTP step-up (F-15); eKYC timeout vs AD-7 wording (F-13) |
| Every owned dimension decided / deferred / open: deployment & envs | Partial | Image registry, promotion, DNS/TLS, migration execution undecided (F-12, F-19) |
| ... infra strategy | Partial | Staging capacity and quorum vs node count (F-7) |
| ... operations | Weak | Backups/PITR/RPO, probes, graceful shutdown, alert routing, SLO-measurement constraint (F-7, F-11, F-17, F-18) |
| ... security | Weak | Encryption at rest/field, key mgmt, internal-token key distribution, SPA token storage/CSRF, scanning (F-6, F-16, F-20) |
| No contradictions with memlog / business-flows | Minor issues | F-7 (memlog L21 vs CNPG 3 + quorum), F-13 (AD-7 vs customer state machine), F-17 (memlog L20 missing), F-22 (OpenSearch Ingestion, gitleaks) |
| Open questions carried | Missing | The spine has no Open Questions section, so PRD §8 items are not carried (F-23) |

---

## Findings

### F-1 [high] Cross-module transaction inside core is undecided, and AD-3 and AD-4 pull against each other
- **Location:** AD-3 (last sentence), AD-4, Consistency Conventions "Transactions"
- **Issue:** AD-3 says a core module touches only its own tables and calls other modules through their `app` port. AD-4 requires the journal to be written "in one DB transaction together with its business record". The business record lives in `payment`/`savings` and the journal lives in `ledger`, so every money use case crosses a module port inside one transaction. The spine never says how that transaction travels through ports. One team may pass a `pgx.Tx` or unit-of-work through `context`. Another may let `ledger` open its own transaction, which silently breaks atomicity. Nothing enforces the module-table boundary either. This is the main divergence point of a modular monolith, and it bears directly on money correctness (SM-1).
- **Fix:** Add an AD such as "AD-16 Unit of work in core". The use case in the *initiating* module opens the transaction with `uow.Do(ctx, func(ctx) error)`. Port methods of other modules take that `ctx` and must run on the ambient transaction (`db.FromCtx(ctx)`). They never call `Begin`. Enforce module boundaries two ways: one PostgreSQL schema per module (`ledger.*`, `payment.*`), and a depguard/import-lint rule that forbids `internal/<a>/...` from importing `internal/<b>/{domain,adapters}`, so only `internal/<b>/app` may be imported.

### F-2 [high] Registration and login span public-api and core with no defined protocol
- **Location:** AD-1 (ownership), Capability map rows FR-1..3 and FR-4; BF-1 step "kiểm trùng SĐT/CCCD, băm mật khẩu, lưu ảnh"
- **Issue:** FR-1 creates a password credential, which public-api owns, and a customer profile with eKYC state, which core owns, in a single request. BF-1 draws one "API" doing both. The spine does not decide:
  - who enforces SĐT uniqueness (SĐT is the login identifier in public-api *and* a profile field in core);
  - the write order and what compensates if the second write fails;
  - how public-api maps SĐT to `customer_id`;
  - whether login is allowed for `pending_ekyc` / `rejected` / `pending_review` customers, and how public-api learns customer state changes. The diagram shows only core-worker consuming from MQ.

  Two implementers will build two different registration sagas.
- **Fix:** Add a rule. For example: public-api's `Register` validates the password policy, then calls core `CreateCustomer` (idempotent on the forwarded key) and gets `customer_id` back. core enforces SĐT/CCCD uniqueness. public-api then stores the credential keyed by `customer_id` + SĐT in its own transaction. An orphan core customer with no credential is harmless and is swept by a job. Core publishes `banking.customer.customer.{activated,rejected}`, and public-api consumes it (via the inbox) to enable or disable login. Also state the login policy per customer state, or record it as an open question for the PRD.

### F-3 [high] AD-10 "AuthZ in core" cannot cover admin-api-owned use cases, so two permission models exist
- **Location:** AD-10, AD-1 (admin-api owns admin users, roles, maker-checker requests), Capability map FR-20..22
- **Issue:** FR-21 requires every admin API to check permission by role with default deny. FR-22 (create/lock admin users, assign roles, "no self-assign") and the R2 maker-checker requests are owned and executed in admin-api, so core never sees them. admin-api must therefore authorize too. That is exactly the "two permission models" AD-10 claims to prevent. Role names are owned by admin-api, while the role→permission mapping core enforces is not placed anywhere.
- **Fix:** Rewrite AD-10. The role→permission matrix lives in one place, either a shared `pkg/authz` policy file versioned in `/proto` or core as the single PDP with a `Authorize(actor, action, resource)` gRPC. Both admin-api (for its own use cases) and core (for core use cases) evaluate that same policy, default deny. FR-22's "no self-assignment" is a policy rule in that matrix. Update "Prevents" to match.

### F-4 [high] Maker-checker is enforced only at the edge, so core cannot tell an approved command from a direct one
- **Location:** AD-2 (last sentence), AD-1, Capability map R2 row, Deferred bullet 1
- **Issue:** BF-9 says "Chưa duyệt thì chưa có hiệu lực". AD-2 says the approval in admin-api "executes by calling a core command". Core is the authorizer (AD-10), but it gets no evidence that the command was approved, by whom, or that checker ≠ maker. A buggy or compromised admin-api, or a GDV role allowed to call `AdjustBalance` directly, would bypass maker-checker. This is the exact threat AD-10 lists. The approve→execute step also crosses services with no rule on retries or partial failure (approved in admin DB, core call failed). Deferring the request *shape* is fine. The *enforcement point and execution protocol* are divergence points and cannot be deferred.
- **Fix:** Add a rule. Commands that are subject to maker-checker are callable in core only with an `approval` claim in the internal token: `request_id`, `maker_id`, `checker_id`, `request_hash`. Core rejects them otherwise, verifies `maker_id ≠ checker_id` and the checker role, and stores the approval in its audit record. admin-api executes with `Idempotency-Key = request_id`, has states `approved → executing → executed | execution_failed`, and retries via its outbox. Alternative: move maker-checker requests into core and keep only the UI in admin-api.

### F-5 [high] No object store anywhere, although FR-1/BF-1 require one
- **Location:** AD-1 (deployables/ownership), Deployment diagram, Stack, Structural Seed
- **Issue:** FR-1 says "Ảnh không lưu trong DB nghiệp vụ; chỉ lưu tham chiếu tới kho object", and BF-1 says "lưu ảnh vào object store". The spine has no S3 (prod), no MinIO or other store (staging), and no owner. Unresolved questions include: which service uploads (registration enters via public-api, but core owns eKYC); how mock-ekyc gets the images (presigned URL vs bytes); encryption and retention. Without an AD, public-api and core will each pick their own. R3 recon files (BF-10) need the same infrastructure.
- **Fix:** Add the object store to the infra strategy (prod S3 with SSE-KMS and a bucket per env; staging MinIO or a CNPG-adjacent S3-compatible store) and to the stack table. Add an ownership rule. Example: core owns the `ekyc-documents` bucket; public-api streams the upload to core (or gets a presigned PUT from core); the DB stores only the object key; mock-ekyc receives a short-TTL presigned GET; images never appear in logs, traces or audit (consistent with AD-11).

### F-6 [high] Sensitive-data protection is not decided (product.md success criterion)
- **Location:** Missing. Should sit next to AD-10/AD-11, plus a Conventions row.
- **Issue:** product.md "Tiêu chí thành công / Bảo mật" lists "mã hóa dữ liệu nhạy cảm", and SM-4 requires OWASP Top 10 to be clean. The spine covers log masking only. Several things are undecided:
  - encryption at rest (RDS/CNPG storage, S3);
  - field-level encryption for CCCD, phone, TOTP secrets and refresh tokens;
  - key management (KMS in prod, what in staging);
  - how FR-24 lookup by SĐT/CCCD works if those fields are encrypted (blind index/HMAC).

  Each module will choose differently, and lookup and uniqueness (F-2) depend on the choice.
- **Fix:** Add an AD such as "AD-17 Sensitive data". Example content:
  - storage encryption is on everywhere (RDS/EBS/S3 with KMS; CNPG on encrypted volumes);
  - CCCD and phone are envelope-encrypted with a `pkg/crypto` helper and searched or uniqueness-checked through an HMAC-SHA256 blind-index column;
  - TOTP secrets are encrypted, and refresh tokens are stored hashed;
  - keys come from KMS (prod) or a Sealed Secret (staging) and rotate via a key-id prefix;
  - TLS terminates at Gateway/ALB, and internal traffic uses mTLS (already in AD-10).

### F-7 [high] The staging topology cannot meet the failover/quorum promises it is meant to prove
- **Location:** Deployment diagram (STG subgraph), memlog L21 ("kubeadm 3 node (1 control-plane + 2 worker ~8GB), test mất node được"), memlog L20, SM-2/SM-3
- **Issue:** memlog L20 says SLO and failover are measured continuously on **staging**. The staging cluster has 2 schedulable workers, but the spine places CNPG 1 primary + 2 replicas and RabbitMQ quorum queues there. Quorum queues need 3 nodes to tolerate losing one. With 2 workers, losing one node can lose a majority of the RabbitMQ replicas or 2 of 3 PG instances, so the "test mất node được" claim and the SM-3 "phục hồi < 1 phút" test are not achievable as drawn. Also, 2×8 GB has to hold ES+Kibana, Prometheus/Grafana, Jaeger, 3 PG, RabbitMQ, 10 deployables with replicas, and a 500 TPS k6 run (SM-2). Nothing states capacity or anti-affinity. Separately, prod uses "RDS Multi-AZ". A Multi-AZ *instance* fails over in about 60–120 s, which can miss the "< 1 phút" figure if SM-3 is ever demonstrated on prod.
- **Fix:** Decide one of these and record it in the spine: (a) make the control plane schedulable (untaint) and give CNPG/RabbitMQ `podAntiAffinity` across all 3 nodes; or (b) use 3 workers. State the capacity budget, and that ES/Jaeger are single-replica best-effort. Add a line that SLO/failover evidence is produced on staging (memlog L20). For prod, choose "RDS Multi-AZ **DB cluster**" (2 readable standbys, about 35 s failover) or state explicitly that SM-3 is not measured on prod.

### F-8 [medium] AD-5 locks only on "posting", but hold placement/release also changes `available_balance`
- **Location:** AD-5 Rule
- **Issue:** BF-4/BF-8 place holds in tx1, before any posting. If an implementer places a hold without `FOR UPDATE` on the customer account, a concurrent internal transfer and withdrawal can both pass the available-balance check. AD-5's scope is "A posting transaction", so that implementation would comply.
- **Fix:** Change the wording to "Any transaction that changes a customer account's `balance`, `available_balance`, holds or status takes `SELECT … FOR UPDATE` on that account, in ascending `account_id` order". Add a DB `CHECK (available_balance >= 0)` as a backstop.

### F-9 [medium] Business-day and timezone semantics are undecided (daily limits, EOD, accrual, statements)
- **Location:** Consistency Conventions "Time"
- **Issue:** The convention "`timestamptz` UTC; `business_date` (DATE)" does not say which timezone defines a day (UTC vs Asia/Ho_Chi_Minh), who assigns `business_date` to a journal, or what happens to postings made while EOD has the day locked (BF-10). Several modules depend on this: R2 daily limits ("hạn mức theo ngày"), R4 daily accrual, FR-9 statement date ranges and R3 EOD. They will diverge, and retrofitting `business_date` onto R1 journals later is costly.
- **Fix:** Add conventions. Calendar days are Asia/Ho_Chi_Minh. Every journal carries `business_date`, taken from a single core `calendar` port (open business date). Postings arriving while EOD has a date locked go to the next open date. Daily limits use the calendar day in ICT. Make the column mandatory from R1.

### F-10 [medium] AD-4/AD-11 "DB grants enforce no UPDATE/DELETE" cannot be enforced without a role split
- **Location:** AD-4, AD-11, AD-3 (one role per DB)
- **Issue:** AD-3 gives each service a single role. If that role owns the tables, as it does when goose runs as the same role, it can always UPDATE/DELETE whatever the grants say.
- **Fix:** For each database, define a `<svc>_migrator` role that owns the tables and runs goose, and a `<svc>_app` runtime role with `INSERT, SELECT` only on `journals`, `entries` and `audit_logs`. Add a CI test that asserts `UPDATE entries` fails under the app role.

### F-11 [medium] No convention for health probes, graceful shutdown or the readiness of relays and consumers
- **Location:** Consistency Conventions (missing rows); AD-14
- **Issue:** One Helm chart per deployable (AD-14) depends on probe paths and shutdown behaviour. With several replicas, these matter for correctness too: draining in-flight gRPC calls, stopping the outbox relay and AMQP consumers before closing the DB pool, and acking only after commit. Each service will choose differently.
- **Fix:** Add a row. Every Go service exposes `/livez` and `/readyz` on an admin port (readiness includes DB and broker), handles SIGTERM with a drain timeout below `terminationGracePeriodSeconds`, stops consumers and the relay first, and acks a message only after the inbox+effect transaction commits.

### F-12 [medium] Migration execution and schema-change compatibility are undecided
- **Location:** AD-14, Stack (goose); memlog L35
- **Issue:** Nothing says who runs goose (init container, Argo CD PreSync Job, or app startup), and nothing requires expand/contract compatibility while multiple replicas roll. With ephemeral prod rebuilt from Terraform, bootstrap order matters too: DB, then migrations, then apps. Each chart will do it differently.
- **Fix:** Rule: migrations run as an Argo CD `PreSync` hook Job per service using the `_migrator` role (F-10). Every migration must be backward-compatible with the previous release (expand → deploy → contract). App pods never migrate.

### F-13 [medium] AD-7 binds BF-1, but its "timeout → unknown, only reconciliation finalizes" wording contradicts the customer state machine
- **Location:** AD-7 Binds/Rule vs business-flows.md "Khách hàng" state machine and BF-1
- **Issue:** For eKYC, a timeout means retry with backoff, at most 3 times, and then `pending_review`. There is no `unknown` and BF-5 reconciliation is not used. Read literally, AD-7 pushes eKYC into the transaction `unknown` path.
- **Fix:** Scope the sentence about `unknown` to money transactions (FR-18). Add: "Non-money partner calls follow their own state machine in business-flows.md (eKYC: retry ≤ 3 with backoff, then `pending_review`)." Keep the tx1/outbox/tx2 shape for both.

### F-14 [medium] AD-15 puts all periodic jobs in core-worker, but edges own jobs too
- **Location:** AD-15 vs AD-1, AD-6 (retention), BF-9
- **Issue:** BF-9 maker-checker expiry ("quá hạn → hết hiệu lực") belongs to admin-api. Idempotency-record purge (AD-6) and expired refresh-token cleanup belong to each service. AD-15 says periodic jobs run in core-worker, and core-worker cannot touch the `public` or `admin` databases (AD-3).
- **Fix:** Change the rule to "Each owning service runs its own periodic jobs (in-process scheduler or a `cmd/<svc>-worker`), each guarded by a PostgreSQL advisory lock named `<svc>.<job>`, and idempotent per window." Also allow lazy expiry: an expired request is treated as expired at read time.

### F-15 [medium] R2 synchronous partner interactions (NAPAS name inquiry, OTP step-up) have no home
- **Location:** AD-12 (Binds: mocks, core-worker), system diagram (only WRK → MOCK), Capability map R2 row
- **Issue:**
  - BF-8 name lookup is a synchronous read the UI needs immediately, but AD-7/AD-12 route every partner call through core-worker.
  - public-api owns OTP sessions (AD-1), while core decides whether OTP is required (limits/pricing). Core then has to trust a "verified OTP" assertion from the edge. That claim must be bound to the specific transfer, or a valid OTP could be replayed for another transfer.
  - The diagram never shows public-api → mock-otp.
- **Fix:**
  - Allow synchronous, read-only partner calls (name inquiry) from core's adapter with a timeout and no DB transaction open. This is consistent with AD-7.
  - Add an R2 rule for step-up. Core returns `OTP_REQUIRED` with a `challenge_id` bound to the request hash. public-api verifies with mock-otp and re-calls with `otp: {challenge_id, verified_at}` in the internal token. Core checks the binding.
  - Add public-api → mock-otp to the diagram and to AD-12 Binds.

  If you would rather not decide now, list both as Open Questions for R2.

### F-16 [medium] Internal-token trust and secret lifecycle are not specified
- **Location:** AD-10, AD-12, AD-14
- **Issue:** AD-10 leaves open several things core needs to verify edge-signed EdDSA tokens: how it learns each edge's public key, how keys rotate, and how system actors (core-worker jobs, reconciliation) are represented. AD-12 HMAC secrets between mocks and worker have no rotation or key-id. `x-actor` lacks client IP and user agent, which AD-11 requires in audit records, so each edge will pass them its own way.
- **Fix:** Rule: each edge publishes its public keys via a mounted JWKS Secret with a `kid` (rotation means overlapping kids), and core pins the issuer per edge. Add `ip` and `user_agent` to the internal-token claims. Define a `system:<job>` actor type for worker-initiated commands. HMAC headers carry `key-id` + timestamp, and requests are rejected after 5 minutes (replay window).

### F-17 [medium] Backups, PITR and RPO/RTO are undecided; memlog's SLO-measurement constraint is not carried
- **Location:** Deployment diagram, AD-14; memlog L20
- **Issue:** Money data needs a stated backup and PITR position: CNPG Barman to the object store, RDS automated backups and retention, and the RPO/RTO behind SM-3 "không mất giao dịch đã succeeded". Ephemeral prod also needs a statement such as "prod data is disposable per demo window". memlog L20 ("SLO 99.9% đo liên tục trên staging; prod đo trong cửa sổ release/demo") is a decision with operational impact, but it is missing from the spine.
- **Fix:** Add an "Operations" sub-section or AD. Staging: CNPG continuous WAL archive to MinIO/S3 with daily base backups, and a PITR restore drill once per release. Prod: RDS automated backups, retention N days, data discarded on destroy. RPO = 0 for committed transactions (synchronous replica: CNPG `minSyncReplicas: 1`; Multi-AZ). Copy memlog L20 in verbatim.

### F-18 [medium] Alert routing and on-call path are absent (FR-13 "critical alert", DLQ alert, unknown threshold)
- **Location:** AD-8 (DLQ depth alerted), AD-5/FR-13, Deferred bullet 4, Structural seed `observability/alerts`
- **Issue:** Several ADs say "alert", but nothing says where alerts go: Alertmanager on staging vs AMP alert manager → SNS on prod, or which receiver (email/Telegram/Slack). Alert rules authored per service may not work in both backends.
- **Fix:** Decide that alert rules are Prometheus-format files in `observability/alerts/`, loaded by Prometheus/Alertmanager on staging and by the AMP ruler on prod. Name one receiver per env. Severity labels are `critical|warning`, and FR-13 violations are `critical`.

### F-19 [low] Image registry and staging→prod promotion are undecided
- **Location:** Deployment diagram ("image push", "image tag commit"), AD-14
- **Issue:** The registry (GHCR vs ECR) is not named, and neither is EKS pull auth. It is also unclear which values file CI bumps, and whether prod deploys the same digest that passed staging.
- **Fix:** For example: GHCR, images referenced by digest; CI bumps `values-staging.yaml`; promotion to prod is a PR copying the digest to `values-prod.yaml`.

### F-20 [low] SPA session handling and CI security scanning are not pinned (SM-4)
- **Location:** AD-10, Stack, Deployment diagram (GHA "scan")
- **Issue:** It is undecided where web-customer keeps access/refresh tokens (memory + httpOnly SameSite cookie vs localStorage), as are CSRF/CORS policy and admin session cookie flags. The "scan" step in CI is unnamed. gitleaks is verified in memlog L11 but missing from the stack, and SAST/DAST/image-scan tools are not listed either.
- **Fix:** Add a Conventions row: access token in memory, refresh token in an httpOnly `Secure SameSite=Strict` cookie scoped to `/v1/auth`, CORS allow-list per env. Add gitleaks, govulncheck, Trivy (image) and OWASP ZAP baseline (staging) to the stack.

### F-21 [low] "CDN/static hosting for SPAs" is deferred, but AD-1/AD-14 already make SPAs Helm deployables
- **Location:** Deferred bullet 5 vs AD-1, AD-14
- **Issue:** If deployment.md later picks CloudFront+S3 for prod, AD-14's "one Helm chart per deployable" breaks for the SPAs, and API base URL/CORS handling will differ between envs.
- **Fix:** Decide now (e.g., SPAs are static nginx images in-cluster in both envs, with runtime `config.json` for the API base URL), or carve the SPAs out of AD-14 explicitly.

### F-22 [low] Small drift from memlog
- **Location:** Deployment diagram PRD subgraph; Stack
- **Issue:** memlog L18 says prod logs go "OpenSearch Ingestion → OpenSearch Service + Dashboards", but the diagram shows Collector → OpenSearch directly. gitleaks (memlog L11) and cert-manager (AD-10) are missing from the Stack table. EKS "latest EKS-supported" vs staging 1.37 leaves API-version drift open. memlog L9 promises `docs/foundation/architecture.md` (C4) as a companion, but `companions: []`.
- **Fix:** Add OpenSearch Ingestion to the diagram. Add cert-manager and gitleaks with versions. Pin EKS to the same minor as staging, or state "staging tracks the EKS-supported minor". List architecture.md under `companions` once it exists.

### F-23 [low] No Open Questions section; PRD §8 and other undecided items are not carried
- **Location:** Spine structure
- **Issue:** PRD §8 lists default limits/OTP threshold (R2), the NAPAS recon file format (R3) and interest rate/rounding (R4). Rounding in particular is a money rule that savings and EOD must share. Login policy per customer state (F-2) is also open. Deferred covers some of these, but not interest rounding or customer-state login.
- **Fix:** Add `## Open Questions` with those items, each with an owner and the release that must close it. Constrain rounding now: "interest computed in integer đồng; rounding mode decided once in core `pricing` and reused by `savings`/`eod`".

### F-24 [low] Idempotency concurrent-same-key behaviour and `scope` are unspecified
- **Location:** AD-6
- **Issue:** Two simultaneous requests with the same key can both miss the lookup. The spine does not say whether the loser blocks, gets 409 `idempotency_in_progress`, or relies on a unique-violation retry. `scope` is undefined: it should include the actor so keys from two customers never collide. "Every mutating REST call" also sweeps in login/logout, which is stricter than FR-14 ("API tạo giao dịch") and may not be intended.
- **Fix:** Define `scope = <actor_id>:<operation>`, add a unique constraint on `(scope, key)`, and say the losing concurrent request returns 409 `idempotency_in_progress` (retryable). Either list auth endpoints as exempt or keep them in deliberately.

### F-25 [low] Cross-boundary error-code transport not fixed
- **Location:** AD-9, Conventions "Errors (Go)"
- **Issue:** Core's stable domain codes must reach the RFC 9457 `code` at the edge. Without a rule, each edge maps gRPC status differently.
- **Fix:** Core puts the domain code in `google.rpc.ErrorInfo.reason` (domain `banking-go`) with params in `metadata`. Edges copy them verbatim into problem `code`/params and never re-map business codes.

---

## Coverage check (PRD / business-flows → spine)

| Item | Covered by | Gap |
| --- | --- | --- |
| FR-1 register (uniqueness, argon2id, object store) | AD-1 partial | F-2, F-5, F-6 |
| FR-2/3 eKYC + review | AD-7, AD-12, AD-11 | F-13 |
| FR-4 customer login, lockout | AD-1, AD-10 | F-2 (state-gated login), F-20 |
| FR-5 Luhn number | Conventions IDs | ok |
| FR-6..8 accounts, block/close | AD-2, AD-5 | F-8 |
| FR-9 statement with balance-after | AD-4 | not decided whether `balance_after` is stored on entry or computed; low risk, folds into F-1's AD |
| FR-10..13 ledger, internal accounts, holds, invariants | AD-4, AD-5, AD-15 | F-8, F-10; seeding of internal ledger accounts (FR-11) unassigned (migration seed in `ledger`) |
| FR-14 idempotency | AD-6 | F-24 |
| FR-15..19 deposit/transfer/withdraw/states/recon | AD-5..AD-8, AD-15 | ok |
| FR-20..22 admin auth, roles, users | AD-1, AD-10 | F-3 |
| FR-23 audit | AD-11 | F-16 (IP) |
| FR-24 staff lookup | AD-2, AD-10 | F-6 (search on encrypted fields) |
| R2 interbank/OTP/limits/fees/maker-checker | AD-2, AD-7 | F-4, F-15, F-9 |
| R3 recon/EOD/500 TPS/failover | AD-5, AD-7, AD-15 | F-5 (recon file intake), F-7, F-9 |
| R4 savings | AD-2, AD-4, AD-15 | F-9, F-23 (rounding) |
| BF general rules 1–5 | AD-6, AD-4, AD-7, AD-4 | ok |
| Product "mã hóa dữ liệu nhạy cảm", runbook/postmortem | — | F-6, F-17 |

## What is good (keep)
- AD-4/AD-5's hot-account strategy (lock only customer accounts, derive internal balances) is concrete and matches memlog L25.
- AD-7 closely follows business-flows rules 3–4 and partner idempotency (our txn id as the partner key).
- AD-8 outbox+inbox with same-transaction inbox writes is the right enforceable shape.
- AD-13 OTLP-only plus Collector-per-env removes backend drift between staging and prod cleanly.
- AD-14 GitOps-only plus a Terraform-only, reviewer-gated prod matches memlog L19/L37.
