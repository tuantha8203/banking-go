---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
# TypeScript/JavaScript Testing

> This file extends [common/testing.md](../common/testing.md) with TypeScript/JavaScript specific content.

## E2E Testing

Use **Playwright** as the E2E testing framework for critical user flows (`apps/<app>/e2e/`, `make e2e`).
Unit/component tests use **Vitest** (`make test`, `make test-one WEB=<package> RUN=<name>`); see skills `react-testing` and `e2e-testing`.

## Agent Support

- **e2e-runner** - Playwright E2E testing specialist
