---
name: postgres-patterns
description: PostgreSQL 18 patterns for query optimization, schema design, indexing, locking, and queue processing (pgx + sqlc). Use when designing PostgreSQL schemas, indexes, or queries, or when a query is too slow.
metadata:
  origin: ECC
---

# PostgreSQL Patterns

Quick reference for PostgreSQL best practices.

> banking-go: `docs/foundation/data-model.md` and the spine (AD-4, AD-5, AD-8, AD-16) are binding: one database per
> service, one schema per core module, FK only within a schema, money = `bigint` VND, IDs = UUIDv7 generated in the app,
> journal/entry rows are append-only. When this skill disagrees, the foundation docs win.

## When to Activate

- Writing SQL queries or migrations
- Designing database schemas
- Troubleshooting slow queries
- Setting up connection pooling

## Quick Reference

### Index Cheat Sheet

| Query Pattern | Index Type | Example |
|--------------|------------|---------|
| `WHERE col = value` | B-tree (default) | `CREATE INDEX idx ON t (col)` |
| `WHERE col > value` | B-tree | `CREATE INDEX idx ON t (col)` |
| `WHERE a = x AND b > y` | Composite | `CREATE INDEX idx ON t (a, b)` |
| `WHERE jsonb @> '{}'` | GIN | `CREATE INDEX idx ON t USING gin (col)` |
| `WHERE tsv @@ query` | GIN | `CREATE INDEX idx ON t USING gin (col)` |
| Time-series ranges | BRIN | `CREATE INDEX idx ON t USING brin (col)` |

### Data Type Quick Reference

| Use Case | Correct Type | Avoid |
|----------|-------------|-------|
| IDs | `uuid` (UUIDv7, generated in app — no `DEFAULT gen_random_uuid()`) | `int`, random UUIDv4 |
| Strings | `text` | `varchar(255)` |
| Timestamps | `timestamptz` | `timestamp` |
| Money | `bigint` VND (whole đồng; constitution I.1) | `float`, `numeric`, decimal strings |
| Flags | `boolean` | `varchar`, `int` |
| Enums | `text` + `CHECK (col IN (...))` | Postgres `ENUM` types |
| Version | `version bigint NOT NULL DEFAULT 1` | — |

### Common Patterns

**Composite Index Order:**
```sql
-- Equality columns first, then range columns
CREATE INDEX idx ON orders (status, created_at);
-- Works for: WHERE status = 'pending' AND created_at > '2024-01-01'
```

**Covering Index:**
```sql
CREATE INDEX idx ON users (email) INCLUDE (name, created_at);
-- Avoids table lookup for SELECT email, name, created_at
```

**Partial Index:**
```sql
CREATE INDEX idx ON users (email) WHERE deleted_at IS NULL;
-- Smaller index, only includes active users
```

**UPSERT:**
```sql
INSERT INTO settings (user_id, key, value)
VALUES (123, 'theme', 'dark')
ON CONFLICT (user_id, key)
DO UPDATE SET value = EXCLUDED.value;
```

**Cursor Pagination:**
```sql
SELECT id, name FROM products WHERE id > @last_id ORDER BY id LIMIT 51;  -- sqlc named param
-- O(1) vs OFFSET which is O(n). API contract: ?cursor=&limit= (default 50, max 200), opaque base64 cursor.
```

**Queue Processing (outbox relay, AD-8):**
```sql
UPDATE jobs SET status = 'processing'
WHERE id = (
  SELECT id FROM jobs WHERE status = 'pending'
  ORDER BY created_at LIMIT 1
  FOR UPDATE SKIP LOCKED
) RETURNING *;
```

**Row Locking Order (AD-5):**
```sql
-- Only customer account rows are locked; always in a fixed order inside one UoW:
-- idempotency -> transaction -> accounts by id ASC -> limit usage -> business_day
SELECT id FROM ledger_accounts WHERE id = ANY(@account_ids::uuid[]) ORDER BY id FOR UPDATE;
-- Internal (hot) accounts are append-only: never lock them.
```

### Anti-Pattern Detection

```sql
-- Find unindexed foreign keys
SELECT conrelid::regclass, a.attname
FROM pg_constraint c
JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey)
WHERE c.contype = 'f'
  AND NOT EXISTS (
    SELECT 1 FROM pg_index i
    WHERE i.indrelid = c.conrelid AND a.attnum = ANY(i.indkey)
  );

-- Find slow queries
SELECT query, mean_exec_time, calls
FROM pg_stat_statements
WHERE mean_exec_time > 100
ORDER BY mean_exec_time DESC;

-- Check table bloat
SELECT relname, n_dead_tup, last_vacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 1000
ORDER BY n_dead_tup DESC;
```

### Configuration

Server settings (`max_connections`, timeouts, `pg_stat_statements`) are managed through Git: CNPG cluster manifests
(staging) and the RDS parameter group in Terraform (prod). Never `ALTER SYSTEM` by hand. Per-transaction limits
(`lock_timeout`, `statement_timeout`) are set by the UoW (AD-5) and map to the `resource_busy` error code.

## Related

- Skill: `database-migrations` — goose migrations, expand → deploy → contract
- Skill: `golang-testing` — integration tests against real Postgres (testcontainers)

---

*Based on Supabase Agent Skills (credit: Supabase team) (MIT License)*
