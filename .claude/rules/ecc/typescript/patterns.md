---
paths:
  - "**/*.ts"
  - "**/*.tsx"
  - "**/*.js"
  - "**/*.jsx"
---
# TypeScript/JavaScript Patterns

> This file extends [common/patterns.md](../common/patterns.md) with TypeScript/JavaScript specific content.

## API Response Format

Do not define a generic envelope. Use the generated types from the OpenAPI spec and the shapes in
`docs/foundation/api-contracts/README.md`:

```typescript
// List endpoints
interface Page<T> {
  items: T[]
  nextCursor: string | null
}

// Errors: RFC 9457 problem details
interface Problem {
  type: string
  title: string
  status: number
  code: string                       // stable snake_case, translate with i18n
  params?: Record<string, unknown>
  errors?: { field: string; code: string }[]
  traceId?: string
}
```

## Custom Hooks Pattern

```typescript
export function useDebounce<T>(value: T, delay: number): T {
  const [debouncedValue, setDebouncedValue] = useState<T>(value)

  useEffect(() => {
    const handler = setTimeout(() => setDebouncedValue(value), delay)
    return () => clearTimeout(handler)
  }, [value, delay])

  return debouncedValue
}
```
