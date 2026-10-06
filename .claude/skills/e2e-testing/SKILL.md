---
name: e2e-testing
description: Playwright E2E testing patterns, Page Object Model, configuration, CI/CD integration, artifact management, and flaky test strategies. Use when writing Playwright tests, structuring page objects, or fixing flaky E2E runs in CI.
metadata:
  origin: ECC
---

# E2E Testing Patterns

Comprehensive Playwright patterns for building stable, fast, and maintainable E2E test suites.

> banking-go: each SPA has its own Playwright 1.63 setup (`apps/<app>/playwright.config.ts`, tests in `apps/<app>/e2e/`)
> running against the production build served by `vite preview` (web-customer :4173). Run with `make e2e`
> (first time: `npx -y pnpm@12.9.1 --filter @banking-go/web-customer exec playwright install chromium`).
> Cross-system journeys (SPA → edge → core → mocks) are planned under `tests/e2e/`. E2E never runs against prod
> (constitution IV.3); release demo E2E runs on staging (IV.5).

## Test File Organization

```
apps/web-customer/
├── e2e/
│   ├── smoke.spec.ts
│   ├── auth/
│   │   ├── login.spec.ts
│   │   └── lockout.spec.ts
│   ├── transfers/
│   │   └── transfer.spec.ts
│   ├── pages/            # page objects
│   └── fixtures/
└── playwright.config.ts
```

## Page Object Model (POM)

```typescript
import { Page, Locator, expect } from '@playwright/test'

export class ItemsPage {
  readonly page: Page
  readonly searchInput: Locator
  readonly itemCards: Locator
  readonly createButton: Locator

  constructor(page: Page) {
    this.page = page
    // Role/label first (same priority as RTL); data-testid only as a last resort
    this.searchInput = page.getByRole('searchbox', { name: /search/i })
    this.itemCards = page.getByRole('listitem')
    this.createButton = page.getByRole('button', { name: /create/i })
  }

  async goto() {
    await this.page.goto('/items')
    await expect(this.searchInput).toBeVisible()
  }

  async search(query: string) {
    const response = this.page.waitForResponse(resp => resp.url().includes('/v1/search'))
    await this.searchInput.fill(query)
    await response
  }

  async getItemCount() {
    return await this.itemCards.count()
  }
}
```

## Test Structure

```typescript
import { test, expect } from '@playwright/test'
import { ItemsPage } from './pages/ItemsPage'

test.describe('Item Search', () => {
  let itemsPage: ItemsPage

  test.beforeEach(async ({ page }) => {
    itemsPage = new ItemsPage(page)
    await itemsPage.goto()
  })

  test('should search by keyword', async ({ page }) => {
    await itemsPage.search('test')

    const count = await itemsPage.getItemCount()
    expect(count).toBeGreaterThan(0)

    await expect(itemsPage.itemCards.first()).toContainText(/test/i)
    await page.screenshot({ path: 'artifacts/search-results.png' })
  })

  test('should handle no results', async ({ page }) => {
    await itemsPage.search('xyznonexistent123')

    await expect(page.getByText(/no results/i)).toBeVisible()
    expect(await itemsPage.getItemCount()).toBe(0)
  })
})
```

## Playwright Configuration

Use the existing `apps/<app>/playwright.config.ts` (chromium project, `trace: 'on-first-retry'`, `retries: 1` in CI,
`webServer: pnpm preview` on :4173, `forbidOnly` in CI). Change it only when a test needs it, and keep both apps aligned.

## Flaky Test Patterns

### Quarantine

Quarantine is a last resort and needs the user's approval, an issue link and a recorded reason; never skip or loosen a
test just to get green (constitution II.4). Fix the cause first.

```typescript
test('flaky: complex search', async ({ page }) => {
  test.fixme(true, 'Flaky - Issue #123')
  // test code...
})

test('conditional skip', async ({ page }) => {
  test.skip(process.env.CI, 'Flaky in CI - Issue #123')
  // test code...
})
```

### Identify Flakiness

```bash
npx -y pnpm@12.9.1 --filter @banking-go/web-customer exec playwright test e2e/search.spec.ts --repeat-each=10
npx -y pnpm@12.9.1 --filter @banking-go/web-customer exec playwright test e2e/search.spec.ts --retries=3
```

### Common Causes & Fixes

**Race conditions:**
```typescript
// Bad: assumes element is ready
await page.click('#submit')

// Good: auto-wait locator
await page.getByRole('button', { name: /submit/i }).click()
```

**Network timing:**
```typescript
// Bad: arbitrary timeout
await page.waitForTimeout(5000)

// Good: wait for specific condition
await page.waitForResponse(resp => resp.url().includes('/v1/accounts'))
```

**Animation timing:**
```typescript
// Bad: click during animation
await page.click('[data-testid="menu-item"]')

// Good: web-first locator — auto-waits for visible, stable, enabled
await page.getByRole('menuitem', { name: /settings/i }).click()
```

## Artifact Management

### Screenshots

```typescript
await page.screenshot({ path: 'artifacts/after-login.png' })
await page.screenshot({ path: 'artifacts/full-page.png', fullPage: true })
await page.getByRole('img', { name: /balance chart/i }).screenshot({ path: 'artifacts/chart.png' })
```

### Traces

Traces are configured in `playwright.config.ts` (`trace: 'on-first-retry'`); open with
`npx -y pnpm@12.9.1 --filter @banking-go/web-customer exec playwright show-trace <trace.zip>`.

### Video

```typescript
// In playwright.config.ts (artifacts go to test-results/)
use: {
  video: 'retain-on-failure',
}
```

## CI/CD Integration

PR CI (`.github/workflows/ci.yml`) runs lint/typecheck/vitest only. E2E against staging belongs to the release gate
(`deployment.md`, `staging-drills.yml`); do not add a separate npm-based E2E workflow.

## Test Report Template

```markdown
# E2E Test Report

**Date:** YYYY-MM-DD HH:MM
**Duration:** Xm Ys
**Status:** PASSING / FAILING

## Summary
- Total: X | Passed: Y (Z%) | Failed: A | Flaky: B | Skipped: C

## Failed Tests

### test-name
**File:** `apps/web-customer/e2e/feature.spec.ts:45`
**Error:** Expected element to be visible
**Screenshot:** artifacts/failed.png
**Recommended Fix:** [description]

## Artifacts
- HTML Report: playwright-report/index.html
- Screenshots: artifacts/*.png
- Videos: artifacts/videos/*.webm
- Traces: artifacts/*.zip
```

## Financial / Critical Flow Testing

```typescript
test('transfer is idempotent and shows pending state', async ({ page }) => {
  // Runs only against local/staging builds with mock partners — never prod (constitution IV.3)
  await page.goto('/transfers/new')
  await page.getByLabel(/to account/i).fill('970400000001')
  await page.getByLabel(/amount/i).fill('150000') // integer VND, no decimals

  const request = page.waitForRequest(r => r.url().includes('/v1/transfers') && r.method() === 'POST')
  await page.getByRole('button', { name: /confirm/i }).click()
  const sent = await request
  expect(sent.headers()['idempotency-key']).toMatch(/^[0-9a-f-]{36}$/)

  // A timeout from the partner is `unknown`, not `failed` (AD-7): the UI must show the in-progress state
  await expect(page.getByText(/processing|pending/i)).toBeVisible()
})
```
