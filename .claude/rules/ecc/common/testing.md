# Testing Requirements

## Coverage

The repo has no global coverage gate. Aim for ~80% on new code and full coverage of money paths
(ledger, payment, idempotency, outbox); report coverage of touched packages as evidence.

Test Types:
1. **Unit Tests** - Individual functions, utilities, components (`make test`)
2. **Integration Tests** - Database, broker and API adapters against real PostgreSQL/RabbitMQ via testcontainers,
   build tag `integration` (`make test-integration`); never mock the DB for money logic (constitution II.2)
3. **E2E Tests** - Critical user flows with Playwright (`make e2e`)

## Test-Driven Development

MANDATORY workflow (details: `.claude/vendor/superpowers/test-driven-development/SKILL.md`):
1. Write test first (RED)
2. Run test - it should FAIL
3. Write minimal implementation (GREEN)
4. Run test - it should PASS
5. Refactor (IMPROVE)
6. Verify coverage of the touched code

## Troubleshooting Test Failures

1. Reproduce with a failing test first (vendored TDD skill), then find the root cause
2. Check test isolation
3. Verify fakes are correct
4. Fix implementation, not tests (unless the spec changed — record why; constitution II.4)

Run one test with `make test-one PKG=./pkg/health RUN=TestReadyz` or `make test-one WEB=@banking-go/web-customer RUN="renders"`.

## Test Structure (AAA Pattern)

Prefer Arrange-Act-Assert structure for tests:

```typescript
test('calculates similarity correctly', () => {
  // Arrange
  const vector1 = [1, 0, 0]
  const vector2 = [0, 1, 0]

  // Act
  const similarity = calculateCosineSimilarity(vector1, vector2)

  // Assert
  expect(similarity).toBe(0)
})
```

### Test Naming

Use descriptive names that explain the behavior under test:

```typescript
test('returns empty array when no markets match query', () => {})
test('throws error when API key is missing', () => {})
test('shows pending state when the transfer result is unknown', () => {})
```
