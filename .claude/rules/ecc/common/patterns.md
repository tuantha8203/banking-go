# Common Patterns

> banking-go: the architecture (`docs/foundation/architecture.md`, spine AD-n) and API contracts
> (`docs/foundation/api-contracts/`) are binding; this file only adds general guidance.

## Design Patterns

### Ports & Repositories (AD-16)

Encapsulate data access behind ports owned by the `app` layer:
- Define only the operations the use case needs (no generic CRUD); port methods take `tx` right after `ctx`
- Adapters (pgx/sqlc) implement the ports and never `Begin`/`Commit` themselves — only the entry use case calls `uow.Do`
- Business logic depends on the port, not the storage mechanism
- Money logic (ledger, payment, idempotency, outbox) is tested against real PostgreSQL, never against mocked
  repositories (constitution II.2); fakes are fine for non-money ports

### API Response Format

Follow `docs/foundation/api-contracts/README.md`, not a generic envelope:
- Success: the resource itself (camelCase JSON, money as integer VND), correct HTTP status
- Lists: `{ "items": [...], "nextCursor": "…" | null }` with `?cursor=&limit=` (default 50, max 200)
- Errors: RFC 9457 problem details with a stable snake_case `code`, `params`, `errors[]`, `traceId`
- Mutating requests require the `Idempotency-Key` header; replays return the original result
