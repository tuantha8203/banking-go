---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/components/**/*.ts"
  - "**/app/**/*.ts"
  - "**/pages/**/*.ts"
---
# React Security

> This file extends [typescript/security.md](../typescript/security.md) and [common/security.md](../common/security.md) with React specific content.

## XSS via `dangerouslySetInnerHTML`

CRITICAL. The prop name is deliberately scary — treat every usage as a code review halt.

```tsx
// CRITICAL: unsanitized user input
<div dangerouslySetInnerHTML={{ __html: userBio }} />

// CORRECT options:
// 1. Render as text
<div>{userBio}</div>

// 2. If raw HTML is ever required, stop and ask: add a vetted sanitizer (e.g. DOMPurify) with the user's OK
```

Audit checklist for every `dangerouslySetInnerHTML` call:

- Is the input always under our control? Document the source.
- If user-derived: is it sanitized at the **same call site**? (Sanitization at the API boundary is acceptable only if every consumer is verified.)
- Is the sanitizer config allowlisting tags, not denylisting?

## Unsafe URL Schemes

`javascript:` and `data:` URLs in `href`, `src`, and `xlink:href` execute arbitrary code.

```tsx
// CRITICAL: javascript: URL injection
<a href={user.website}>Visit</a>   // if user.website = "javascript:alert(1)"

// CORRECT: validate scheme
function safeUrl(url: string): string | undefined {
  try {
    const parsed = new URL(url);
    if (["http:", "https:", "mailto:"].includes(parsed.protocol)) return url;
  } catch {
    return undefined;
  }
  return undefined;
}
<a href={safeUrl(user.website)}>Visit</a>
```

React warns about `javascript:` URLs in `href` in development mode, but does not block them at runtime. `data:` URLs and other schemes also slip through. Always validate.

## `target="_blank"` Without `rel`

`<a target="_blank">` without `rel="noopener noreferrer"` lets the target page access `window.opener` and run navigation hijacks.

```tsx
// WRONG
<a href={externalUrl} target="_blank">External</a>

// CORRECT
<a href={externalUrl} target="_blank" rel="noopener noreferrer">External</a>
```

Modern browsers default to `noopener` when `target="_blank"`, but do not rely on browser defaults — be explicit.

## Input Validation

The SPA validates for UX only (Ant Design `Form` rules); the edge services (Huma) and core re-validate everything.
Never rely on client-side checks or hidden UI for authorization — core enforces ownership and policy (AD-10).

## Secret Exposure via Env Vars

Prefixed env vars are bundled into the client. Treat them as public.

Vite exposes every `VITE_*` variable to the bundle. The SPAs have no server side, so they must hold **no secrets** at all.

```ts
// CRITICAL: secret leaked to client bundle
const apiKey = import.meta.env.VITE_PARTNER_SECRET_KEY;
```

Audit on every PR that touches env vars: would this string in the public bundle be a problem?

## Authentication / Authorization

- Token storage (memory / localStorage / httpOnly cookie) and the CSRF strategy are **Deferred** in the spine — do not
  choose inside a feature; follow the decision once `/foundation update` records it. Until then never persist refresh
  tokens in `localStorage` without that decision.
- Never trust client-set state to gate sensitive UI. Render-gating in JSX prevents display, not access — the API must enforce.
- If cookie-based auth is chosen: CSRF tokens or `SameSite=Strict`/`Lax` cookies plus Origin checks

## Content Security Policy (CSP)

Configure at the gateway / static file server (the SPAs are static builds). The minimum acceptable CSP:

```
default-src 'self';
script-src 'self' 'nonce-{REQUEST_NONCE}';
style-src 'self' 'unsafe-inline';
img-src 'self' data: https:;
connect-src 'self' https://api.example.com;
frame-ancestors 'none';
```

- Avoid `unsafe-inline` and `unsafe-eval` in `script-src`
- `style-src 'unsafe-inline'` may be needed for Ant Design's CSS-in-JS — document the tradeoff (or configure a nonce)

## Prototype Pollution via Object Spread

```tsx
// WRONG: untrusted JSON spread directly into state
const update = await req.json();
setState({ ...state, ...update });    // attacker controls __proto__

// CORRECT: pick known keys from a typed (generated) response
const { name, email } = (await res.json()) as UpdateUserResponse;
setState({ ...state, name, email });
```

## Third-Party Components

- Run `npx -y pnpm@12.9.1 audit` and ask the user before adding any UI library (Ant Design is the UI kit)
- Check that the library does not internally use `dangerouslySetInnerHTML` on its input (e.g., rich text editors)
- Pin versions, review changelogs before major upgrades
- Be wary of components that accept HTML strings as props

## Source Map Exposure in Production

Production builds should ship without public source maps (Vite default `build.sourcemap: false`); if added later, upload them to the error tracker and strip them from the public bundle. Public source maps leak internal logic and file structure.

## Agent Support

- Use the `ecc-security-checklist` skill while implementing
- Code review runs through Open Code Review (`/review-diff`)
