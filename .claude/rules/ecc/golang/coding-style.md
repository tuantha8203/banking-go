---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go Coding Style

> This file extends [common/coding-style.md](../common/coding-style.md) with Go specific content.

## Formatting

- **gofmt** and **goimports** are mandatory — run `make fmt` (golangci-lint fmt per module); no style debates

## Design Principles

- Accept interfaces, return structs
- Keep interfaces small (1-3 methods)

## Error Handling

Always wrap errors with context:

```go
if err != nil {
    return fmt.Errorf("create customer: %w", err)
}
```

## Reference

See skill: `golang-patterns` for comprehensive Go idioms and patterns. Errors that cross the API boundary map to the
stable snake_case codes in `docs/foundation/api-contracts/README.md` (core: `google.rpc.ErrorInfo.reason`).
