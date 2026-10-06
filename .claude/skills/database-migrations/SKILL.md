---
name: database-migrations
description: "Safe database migration patterns for PostgreSQL with goose: forward-only production changes, expand-contract zero-downtime renames, concurrent indexes, and batched backfills. Use when writing a schema or data migration, adding a column or index to a large table, planning a rollback, or preparing a zero-downtime deploy."
metadata:
  origin: ECC
---

# Database Migration Patterns

Safe, reversible database schema changes for production systems.

> banking-go: migrations are goose SQL files in `services/<svc>/migrations/`, run by an Argo CD PreSync Job with role
> `<svc>_migrator`; app pods never migrate. Every change is expand → deploy → contract and must stay compatible with the
> running release (constitution IV.4, deployment.md D-28). A migration already merged to `main` is never edited.

## When to Activate

- Creating or altering database tables
- Adding/removing columns or indexes
- Running data migrations (backfill, transform)
- Planning zero-downtime schema changes
- Setting up migration tooling for a new project

## Core Principles

1. **Every change is a migration** — never alter production databases manually
2. **Migrations are forward-only in production** — rollbacks use new forward migrations
3. **Schema and data migrations are separate** — never mix DDL and DML in one migration
4. **Test migrations against production-sized data** — a migration that works on 100 rows may lock on 10M
5. **Migrations are immutable once deployed** — never edit a migration that has run in production

## Migration Safety Checklist

Before applying any migration:

- [ ] Migration has both `-- +goose Up` and `-- +goose Down` (Down is for local dev only; staging/prod never run down — roll forward)
- [ ] No full table locks on large tables (use concurrent operations)
- [ ] New columns have defaults or are nullable (never add NOT NULL without default)
- [ ] Indexes created concurrently (not inline with CREATE TABLE for existing tables)
- [ ] Data backfill is a separate migration from schema change
- [ ] CI gate D-28 passes: this commit's migrations on the previous release's schema + previous release's tests on the new schema
- [ ] Rollback plan documented (app rollback must work on the new schema)
- [ ] No UPDATE/DELETE on ledger journal/entry rows — they are append-only (constitution I.2); fix with a reversal transaction

## PostgreSQL Patterns

### Adding a Column Safely

```sql
-- GOOD: Nullable column, no lock
ALTER TABLE users ADD COLUMN avatar_url TEXT;

-- GOOD: Column with default (Postgres 11+ is instant, no rewrite)
ALTER TABLE users ADD COLUMN is_active BOOLEAN NOT NULL DEFAULT true;

-- BAD: NOT NULL without default on existing table (requires full rewrite)
ALTER TABLE users ADD COLUMN role TEXT NOT NULL;
-- This locks the table and rewrites every row
```

### Adding an Index Without Downtime

```sql
-- BAD: Blocks writes on large tables
CREATE INDEX idx_users_email ON users (email);

-- GOOD: Non-blocking, allows concurrent writes
CREATE INDEX CONCURRENTLY idx_users_email ON users (email);

-- Note: CONCURRENTLY cannot run inside a transaction block
-- Most migration tools need special handling for this
```

### Renaming a Column (Zero-Downtime)

Never rename directly in production. Use the expand-contract pattern:

```sql
-- Step 1: Add new column (migration 001)
ALTER TABLE users ADD COLUMN display_name TEXT;

-- Step 2: Backfill data (migration 002, data migration)
UPDATE users SET display_name = username WHERE display_name IS NULL;

-- Step 3: Update application code to read/write both columns
-- Deploy application changes

-- Step 4: Stop writing to old column, drop it (migration 003)
ALTER TABLE users DROP COLUMN username;
```

### Removing a Column Safely

```sql
-- Step 1: Remove all application references to the column
-- Step 2: Deploy application without the column reference
-- Step 3: Drop column in next migration
ALTER TABLE orders DROP COLUMN legacy_status;

```

### Large Data Migrations

```sql
-- BAD: Updates all rows in one transaction (locks table)
UPDATE users SET normalized_email = LOWER(email);

-- GOOD: Batch update with progress
-- COMMIT inside a DO block only works outside a transaction: in goose put
-- `-- +goose NO TRANSACTION` at the top of the file, or run the backfill as an app/worker job.
DO $$
DECLARE
  batch_size INT := 10000;
  rows_updated INT;
BEGIN
  LOOP
    UPDATE users
    SET normalized_email = LOWER(email)
    WHERE id IN (
      SELECT id FROM users
      WHERE normalized_email IS NULL
      LIMIT batch_size
      FOR UPDATE SKIP LOCKED
    );
    GET DIAGNOSTICS rows_updated = ROW_COUNT;
    RAISE NOTICE 'Updated % rows', rows_updated;
    EXIT WHEN rows_updated = 0;
    COMMIT;
  END LOOP;
END $$;
```

## goose (Go)

### Workflow

```bash
make tools                                                  # builds bin/goose from tools/go.mod
bin/goose -dir services/core/migrations create add_user_avatar sql
bin/goose -dir services/core/migrations postgres "$DATABASE_URL" up      # local only
bin/goose -dir services/core/migrations postgres "$DATABASE_URL" status
# down: local dev only — never on staging/prod
```

### Migration Files

```sql
-- services/core/migrations/20261006120000_add_customer_avatar.sql
-- +goose Up
ALTER TABLE customer.customers ADD COLUMN avatar_key text;

-- +goose Down
ALTER TABLE customer.customers DROP COLUMN IF EXISTS avatar_key;
```

Concurrent index (cannot run inside a transaction):

```sql
-- services/core/migrations/20261006120100_idx_customer_avatar.sql
-- +goose NO TRANSACTION
-- +goose Up
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_customers_avatar ON customer.customers (avatar_key) WHERE avatar_key IS NOT NULL;

-- +goose Down
DROP INDEX CONCURRENTLY IF EXISTS customer.idx_customers_avatar;
```

After schema changes regenerate sqlc code (`cd services/<svc> && ../../bin/sqlc generate` once the service has sqlc.yaml) and commit it.

## Zero-Downtime Migration Strategy

For critical production changes, follow the expand-contract pattern:

```
Phase 1: EXPAND
  - Add new column/table (nullable or with default)
  - Deploy: app writes to BOTH old and new
  - Backfill existing data

Phase 2: MIGRATE
  - Deploy: app reads from NEW, writes to BOTH
  - Verify data consistency

Phase 3: CONTRACT
  - Deploy: app only uses NEW
  - Drop old column/table in separate migration
```

### Timeline Example

```
Day 1: Migration adds new_status column (nullable)
Day 1: Deploy app v2 — writes to both status and new_status
Day 2: Run backfill migration for existing rows
Day 3: Deploy app v3 — reads from new_status only
Day 7: Migration drops old status column
```

## Anti-Patterns

| Anti-Pattern | Why It Fails | Better Approach |
|-------------|-------------|-----------------|
| Manual SQL in production | No audit trail, unrepeatable | Always use migration files |
| Editing deployed migrations | Causes drift between environments | Create new migration instead |
| NOT NULL without default | Locks table, rewrites all rows | Add nullable, backfill, then add constraint |
| Inline index on large table | Blocks writes during build | CREATE INDEX CONCURRENTLY |
| Schema + data in one migration | Hard to rollback, long transactions | Separate migrations |
| Dropping column before removing code | Application errors on missing column | Remove code first, drop column next deploy |
