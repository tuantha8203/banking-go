# banking-go

Core banking learning/portfolio system: double-entry ledger, transfers with partner mocks, customer and back-office SPAs.
Go services (hexagonal; `core` is a modular monolith that owns all money), PostgreSQL 18, RabbitMQ 4.3, OpenTelemetry.

Foundation docs (product, architecture, data model, API contracts, NFR, deployment): [`docs/foundation/`](docs/foundation/).
Binding architecture: [ARCHITECTURE-SPINE.md](docs/foundation/_bmad/planning-artifacts/architecture/architecture-banking-go-2026-10-05/ARCHITECTURE-SPINE.md).

## Layout

```text
go.work                 Go workspace: pkg, services/{core,public-api,admin-api,mocks}
pkg/                    shared Go libs: health (admin port + graceful shutdown), otelx, config, buildinfo, gen/ (protobuf, generated)
proto/                  buf module (banking.<svc>.v1) → generated into pkg/gen
services/core/          cmd/core (gRPC), cmd/core-worker, internal/<module>/, migrations/
services/public-api/    cmd/public-api (chi + Huma v2), api/openapi/public-api.yaml (generated), migrations/
services/admin-api/     cmd/admin-api (chi + Huma v2), api/openapi/admin-api.yaml (generated), migrations/
services/mocks/         cmd/mock-{napas,ekyc,otp,gateway}
tools/                  go.mod pinning buf, sqlc, goose, protoc-gen-go(-grpc) (outside go.work)
apps/web-customer/      Vite + React 19 + Ant Design 6 SPA
apps/web-admin/         Vite + React 19 + Ant Design 6 SPA
packages/theme/         Ant Design theme tokens (light/dark) from design-system.md
packages/i18n/          i18next resources (vi, en)
deploy/compose/         local dependencies (postgres, rabbitmq, seaweedfs, otel collector)
```

## Prerequisites

- Go 1.27.x (`GOTOOLCHAIN=auto` downloads it from `go.work`)
- Node.js 24 LTS; pnpm 12.9.1 via `npx -y pnpm@12.9.1` (pinned in `package.json` `packageManager`)
- golangci-lint v2.14 on `PATH`
- Docker with Compose v2 (only for `make up`/`run`/`test-integration`)

## Make targets

| Target | What it does |
| --- | --- |
| `make install` | `go mod download` for every module + `pnpm install --frozen-lockfile` |
| `make build` | `go build` all modules + `pnpm -r build` |
| `make test` | Go unit tests + Vitest (no Docker) |
| `make test-one PKG=./pkg/health RUN=TestReadyz` | one Go package/test; `WEB=@banking-go/web-customer RUN='renders'` for Vitest |
| `make test-integration` | `go test -tags integration` (testcontainers, needs Docker; none yet) |
| `make lint` | golangci-lint per module, `buf lint`, ESLint + Prettier check, `tsc --noEmit` |
| `make fmt` | gofmt/goimports, `buf format`, Prettier |
| `make gen` / `make gen-check` | regenerate protobuf (pkg/gen) and OpenAPI; `gen-check` fails on diff |
| `make up` / `make up-obs` / `make down` | local deps via compose (`up-obs` adds the OTel Collector) |
| `make run` | `make up` + how to start each service |
| `make e2e` | build SPAs + Playwright smoke tests against `vite preview` |

## Local ports

| Deployable | App port | Admin port (`/livez`, `/readyz`) |
| --- | --- | --- |
| core (gRPC) | 8090 | 9190 |
| core-worker | — | 9191 |
| public-api | 8081 | 9181 |
| admin-api | 8082 | 9182 |
| mock-napas / ekyc / otp / gateway | 8101 / 8102 / 8103 / 8104 | 9201 / 9202 / 9203 / 9204 |
| web-customer / web-admin | dev 5173 / 5174, preview 4173 / 4174 | — |

Compose: PostgreSQL 5432, RabbitMQ 5672 (UI 15672), SeaweedFS S3 8333 (master 9333), OTel Collector 4317/4318 (health 13133).
Configuration is environment-only (`BG_<SERVICE>_<KEY>`); see [`.env.example`](.env.example).
