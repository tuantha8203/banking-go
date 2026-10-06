# Security Guidelines

## Mandatory Security Checks

Before ANY commit:
- [ ] No hardcoded secrets (API keys, passwords, tokens)
- [ ] All user inputs validated
- [ ] SQL injection prevention (parameterized queries)
- [ ] XSS prevention (sanitized HTML)
- [ ] CSRF protection matches the recorded token-storage decision (Deferred in spine until decided)
- [ ] Authentication/authorization verified
- [ ] Rate limiting on public endpoints (enforced at the edge services)
- [ ] Error messages don't leak sensitive data

## Secret Management

- NEVER hardcode secrets in source code
- ALWAYS read secrets from environment variables at startup (`BG_<SERVICE>_<KEY>`, listed in `.env.example`); staging/prod values come from Sealed Secrets / AWS Secrets Manager
- Validate that required secrets are present at startup
- Rotate any secrets that may have been exposed

## Security Response Protocol

If security issue found:
1. STOP immediately
2. Apply the `ecc-security-checklist` skill and tell the user (review runs through Open Code Review / `/review-diff`)
3. Fix CRITICAL issues before continuing
4. Rotate any exposed secrets
5. Review entire codebase for similar issues
