---
paths:
  - "**/*.go"
  - "**/go.mod"
  - "**/go.sum"
---
# Go Testing

> This file extends [common/testing.md](../common/testing.md) with Go specific content.

## Framework

Use the standard `go test` with **table-driven tests** (stdlib `testing`; no testify/gomock in this repo).
Integration tests use real PostgreSQL/RabbitMQ via testcontainers-go behind `//go:build integration`
(`make test-integration`); never mock the DB for money logic (constitution II.2).

## Race Detection

CI runs with the `-race` flag. `go.work` has no root module, so `./...` from the repo root fails — use
module paths or the Makefile:

```bash
make test                                              # all modules, no Docker
make test-one PKG=./pkg/health RUN=TestReadyz          # one package
go test -race -count=1 ./services/core/...             # one module, as CI does
```

## Coverage

```bash
go test -cover ./services/core/internal/ledger/...     # per package/module, never ./... at the repo root
```

## Reference

See skill: `golang-testing` for detailed Go testing patterns and helpers.
