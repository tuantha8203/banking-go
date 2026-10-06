---
paths:
  - "**/*.tsx"
  - "**/*.jsx"
  - "**/components/**/*.ts"
  - "**/components/**/*.js"
  - "**/app/**/*.tsx"
  - "**/pages/**/*.tsx"
---
# React Patterns

> This file extends [typescript/patterns.md](../typescript/patterns.md) and [common/patterns.md](../common/patterns.md) with React specific content. For hook-specific rules see [hooks.md](./hooks.md).

## Container / Presentational Split

Container components own data fetching, state, and side effects. Presentational components receive props and render — no service calls, no hooks beyond local UI state.

```tsx
// Container — owns data
export function UserPage({ userId }: { userId: string }) {
  const { data: user, isLoading } = useUser(userId);
  if (isLoading) return <Spinner />;
  if (!user) return <NotFound />;
  return <UserCard user={user} onSelect={handleSelect} />;
}

// Presentational — pure
export function UserCard({ user, onSelect }: { user: User; onSelect: (id: string) => void }) {
  return <button onClick={() => onSelect(user.id)}>{user.name}</button>;
}
```

## State Location Decision Tree

1. Used by one component → `useState` inside it
2. Used by parent + a few children → lift to nearest common ancestor, pass via props
3. Used across distant branches → React Context **for low-frequency reads only** (theme, auth, locale)
4. High-frequency updates shared across the tree → external store (none installed; ask first)
5. Server-derived data → TanStack Query with the generated openapi-fetch client — not application state

Context misused for frequently changing values causes every consumer to re-render on every update.

## Suspense + Error Boundaries

Every Suspense boundary needs an Error Boundary above it. The pair handles both states.

```tsx
<ErrorBoundary fallback={<ErrorView />}>
  <Suspense fallback={<Skeleton />}>
    <UserDetails id={id} />
  </Suspense>
</ErrorBoundary>
```

- Place Suspense boundaries close to where data is needed, not at the route root
- Multiple narrower boundaries reveal loaded content progressively
- Error Boundary must be a Class Component (React 19 has no functional equivalent yet) OR use a library wrapper such as `react-error-boundary`

## Forms

### Ant Design `Form` (default)

Use Ant Design `Form` with validation `rules`; submit through a TanStack Query mutation that sends the
`Idempotency-Key` header (generated once per user intent, reused on retry).

```tsx
export function RenameAccountForm({ onSubmit }: { onSubmit: (v: { name: string }) => void }) {
  const { t } = useTranslation();
  return (
    <Form layout="vertical" onFinish={onSubmit}>
      <Form.Item name="name" label={t("account.name")} rules={[{ required: true, max: 50 }]}>
        <Input />
      </Form.Item>
      <Button type="primary" htmlType="submit">{t("common.save")}</Button>
    </Form>
  );
}
```

### Controlled

Use controlled inputs when the value drives other UI, requires real-time validation, or formatting.

```tsx
const [email, setEmail] = useState("");
return <input value={email} onChange={(e) => setEmail(e.target.value)} />;
```

### Complex Forms

For multi-step forms, dynamic field arrays (`Form.List`) and cross-field validation (`dependencies` + validator), stay
with Ant Design `Form`; do not add another form library.

## Data Fetching

| Strategy | When |
|---|---|
| TanStack Query | Client-side cache, mutations, polling (e.g. a transfer in `pending`) |
| `fetch` in `useEffect` | Avoid — race conditions, no cache, no retry. Only acceptable for one-off fire-and-forget |

Never fetch in a `useEffect` when a real cache library is available — they handle deduping, cache invalidation, error retry, and Suspense integration.

## Lists and Keys

- `key` must be stable across renders — never `index` for any list that can reorder, insert, or delete
- `key` must be unique among siblings, not globally
- A reordered list with index keys causes state in child components to attach to the wrong row

## Composition over Inheritance

- Pass `children` for slot-style composition
- Pass render-prop functions for parameterized rendering
- Pass component types for plug-in points: `renderItem={UserRow}`
- Never extend a component class to specialize behavior

## Compound Components

For related controls (Tabs, Accordion, Menu), use compound components sharing state via Context:

```tsx
<Tabs defaultValue="profile">
  <Tabs.List>
    <Tabs.Trigger value="profile">Profile</Tabs.Trigger>
    <Tabs.Trigger value="settings">Settings</Tabs.Trigger>
  </Tabs.List>
  <Tabs.Panel value="profile"><ProfileForm /></Tabs.Panel>
  <Tabs.Panel value="settings"><SettingsForm /></Tabs.Panel>
</Tabs>
```

## Portals

Use `createPortal` for modals, tooltips, toast containers — anything that must escape the parent's `overflow: hidden` or `z-index` stacking context. Render to a stable DOM node mounted in `index.html`.

## Refs and Forwarding (React 19+)

React 19 lets function components accept `ref` as a regular prop — `forwardRef` is no longer required.

```tsx
export function Input({ ref, ...rest }: { ref?: React.Ref<HTMLInputElement> } & InputProps) {
  return <input ref={ref} {...rest} />;
}
```

Older codebases on React 18 still need `forwardRef`.

## Skill Reference

For React-specific deep dives see the `react-patterns` skill; for tests see `react-testing` and `e2e-testing`.
