---
review_of: ARCHITECTURE-SPINE.md (banking-go, 2026-10-05)
lens: versions-and-reality-check
reviewer: BMAD architecture reviewer (versions lens)
date: 2026-10-05
verdict: needs-changes (no blockers to the paradigm; Stack table has unpinned and incompatible rows)
---

# Review: version and reality check

## Verdict

The memlog's `version` entries hold up: every pinned version I re-checked exists and is the current release.
The weak spots are the rows the memlog never checked:
- Staging is pinned to **Kubernetes 1.37**, a version no core add-on supports yet.
- Several components the spine depends on have **no version at all**: cert-manager, Node.js, Gateway API CRDs, the Collector distribution, how the staging data stores are installed, and the TypeScript OpenAPI generator.
- Two rows are **not real pins**: `pnpm: current LTS` and `EKS: latest EKS-supported`.
- There is **staging/prod version drift** in Grafana.

None of this changes the paradigm. It is all Stack-table and add-on hygiene.

## Method

- Read the spine (Stack table, AD-3, AD-9, AD-10, AD-13, AD-14, deployment diagram) and the four `(version)` entries in `.memlog.md`.
- Re-checked the memlog versions against live sources (`git ls-remote` tags, npm registry, go.dev, nodejs.org), then checked every Stack or AD-referenced item **not** covered by the memlog against official docs and release pages.
- Severity: **High** means it will break or block the build substrate if left as is. **Medium** means drift or ambiguity that an implementing agent will trip over. **Low** means a caveat to record. **Info** means confirmed, with nothing to do.

## Memlog spot-check (already web-verified, re-confirmed today)

| Item | Spine | Live latest (2026-10-05) | Status |
|---|---|---|---|
| Go | 1.27.x | go1.27.1 (go.dev/dl) | OK |
| Vite / AntD | 8.3 / 6.6 | 8.3.2 / 6.6.5 (npm) | OK |
| chi / Huma | v5.3 / v2.39 | v5.3.2 / v2.39.1 | OK |
| Prometheus / Grafana | 3.15 / 13.2 | v3.15.0 / v13.2.3 | OK |
| RabbitMQ | 4.3 | v4.3.6 | OK |
| Terraform / Helm / golangci-lint | 1.16 / v4.3 / v2.14 | v1.16.5 / v4.3.0 / v2.14.0 | OK |
| Argo CD / Traefik / CNPG | v3.5 / v3.7 / 1.30 | v3.5.3 / v3.7.13 / v1.30.1 | OK |
| Sealed Secrets / ESO / AWS LBC | v0.40 / 2.11 / v3.5 | v0.40.0 / v2.11.0 / v3.5.0 | OK |
| OTel Collector / Jaeger / ES | v0.162 / v2.21 / 9.5 | v0.162.0 / v2.21.0 / v9.5.4 | OK |

Every memlog version claim I re-checked is correct and current.

## Findings

### F-1 [High] Staging Kubernetes 1.37 is ahead of the add-on support matrix

- **Item:** Stack row `Kubernetes (staging kubeadm / EKS) | 1.37 / ...`. The add-ons named in AD-3, AD-10 and AD-14 must run on that cluster.
- **Evidence:** Kubernetes 1.37 was released upstream on 2026-08-26. The memlog checked that 1.37.1 exists, but not whether the add-ons support it:
  - cert-manager 1.21 (latest, v1.21.2) supports and tests **K8s 1.33–1.36**. The 1.22 release is "~Nov 2026, TBD". https://cert-manager.io/docs/releases/
  - CloudNativePG 1.30 supports **K8s 1.34–1.36**, and lists 1.37 only as "tested, but not supported". https://cloudnative-pg.io/docs/devel/supported_releases
  - Argo CD 3.5 is tested on **K8s 1.33–1.36**. https://github.com/argoproj/argo-cd/blob/v3.5.3/docs/operator-manual/tested-kubernetes-versions.md
  - ECK (if used for Elasticsearch, see F-6) is documented as compatible with **K8s 1.31–1.36**. https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s
- **Impact:** The money database (CNPG), the mTLS certificates (cert-manager) and the GitOps controller (Argo CD) would all run on an unsupported platform. Any issue we hit becomes "unsupported configuration".
- **Fix:** Pin staging to **Kubernetes 1.36.x** (latest patch), and pin EKS to 1.36 as well (see F-2). Add a Deferred line: "move to 1.37 when cert-manager ≥1.22, CNPG ≥1.31 and Argo CD ≥3.6 list it as supported."

### F-2 [Medium] `EKS: latest EKS-supported` is not a pin

- **Item:** Stack row for EKS.
- **Evidence:** EKS released 1.37 on 2026-10-01. Standard support now covers 1.34–1.37, and 1.34 standard support ends 2026-12-02. https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html
- **Impact:** Prod is ephemeral: Terraform creates and destroys it per release or demo. "Latest" means each apply can land on a different minor version, which may differ from staging and from what the add-ons support (same problem as F-1). That breaks the parity AD-14 relies on ("one Helm chart, values per env").
- **Fix:** Pin `cluster_version = "1.36"` in Terraform and in the Stack row (the same minor as staging). Bump both together on purpose.

### F-3 [Medium] `pnpm: current LTS`: pnpm has no LTS line

- **Item:** Stack row `pnpm | current LTS`.
- **Evidence:** pnpm publishes majors with no LTS designation. The npm dist-tags show `latest` = **12.9.1**, with `latest-11` = 11.28.2 and `latest-10` = 10.34.6 still maintained. pnpm 12.0.0 shipped 2026-08-26, and 11 and 10 reach end of life on 2027-04-30. https://registry.npmjs.org/pnpm and https://endoflife.date/pnpm
- **Impact:** The row cannot be resolved as written, and agents will pick different majors. Lockfile formats differ between majors, so CI and local installs will disagree.
- **Fix:** Pin `pnpm 12.9.x` (or `11.28.x` if a less-than-six-week-old major is too fresh). Set it through the root `package.json` `"packageManager": "pnpm@12.9.1"`, and use `pnpm/action-setup` in CI. Don't rely on Corepack, which Node no longer bundles from v25 onward.

### F-4 [Medium] Required components with no Stack row

The spine depends on these, but the Stack table gives no version (and none is in the memlog):

| Missing row | Why it matters | Suggested pin (verified 2026-10-05) |
|---|---|---|
| **cert-manager** (AD-10 mTLS) | Its K8s support window drives F-1 | v1.21.x (latest v1.21.2), https://cert-manager.io/docs/releases/ |
| **Node.js** (Vite 8, pnpm) | Vite 8.3.2 needs `^20.19 \|\| >=22.12` (npm `engines`) | **Node 24.x LTS "Krypton"** (latest 24.21.0). Node 26 is still "Current" until its late-Oct-2026 LTS promotion. https://nodejs.org/dist/index.json |
| **Gateway API CRDs** (AD-14) | Traefik v3.7 is built for Gateway API **v1.6.1**; AWS LBC v3.5 for **v1.6.0** and requires CRDs installed before the controller | Standard channel **v1.6.x** on both clusters (latest v1.6.2). https://doc.traefik.io/traefik/v3.7/reference/install-configuration/providers/kubernetes/kubernetes-gateway/ and https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/ |
| **OTel Collector distribution** | AD-13 needs `elasticsearch` exporter, `sigv4auth` extension, `prometheusremotewrite`/OTLP to AMP and `otlphttp` to X-Ray/OSIS. These ship in **contrib** (or ADOT), not the core distribution | `otelcol-contrib` v0.162.0 (or a custom `ocb` build pinned to v0.162.0) |
| **TS OpenAPI client generator** (AD-9) | Huma v2.39 emits **OpenAPI 3.1** by default (it can also serve a 3.0.3 downgrade); the generator must accept 3.1 | Name one (e.g. openapi-typescript or @hey-api/openapi-ts) and pin it |
| **otelslog bridge** (AD-13 slog→OTel) | The log API and SDK are v1.47.0, but the bridge is **v0.21.0 (0.x, may break)** | Pin `go.opentelemetry.io/contrib/bridges/otelslog v0.21.x` and record that it is 0.x |
| **AWS managed engine versions** | Terraform must set engine versions explicitly | RDS PostgreSQL **18.6** (available), Amazon MQ RabbitMQ **4.3**, OpenSearch Service **3.5**, AMG **12.4** |

### F-5 [Medium] Grafana version drift between staging (13.2) and prod (AMG 12.4)

- **Item:** Stack row `Grafana 13.2`. Prod uses Amazon Managed Grafana.
- **Evidence:** AMG supports creating workspaces only up to **Grafana 12.4** (announced 2026-04/05). https://aws.amazon.com/about-aws/whats-new/2026/05/amazon-managed-grafana-v12-update/
- **Impact:** `observability/dashboards/` is shared across environments. Dashboards authored in Grafana 13 (newer dashboard schema and panels) may not import into 12.4.
- **Fix:** Either pin staging Grafana to **12.4.x** to match AMG, or require dashboards to be stored in a 12.4-compatible JSON schema and validated against 12.4 in CI. Record the choice in the Stack row.

### F-6 [Medium] Install method for staging stateful add-ons is unspecified (Bitnami trap)

- **Item:** Staging RabbitMQ, Elasticsearch/Kibana, Prometheus/Grafana and Jaeger. The spine pins app versions but not the operator or chart that installs them.
- **Evidence:** Bitnami moved its free images to the unmaintained `bitnamilegacy` repository on 2025-08-28. Charts that still default to `docker.io/bitnami` break or stop receiving patches. https://www.credativ.de/en/blog/credativ-inside/bitnami-container-repository-migration and https://github.com/bitnami/charts/issues/36215
- **Impact:** An agent that runs `helm install bitnami/rabbitmq` or `bitnami/elasticsearch` (the most common training-data pattern) gets either broken pulls or images that never receive security updates.
- **Fix:** Name the installers in the Stack and pin them:
  - RabbitMQ Cluster Operator **v2.23.x**
  - ECK **v3.5.x** for Elasticsearch/Kibana 9.5, but confirm the K8s range (F-1)
  - kube-prometheus-stack (pinned chart version) for Prometheus and Grafana
  - the official Jaeger v2 Helm chart or the Jaeger operator

  Ban Bitnami charts in the conventions.

### F-7 [Low] Jaeger v2 + Elasticsearch 9: compatible, but the docs disagree

- **Item:** Staging traces go to Jaeger v2.21 with ES 9.5 storage.
- **Evidence:**
  - The Jaeger 2.21 ES docs page still says "Supported ES versions: 7.x, 8.x". https://www.jaegertracing.io/docs/2.21/storage/elasticsearch/
  - The changelog, however, shows ES v9 support added in v2.9.0/v2.10.0 (PRs #7320 and #7358). https://github.com/jaegertracing/jaeger/blob/main/CHANGELOG.md
  - Jaeger CI runs direct and e2e tests against **ES 9.x**, specifically image `elasticsearch:9.5.3`. https://github.com/jaegertracing/jaeger/blob/main/.github/workflows/ci-e2e-elasticsearch.yml and https://github.com/jaegertracing/jaeger/blob/main/docker-compose/elasticsearch/v9/docker-compose.yml
- **Impact:** The combination works, but someone reading the docs will think it doesn't. Third-party guidance, such as Big Bang's, still says "Jaeger is not compatible with ES 9".
- **Fix:** Add a memlog `(version)` line recording this evidence. Keep Jaeger ≥ v2.10.

### F-8 [Low] X-Ray OTLP ingestion has prerequisites not stated in AD-13 or AD-14

- **Item:** Prod traces go from the Collector to X-Ray.
- **Evidence:** X-Ray accepts OTLP at `https://xray.<region>.amazonaws.com/v1/traces`. Constraints:
  - **HTTP only (no gRPC)**
  - **SigV4 required**: Collector `sigv4authextension`, service `xray`
  - **"Make sure Transaction Search is enabled before you use the OTLP Endpoint for traces"**
  - Limits: 5 MB and 10,000 spans per request

  https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-OTLPEndpoint.html and https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-OTLPGettingStarted.html
- **Fix:** In Terraform, enable X-Ray Transaction Search (spans go to the CloudWatch Logs `aws/spans` destination, which has an ingestion cost), and give the Collector an IRSA or Pod Identity role. Configure the prod Collector with `otlphttp` + `sigv4auth`, and size its batch processor below the limits. OpenSearch Ingestion uses the same pattern (`otlphttp` + `sigv4auth`, service `osis`). https://docs.aws.amazon.com/opensearch-service/latest/developerguide/configure-client-otel.html

### F-9 [Low] Amazon MQ RabbitMQ 4.3: instance and feature constraints

- **Item:** Prod broker is Amazon MQ for RabbitMQ 4.3.
- **Evidence:**
  - 4.3 has been GA since 2026-09-10, but **only on m7g instances**.
  - 4.3 removes transient non-exclusive queues, **Global QoS** and classic queues v1 storage.
  - Cluster deployment needs **m7g.large or larger**, and m7g.medium is for testing only.
  - Quorum queues are the default on RabbitMQ 4.

  https://aws.amazon.com/about-aws/whats-new/2026/09/amazon-mq-rabbitmq-43/ and https://docs.aws.amazon.com/amazon-mq/latest/developer-guide/rabbitmq-version-support.md
- **Fix:** In Terraform, set `engine_version = "4.3"`, `host_instance_type = "mq.m7g.large"` and `deployment_mode = "CLUSTER_MULTI_AZ"`. Add a convention: amqp091-go consumers call `Qos(prefetch, 0, false)` (never `global=true`), and every queue is declared as a durable quorum queue. Staging RabbitMQ 4.3.6 should match these settings.

### F-10 [Low] CNPG 1.30 reaches end of life around December 2026

- **Item:** Stack row `CloudNativePG 1.30`.
- **Evidence:** 1.30 was released 2026-06-29 with EOL "~Dec 2026". 1.31 was planned for "~Sep 2026" but has not been tagged as of today (latest tag v1.30.1). CNPG 1.30 supports PostgreSQL 14–18 and defaults to 18.4, so PostgreSQL 18 itself is fine. https://cloudnative-pg.io/docs/devel/supported_releases
- **Fix:** Keep 1.30.1 for now and add a Deferred item: "upgrade to CNPG 1.31 before Dec 2026". When upgrading, pin the PostgreSQL 18.x image tag explicitly rather than taking the operator default, so staging matches RDS 18.6.

### F-11 [Low] Staging capacity and failure tolerance on 1 control plane + 2 workers of about 8 GB

- **Item:** Staging topology (memlog: "kubeadm 3 node ... test mất node được", i.e. it should survive losing a node).
- **Evidence:** Rough fit: Elasticsearch 9 needs a JVM heap of at least 1–2 GB plus page cache, and Kibana about 1 GB. On top of that come CNPG with 3 instances, RabbitMQ with quorum queues (needs 3 replicas to tolerate a node loss), Prometheus, Grafana, Jaeger, Argo CD, Traefik, 4 Go services and 4 mocks. That is tight in 16 GB of worker memory. With only 2 schedulable workers, CNPG anti-affinity and a 3-replica RabbitMQ cannot spread across 3 failure domains unless the control plane is untainted.
- **Fix:** Note this in `deployment.md`: either make the control plane schedulable for stateful replicas or add a third worker, and set ES to a single node with a small heap and ILM retention. This is not a version issue, but it is a reality check on the committed topology.

### F-12 [Info] Confirmed fits (no action)

- **Elasticsearch / Kibana 9.5 license for self-hosting:** Both are triple-licensed under AGPLv3, ELv2 and SSPL. Free for internal use, and the free Basic tier includes security (TLS, RBAC). The only restriction is not offering it to others as a managed service. Kibana v9.5.4 matches ES v9.5.4. https://www.elastic.co/licensing/elastic-license/faq
- **RDS PostgreSQL 18:** GA since 2025-11-14. **18.6** is available on RDS today. https://aws.amazon.com/about-aws/whats-new/2025/11/amazon-rds-postgresql-major-version-18 and https://docs.aws.amazon.com/AmazonRDS/latest/PostgreSQLReleaseNotes/postgresql-versions.html
- **AWS LBC Gateway API:** GA since v3.0.0. v3.5.0 is built for Gateway API v1.6.0 and supports HTTPRoute and GRPCRoute on ALB. Caveat: TLS certificates come from ACM through hostname discovery, not `certificateRefs`, so cert-manager is not used for public TLS in prod. https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/
- **Traefik v3.7 Gateway API:** Supports Standard channel v1.6.1, including HTTPRoute, GRPCRoute, TLSRoute and BackendTLSPolicy. https://doc.traefik.io/traefik/v3.7/reference/install-configuration/providers/kubernetes/kubernetes-gateway/
- **Huma v2.39.1 + chi:** The `github.com/danielgtaylor/huma/v2/adapters/humachi` adapter exists at the v2.39.1 tag and imports `go-chi/chi/v5`. Huma's go.mod requires chi v5.3.1 (compatible with v5.3.2) and Go ≥1.25. https://github.com/danielgtaylor/huma/tree/v2.39.1/adapters/humachi
- **Argo CD 3.5 with Helm v4.3:** Argo CD 3.5 bundles **Helm 4.2.1** for rendering (per `hack/tool-versions.sh`). Charts written for Helm CLI 4.3 should avoid 4.3-only features, or the renders will diverge.
- **EKS 1.37:** Available since 2026-10-01, so it exists. The issue is only F-1/F-2 (add-on support and pinning).
- **OpenSearch Service:** OpenSearch 3.5 and Dashboards 3.5 are available. OpenSearch Ingestion accepts OTLP from the Collector over SigV4.

## Suggested Stack table patch (for the author; spine not edited)

| Name | Version |
|---|---|
| Kubernetes (staging kubeadm / EKS) | 1.36.x / 1.36 (pinned) |
| Gateway API CRDs | v1.6.x standard channel |
| cert-manager | v1.21.x |
| Node.js / pnpm | 24.x LTS / 12.9.x (`packageManager`) |
| OTel Collector | otelcol-contrib v0.162 |
| otelslog bridge | v0.21 (0.x) |
| Grafana (staging) / AMG | 12.4.x / 12.4 (or keep 13.2 with a 12.4-compatible dashboard schema) |
| RabbitMQ Cluster Operator / ECK / kube-prometheus-stack | v2.23 / v3.5 / pinned chart |
| TS OpenAPI client generator | name + version |
| RDS / Amazon MQ / OpenSearch | PG 18.6 / RabbitMQ 4.3 on mq.m7g.large cluster / OpenSearch 3.5 |
