---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
# TypeScript/JavaScript Security

> This file extends [common/security.md](../common/security.md) with TypeScript/JavaScript specific content.

## Secret Management

The SPAs are static bundles: **they hold no secrets**. Everything in `import.meta.env.VITE_*` is public and shipped to
the browser; secrets live only in the Go services.

```typescript
// NEVER: a secret in the SPA (hardcoded or via VITE_*)
const partnerKey = "sk-live-xxxxx"
const key = import.meta.env.VITE_PARTNER_KEY

// OK: public, non-secret configuration
const apiBaseUrl = import.meta.env.VITE_API_BASE_URL
```

## Agent Support

- Use the **ecc-security-checklist** skill while implementing; reviews go through Open Code Review (`/review-diff`)
