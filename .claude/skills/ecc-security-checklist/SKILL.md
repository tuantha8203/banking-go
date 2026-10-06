---
name: ecc-security-checklist
description: Use this skill when adding authentication, handling user input, working with secrets, creating API endpoints, or implementing payment/sensitive features. Provides a security checklist and patterns for the Go services and React SPAs of this repo.
metadata:
  origin: ECC (security-review, adapted for banking-go)
---

# Security Checklist

This skill ensures code follows security best practices and identifies potential vulnerabilities while implementing.
It is a checklist for the implement step; it does not replace code review (Open Code Review) or the built-in
`/security-review` command.

> banking-go: constitution III (default deny, no secrets/PII in logs, secrets only via secret manager, audit,
> maker-checker) and the spine (AD-6 idempotency, AD-10 authN at edge / authZ in core, AD-19, AD-25 PII encryption)
> are binding. Error format and codes: `docs/foundation/api-contracts/README.md`.

## When to Activate

- Implementing authentication or authorization
- Handling user input or file uploads (eKYC images)
- Creating new API endpoints (Huma REST) or gRPC methods
- Working with secrets or credentials
- Implementing money movement (ledger, payment, fees, limits)
- Storing or transmitting sensitive data (PII, tokens)
- Integrating partner APIs (NAPAS, eKYC, OTP, gateway mocks) or webhooks

## Security Checklist

### 1. Secrets Management

#### FAIL: NEVER Do This
```go
const partnerKey = "sk-live-xxxxx"   // hardcoded secret
dsn := "postgres://core:password123@db/core" // in source code
```

#### PASS: ALWAYS Do This
```go
// Typed config loaded from env at startup (pkg/config, caarlos0/env); keys are BG_<SERVICE>_<KEY>
// and every key is listed in .env.example. Fail fast with an error.
type Config struct {
    config.Common
    DatabaseURL  string `env:"DATABASE_URL,required,unset"`   // BG_CORE_WORKER_DATABASE_URL
    NapasHMACKey string `env:"NAPAS_HMAC_KEY,required,unset"` // BG_CORE_WORKER_NAPAS_HMAC_KEY
}

cfg, err := config.Load("core-worker", Config{})
if err != nil {
    return fmt.Errorf("load config: %w", err) // never print the values
}
```

#### Verification Steps
- [ ] No hardcoded API keys, tokens, or passwords (gitleaks runs in CI)
- [ ] All secrets read from env vars at startup; `.env` is gitignored, only `.env.example` is committed
- [ ] No secrets in git history, images or logs
- [ ] Staging secrets via Sealed Secrets, prod via External Secrets ← AWS Secrets Manager (constitution III.3)
- [ ] The SPAs hold no secrets: everything under `import.meta.env.VITE_*` is public

### 2. Input Validation

#### Always Validate User Input
```go
// Huma validates the request struct before the handler runs (code-first OpenAPI, AD-9).
type CreateTransferInput struct {
    IdempotencyKey string `header:"Idempotency-Key" required:"true" format:"uuid"`
    Body struct {
        FromAccountID   string `json:"fromAccountId" format:"uuid"`
        ToAccountNumber string `json:"toAccountNumber" pattern:"^[0-9]{12}$"`
        Amount          int64  `json:"amount" minimum:"1"` // integer VND
        Note            string `json:"note,omitempty" maxLength:"140"`
    }
}
// Validation failure → RFC 9457 problem with code `validation_failed` (400) and `errors[]`.
// Domain checks (Luhn on account number, limits) run again in core.
```

#### File Upload Validation
```go
const maxKYCImage = 5 << 20 // 5 MB (api-contracts A-36)

func validateKYCImage(data []byte) error {
    if len(data) > maxKYCImage {
        return problem.New("kyc_image_invalid")
    }
    // Sniff the content; never trust the filename or client Content-Type
    switch http.DetectContentType(data) {
    case "image/jpeg", "image/png":
        return nil
    default:
        return problem.New("kyc_image_invalid")
    }
}
```

#### Verification Steps
- [ ] All user inputs validated by Huma struct tags at the edge and by domain rules in core
- [ ] File uploads restricted (≤ 5 MB, JPEG/PNG by content sniffing); stored write-only under `kyc/`
- [ ] No direct use of user input in queries
- [ ] Allowlist validation (not denylist)
- [ ] Error messages don't leak sensitive info

### 3. SQL Injection Prevention

#### FAIL: NEVER Concatenate SQL
```go
// DANGEROUS - SQL injection
q := "SELECT id FROM customer.customers WHERE phone_hash = '" + phoneHash + "'"
rows, err := pool.Query(ctx, q)
```

#### PASS: ALWAYS Use Parameterized Queries
```go
// sqlc-generated queries are parameterized by construction:
row, err := q.GetCustomerByPhoneHash(ctx, tx, phoneHash)

// Hand-written pgx: the value goes in the args, never in the string
// (Postgres uses numbered placeholders — dollar sign followed by the position).
rows, err := tx.Query(ctx, sqlGetByPhoneHash, phoneHash)
```

<!-- Do not write a literal dollar-sign-N placeholder anywhere in this file.
     Invoking this skill with arguments substitutes it away, and the example
     above then renders as concatenated SQL -- the exact anti-pattern this
     section warns against. -->

#### Verification Steps
- [ ] All database queries use sqlc or pgx parameters
- [ ] No string concatenation / `fmt.Sprintf` in SQL (identifiers come from code constants only)
- [ ] Each service only connects to its own database; each core module only touches its own schema (constitution V.1)

### 4. Authentication & Authorization

#### Tokens
- Customer/admin token storage in the browser and CSRF strategy are **Deferred** in the spine. Do not pick
  localStorage vs cookies inside a feature; follow the decision once `/foundation update` records it.
- Edge → core calls carry a short-lived internal token (EdDSA, `kid` = issuing edge, `aud=core`, `exp ≤ 60s`) over
  mTLS (AD-10). Core verifies `kid` → issuer, `actor_type`, and that `rpc` matches the method.

#### Authorization Checks (in core, inside the UoW)
```go
func (s *Service) GetAccount(ctx context.Context, actor authn.Actor, id uuid.UUID) (Account, error) {
    acc, err := s.accounts.Get(ctx, tx, id)
    if errors.Is(err, ErrNotFound) || acc.OwnerCustomerID != actor.Sub {
        // Ownership miss returns not_found, never 403 — no IDOR oracle (AD-10)
        return Account{}, apperr.NotFound()
    }
    if err := authz.Check(actor, authz.AccountRead, acc); err != nil { // staff policy, pkg/authz
        return Account{}, err // permission_denied + audit "denied"
    }
    return acc, nil
}
```

#### Verification Steps
- [ ] AuthN at edge, AuthZ (ownership + `pkg/authz` policy) in core, default deny (constitution III.1)
- [ ] Ownership miss → `not_found`; staff policy deny → `permission_denied` + audit record
- [ ] Sensitive admin operations require maker ≠ checker approval (R2, AD-20)
- [ ] Login lockout (5 failures → 15 min) and refresh-token rotation/reuse detection respected
- [ ] Every admin action and security event writes an append-only audit record (constitution III.4)

### 5. XSS Prevention

#### Render as text
```tsx
// React escapes text content. Never use dangerouslySetInnerHTML for user/partner data.
<Typography.Text>{transfer.note}</Typography.Text>
```

#### Content Security Policy

The SPAs are static builds; CSP and security headers are set at the gateway (Traefik / ALB) or the static file server.
Start strict and loosen only with a documented removal plan. Do not default to `'unsafe-inline'` or `'unsafe-eval'`
for scripts. (Ant Design's CSS-in-JS may need `style-src 'unsafe-inline'` or a nonce — document the trade-off.)

```text
default-src 'self'; base-uri 'self'; object-src 'none'; frame-ancestors 'none';
script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; connect-src 'self'
```

#### Verification Steps
- [ ] No `dangerouslySetInnerHTML` with user or partner data
- [ ] CSP and security headers configured at the gateway
- [ ] `href` values from data validated to `http:`/`https:`/`mailto:` only

### 6. CSRF Protection

Depends on the deferred token-storage decision: if auth moves to cookies, state-changing requests need
`SameSite` cookies plus a CSRF token or strict Origin checking. Bearer tokens in the `Authorization` header are not
sent automatically and are not CSRF-prone.

#### Verification Steps
- [ ] CSRF strategy matches the recorded decision (no ad-hoc choice in a feature)
- [ ] Mutating endpoints also require `Idempotency-Key` (AD-6) — retries never create a second effect

### 7. Rate Limiting

Rate limiting and lockout live in the edge services (public-api, admin-api), keyed by trusted client IP and by
customer/user; exceeded → `rate_limited` (429) with `Retry-After`.

#### Verification Steps
- [ ] Rate limit on login, OTP, registration, transfer creation and other expensive endpoints
- [ ] IP-based (from the gateway's trusted client IP header) and user-based limits
- [ ] Core is not exposed publicly (gRPC over mTLS only from edge)

### 8. Sensitive Data Exposure

#### Logging
```go
// FAIL: logging sensitive data
logger.Info("login", "phone", req.Phone, "password", req.Password)

// PASS: ids and outcomes only; PII masked or omitted (constitution III.2)
logger.InfoContext(ctx, "login", "customer_id", customerID, "result", "ok")
```

#### Error Messages
```go
// FAIL: internal details to the client
return nil, fmt.Errorf("query failed: %v", err) // ends up in the response body

// PASS: RFC 9457 problem with a stable code; details only in server logs with trace id
logger.ErrorContext(ctx, "create transfer", "err", err)
return nil, problem.Internal() // code internal_error, traceId, no SQL/stack/PII
```

#### Verification Steps
- [ ] No passwords, tokens, secrets, images or full PII in logs, responses or audit records
- [ ] PII (phone, national id) encrypted at rest with blind index for lookup (AD-25)
- [ ] Problem responses never contain SQL, stack traces or PII
- [ ] Partner webhooks verified with HMAC before parsing; replay window enforced

### 9. Dependency Security

```bash
npx -y pnpm@12.9.1 audit --prod        # SPAs
(cd services/core && govulncheck ./...)   # inside ONE module dir; repeat per module (never at the repo root)
```

#### Lock Files
- `pnpm-lock.yaml`, `go.sum`, `go.work.sum` are committed and never hand-edited; CI installs with `--frozen-lockfile`.

#### Verification Steps
- [ ] No known high/critical vulnerabilities in new dependencies
- [ ] New dependencies pinned and approved by the user
- [ ] Container images pinned by version/digest

## Security Testing

```go
// Table-driven edge tests (httptest + Huma), core authz tests against real Postgres (integration tag)
func TestTransferRequiresIdempotencyKey(t *testing.T) { /* expect 400 idempotency_key_required */ }
func TestAccountOwnershipMissReturnsNotFound(t *testing.T) { /* other customer's id -> 404 not_found */ }
func TestStaffWithoutPermissionIsDeniedAndAudited(t *testing.T) { /* 403 permission_denied + audit row */ }
func TestLoginLockoutAfterFiveFailures(t *testing.T) { /* 423 login_locked, params.lockedUntil */ }
func TestRateLimitReturns429WithRetryAfter(t *testing.T) { /* 429 rate_limited */ }
```

## Pre-Deployment Security Checklist

- [ ] **Secrets**: none hardcoded; delivered via Sealed Secrets / External Secrets
- [ ] **Input Validation**: Huma struct validation at edge + domain checks in core
- [ ] **SQL Injection**: sqlc/pgx parameters only
- [ ] **XSS**: no raw HTML rendering of user data
- [ ] **CSRF**: matches the recorded token-storage decision
- [ ] **Authentication**: edge verifies tokens; internal token + mTLS to core
- [ ] **Authorization**: ownership + `pkg/authz` in core, `not_found` on ownership miss
- [ ] **Idempotency**: `Idempotency-Key` on every mutating request
- [ ] **Rate Limiting**: enabled at the edge
- [ ] **HTTPS**: TLS at the gateway, mTLS internally
- [ ] **Security Headers**: CSP, X-Frame-Options/frame-ancestors, nosniff at the gateway
- [ ] **Error Handling**: RFC 9457 problems without sensitive data
- [ ] **Logging**: no sensitive data; trace id present
- [ ] **Audit**: admin actions and security events recorded append-only
- [ ] **Dependencies**: audited, pinned
- [ ] **File Uploads**: size/type validated by content

## Resources

- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [OWASP ASVS](https://owasp.org/www-project-application-security-verification-standard/)
- [Web Security Academy](https://portswigger.net/web-security)

---

**Remember**: Security is not optional. One vulnerability can compromise customer money. When in doubt, err on the side of caution and ask.
