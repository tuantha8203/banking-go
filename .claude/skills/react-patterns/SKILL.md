---
name: react-patterns
description: React 19 SPA patterns (Vite + Ant Design 6) including hooks discipline, Suspense + error boundaries, forms, data fetching with TanStack Query, state management decision trees, and accessibility-first composition. Use when writing or reviewing React components.
metadata:
  origin: ECC
---

# React Patterns

Idiomatic React 19 patterns for building robust, accessible, performant component trees.

> banking-go: two client-only SPAs (`apps/web-customer`, `apps/web-admin`) built with Vite 8, React 19, Ant Design 6,
> `@banking-go/theme`, `@banking-go/i18n` (i18next), TanStack Query 5 and generated API clients (openapi-typescript +
> openapi-fetch in `packages/api-client-*`). There is no SSR, no Server Components and no Server Actions. UI rules:
> `docs/foundation/design-system.md` and ADR 0009. Money is an integer VND (`number`, never fractional); the backend
> returns error `code` + `params` and the SPA translates them.

## When to Activate

- Writing or modifying React function components, custom hooks, or component trees
- Reviewing JSX/TSX files
- Designing state shape or component composition
- Migrating class components or older `forwardRef`/`useEffect`-heavy code
- Choosing between local state, lifted state, context, and external stores
- Implementing forms with Ant Design `Form`
- Wiring data fetching with TanStack Query

## Core Principles

### 1. Render is a Pure Function of Props and State

```tsx
// Good: derive during render
function Cart({ items }: { items: CartItem[] }) {
  const total = items.reduce((sum, i) => sum + i.price * i.qty, 0);
  return <span>{formatMoney(total)}</span>;
}

// Bad: derived state stored separately
function Cart({ items }: { items: CartItem[] }) {
  const [total, setTotal] = useState(0);
  useEffect(() => {
    setTotal(items.reduce((sum, i) => sum + i.price * i.qty, 0));
  }, [items]);
  return <span>{formatMoney(total)}</span>;
}
```

Derived state in `useEffect` adds a render cycle, can desync, and obscures the data flow.

### 2. Side Effects Outside Render

Effects, mutations, network calls, and subscriptions live in event handlers or `useEffect` — never in the render body.

### 3. Composition Over Inheritance

React has no inheritance model for components. Compose with `children`, render props, or component props.

## Hooks Discipline

See `.claude/rules/ecc/react/hooks.md` for the full ruleset. Highlights:

- Top-level only, never conditional
- Cleanup every subscription, interval, listener
- Functional updater (`setX(prev => prev + 1)`) when new state depends on old
- Default position: do not memoize — add `useMemo`/`useCallback` only when a profiler or a dependency chain proves it matters
- Extract a custom hook only when the same hook sequence appears in 2+ components

## State Location Decision Tree

```
Used by one component?
  -> useState inside it

Used by parent + a few descendants?
  -> lift to nearest common ancestor

Used across distant branches AND low-frequency reads (theme, auth, locale)?
  -> React Context

High-frequency updates shared across the tree?
  -> external store (Zustand, Jotai, Redux Toolkit)

Derived from a server?
  -> TanStack Query (never copy server data into useState/a store)
```

Most pages do not need context or a global store. Resist abstraction until duplicated lifting becomes painful.

## Suspense + Error Boundaries

```tsx
<ErrorBoundary fallback={<ErrorView />}>
  <Suspense fallback={<UserSkeleton />}>
    <UserDetail id={id} />
  </Suspense>
</ErrorBoundary>
```

- Place Suspense boundaries close to the data, not at the route root — progressively reveal content
- Error Boundary remains a class API; use `react-error-boundary` for a hook-friendly wrapper
- A boundary catches errors thrown during render, lifecycle, and constructors of its children — NOT in event handlers or async code

## Forms

### Ant Design `Form` + TanStack Query mutation (default for this repo)

```tsx
import { useState } from "react";
import { Form, Input, InputNumber, Button, Alert } from "antd";
import { useMutation } from "@tanstack/react-query";
import { useTranslation } from "react-i18next";
// `api` = openapi-fetch client from packages/api-client-public; `errorCode` reads the RFC 9457 `code`.

type TransferValues = { toAccountNumber: string; amount: number; note?: string };

export function TransferForm({ accountId }: { accountId: string }) {
  const { t } = useTranslation();
  // One Idempotency-Key per user intent: create it when the form opens, reuse it on retry,
  // replace it only after a definitive result (api-contracts: Idempotency-Key is required).
  const [idempotencyKey] = useState(() => crypto.randomUUID());
  const mutation = useMutation({
    mutationFn: (v: TransferValues) =>
      api.POST("/v1/transfers", {
        params: { header: { "Idempotency-Key": idempotencyKey } },
        body: { fromAccountId: accountId, ...v },
      }),
  });

  return (
    <Form<TransferValues> layout="vertical" onFinish={(v) => mutation.mutate(v)} disabled={mutation.isPending}>
      <Form.Item name="toAccountNumber" label={t("transfer.to")} rules={[{ required: true, len: 12 }]}>
        <Input inputMode="numeric" />
      </Form.Item>
      <Form.Item name="amount" label={t("transfer.amount")} rules={[{ required: true, type: "integer", min: 1 }]}>
        <InputNumber precision={0} min={1} />
      </Form.Item>
      {mutation.error && <Alert type="error" message={t(`errors.${errorCode(mutation.error)}`)} />}
      <Button type="primary" htmlType="submit" loading={mutation.isPending}>{t("transfer.submit")}</Button>
    </Form>
  );
}
```

### Controlled inputs

Use controlled when the value drives other UI, formats on every keystroke, or implements real-time validation.

### Complex forms

For multi-step forms, dynamic field arrays (`Form.List`), or cross-field validation (`dependencies` + validator rules): stay with Ant Design `Form`; do not add React Hook Form or TanStack Form. Roll-your-own state management for forms past trivial complexity is a maintenance trap.

## Data Fetching Decision Matrix

| Need | Tool |
|---|---|
| Client-side cache + mutations + invalidation | TanStack Query (with the generated openapi-fetch client) |
| Real-time subscriptions | Server-Sent Events, WebSockets, or the lib's subscription API |
| One-off fire-and-forget | `fetch()` in an event handler |

Avoid `useEffect` + `fetch` for application data — race conditions, no cache, no retry, no Suspense integration.

## Composition Recipes

### Slot via `children`

```tsx
<Layout>
  <Header />
  <Main>{content}</Main>
</Layout>
```

### Named slots

```tsx
<Page header={<Nav />} sidebar={<Filters />}>
  <Results />
</Page>
```

### Compound components (shared state via Context)

```tsx
<Tabs defaultValue="profile">
  <Tabs.List>
    <Tabs.Trigger value="profile">Profile</Tabs.Trigger>
    <Tabs.Trigger value="settings">Settings</Tabs.Trigger>
  </Tabs.List>
  <Tabs.Panel value="profile"><Profile /></Tabs.Panel>
  <Tabs.Panel value="settings"><Settings /></Tabs.Panel>
</Tabs>
```

### Render prop / function-as-child

Useful when the parent needs to pass parameters to the rendered output:

```tsx
<DataLoader id={id}>
  {({ data, isLoading }) => isLoading ? <Spinner /> : <UserCard user={data} />}
</DataLoader>
```

Modern alternative: a hook (`useData(id)`) returning the same shape — usually cleaner.

## Performance

### When `React.memo` Actually Helps

Wrap a component in `React.memo` only when:

1. It re-renders frequently
2. Its props are usually the same between renders
3. Its render is measurably expensive

`React.memo` adds an equality check on every render. If props differ on most renders, the check is pure overhead.

### Avoiding Render Cascades

- Lift state down rather than up where possible
- Split context: one context per concern, so a change to `themeContext` does not re-render auth consumers
- Use `useSyncExternalStore` for external state libraries — required for safe concurrent rendering

### Lists

- Provide stable `key` props (database id, not array index)
- Virtualize long lists with `@tanstack/react-virtual` or `react-window` once visible item count exceeds ~50 with non-trivial rows

## Accessibility-First Composition

- Always render semantic HTML (`<button>`, `<a>`, `<nav>`, `<main>`) before reaching for `role` attributes
- Every interactive element must be reachable by keyboard
- Form inputs need labels — `<label htmlFor>` or `aria-label` if visually labeled by an icon
- Manage focus on route changes and modal open/close
- Run `axe` in component tests (see the `react-testing` skill)
- Prefer Ant Design components (they ship keyboard/ARIA behaviour) over hand-rolled widgets

## Routing

This skill is router-agnostic (no router is installed yet). When one is added, follow its documentation for loaders and nested layouts.

## Related

- Rules: `.claude/rules/ecc/react/` — coding-style, hooks, patterns, security, testing
- Skills: `react-testing` (Vitest + RTL), `e2e-testing` (Playwright)
- Agents: `react-build-resolver` for build/bundler errors

## Examples

### Custom hook for debounced search

```tsx
function useDebounce<T>(value: T, delay = 300): T {
  const [debounced, setDebounced] = useState(value);
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delay);
    return () => clearTimeout(id);
  }, [value, delay]);
  return debounced;
}

function SearchBox() {
  const [query, setQuery] = useState("");
  const debounced = useDebounce(query, 300);
  const { data } = useQuery({
    queryKey: ["search", debounced],
    queryFn: () => searchApi(debounced),
    enabled: debounced.length > 0,
  });
  return (
    <>
      <input value={query} onChange={(e) => setQuery(e.target.value)} />
      <Results items={data ?? []} />
    </>
  );
}
```

### Optimistic UI with React 19 `useOptimistic`

> Never use optimistic UI for money mutations (transfers, holds, fee changes): the server result may be `pending`
> or `unknown` (AD-7) and must be shown as such. Use it only for low-risk, reversible UI state.

```tsx
import { useOptimistic } from "react";

export function MessageList({ messages }: { messages: Message[] }) {
  const [optimistic, addOptimistic] = useOptimistic(
    messages,
    (state, newMessage: Message) => [...state, newMessage],
  );

  async function send(formData: FormData) {
    const text = String(formData.get("text"));
    addOptimistic({ id: "pending", text, sender: "me" });
    await saveMessage(text);
  }

  return (
    <>
      <ul>{optimistic.map((m) => <li key={m.id}>{m.text}</li>)}</ul>
      <form action={send}>
        <input name="text" />
        <button type="submit">Send</button>
      </form>
    </>
  );
}
```

### Splitting context to avoid render cascades

```tsx
// Two contexts: one rarely changes, one frequently
const ThemeContext = createContext<Theme>("light");
const NotificationsContext = createContext<Notification[]>([]);

// A component that only consumes ThemeContext does NOT re-render when notifications change
```
