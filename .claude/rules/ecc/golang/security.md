---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go Security

> This file extends [common/security.md](../common/security.md) with Go specific content.

## Secret Management

Load secrets through the typed config in `pkg/config` (caarlos0/env, keys `BG_<SERVICE>_<KEY>`, every key listed in
`.env.example`) and return an error instead of `log.Fatal`:

```go
type Config struct {
    config.Common
    NapasHMACKey string `env:"NAPAS_HMAC_KEY,required,unset"` // BG_CORE_WORKER_NAPAS_HMAC_KEY
}

cfg, err := config.Load("core-worker", Config{})
if err != nil {
    return fmt.Errorf("load config: %w", err) // never log the secret value
}
```

## Security Scanning

- **gosec** runs as part of golangci-lint v2 (`.golangci.yml`): `make lint-go`. Do not add `//nolint:gosec`
  without the user's approval and a reason.
- Dependency vulnerabilities: `(cd services/<svc> && govulncheck ./...)` — inside one module directory.

## Context & Timeouts

Always use `context.Context` for timeout control:

```go
ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
defer cancel()
```

Never call a partner (NAPAS, eKYC, OTP, gateway) inside a DB transaction; a timeout is `unknown`, not `failed`
(constitution I.5, AD-7).
