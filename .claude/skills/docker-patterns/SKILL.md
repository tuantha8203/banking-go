---
name: docker-patterns
description: Docker and Docker Compose patterns for local development dependencies, Go service images, container security, networking, and volumes. Use when creating or reviewing Dockerfiles or the Compose file in deploy/compose.
---

# Docker Patterns

Docker and Docker Compose best practices for containerized development.

> banking-go: `deploy/compose/compose.yaml` runs **only dependencies** (postgres 18.6, rabbitmq 4.3, seaweedfs,
> optional otel-collector profile `obs`); Go services run on the host (`make run`). Use `make up`, `make up-obs`,
> `make down` (or `docker compose -f deploy/compose/compose.yaml ...`). Official upstream images only, pinned versions.
> Production runs on Kubernetes (Argo CD, Helm) with images built once per commit, pushed to GHCR, signed, and
> promoted by digest (`docs/foundation/deployment.md`) — Compose is never used for staging/prod.

## Docker Compose for Local Development

### Local Dependency Stack

See `deploy/compose/compose.yaml`. Conventions when adding a dependency:

- Official image, explicit version tag (no `:latest`), healthcheck so `make up` (`up -d --wait`) can wait on it
- Named volume for data; read-only bind mounts (`:ro`) for config
- Local-only credentials inline are acceptable *only* in this file; never reuse them elsewhere
- PostgreSQL 18 images keep data under `/var/lib/postgresql` (not `/var/lib/postgresql/data` as in ≤17)

```yaml
services:
  postgres:
    image: postgres:18.6
    volumes:
      - pgdata:/var/lib/postgresql
      - ./postgres/init.sql:/docker-entrypoint-initdb.d/10-init.sql:ro
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres -d postgres"]
      interval: 5s
      timeout: 3s
      retries: 20
```

### Go Service Dockerfile (multi-stage)

```dockerfile
# Build context = repo root (go.work workspace); one image per deployable
FROM golang:1.27 AS build
WORKDIR /src
COPY go.work go.work.sum ./
COPY pkg/go.mod pkg/go.sum pkg/
COPY services/core/go.mod services/core/go.sum services/core/
# ...copy the go.mod/go.sum of every module listed in go.work, then:
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X banking-go/pkg/buildinfo.Version=${VERSION}" \
    -o /out/core ./services/core/cmd/core

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/core /core
USER nonroot:nonroot
EXPOSE 8090 9190
ENTRYPOINT ["/core"]
# Health: Kubernetes probes hit /livez and /readyz on the admin port; no HEALTHCHECK needed (distroless has no shell)
```

`pkg/buildinfo.Version` is the ldflags target (`vX.Y.Z` or `sha-<gitsha>`).

## Networking

### Service Discovery

Services in the same Compose network resolve by service name:
```
# From another container on the same Compose network:
postgres://postgres:postgres@postgres:5432/core   # service name "postgres"
amqp://banking:banking@rabbitmq:5672/             # service name "rabbitmq"
# From the host (Go services run here): localhost:5432, localhost:5672
```

### Custom Networks

```yaml
services:
  frontend:
    networks:
      - frontend-net

  api:
    networks:
      - frontend-net
      - backend-net

  db:
    networks:
      - backend-net              # Only reachable from api, not frontend

networks:
  frontend-net:
  backend-net:
```

### Exposing Only What's Needed

```yaml
services:
  postgres:
    ports:
      - "127.0.0.1:5432:5432"   # Only accessible from host, not network
    # Bind to 127.0.0.1 if the dev machine is on an untrusted network
```

## Volume Strategies

```yaml
volumes:
  # Named volume: persists across container restarts, managed by Docker
  pgdata:

  # Bind mount (read-only) for config files, e.g.
  # - ./otelcol/config.yaml:/etc/otelcol/config.yaml:ro
```

### Common Patterns

```yaml
services:
  postgres:
    volumes:
      - pgdata:/var/lib/postgresql                                         # PG18 data dir
      - ./postgres/init.sql:/docker-entrypoint-initdb.d/10-init.sql:ro     # init scripts
```

## Container Security

### Dockerfile Hardening

```dockerfile
# 1. Use specific tags (never :latest); pin by digest in CI
FROM gcr.io/distroless/static-debian12:nonroot

# 2. Run as non-root
USER nonroot:nonroot

# 3. Drop capabilities (in compose)
# 4. Read-only root filesystem where possible
# 5. No secrets in image layers
```

### Compose Security

```yaml
services:
  app:
    security_opt:
      - no-new-privileges:true
    read_only: true
    tmpfs:
      - /tmp
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE          # Only if binding to ports < 1024
```

### Secret Management

```yaml
# Local only: env from the developer's .env (gitignored; .env.example lists every BG_<SERVICE>_<KEY>)
services:
  app:
    env_file:
      - ../../.env

# BAD: Hardcoded in image
# ENV BG_CORE_DATABASE_URL=postgres://...   # NEVER DO THIS
```

Staging/prod secrets never touch images or Compose: Sealed Secrets (staging) and External Secrets ← AWS Secrets
Manager (prod), read as env vars at startup (constitution III.3).

## .dockerignore

```
.git
.env
.env.*
!.env.example
**/node_modules
**/dist
coverage
playwright-report
test-results
bin/
_bmad/
_bmad-output/
docs/
*.log
```

## Debugging

### Common Commands

```bash
DC="docker compose -f deploy/compose/compose.yaml"

# View logs
$DC logs -f rabbitmq                 # Follow logs
$DC logs --tail=50 postgres          # Last 50 lines

# Execute commands in running container
$DC exec postgres psql -U postgres   # Connect to postgres
$DC exec rabbitmq rabbitmq-diagnostics status

# Inspect
$DC ps                               # Running services
docker stats                         # Resource usage

# Clean up
make down                            # Stop and remove containers (keeps volumes)
$DC down -v                          # Also remove volumes (DESTRUCTIVE — ask the user first)
```

### Debugging Network Issues

```bash
# RABBITMQ_USER / RABBITMQ_PASS: the local compose defaults (deploy/compose/compose.yaml)
# Check connectivity from the host
pg_isready -h localhost -p 5432
curl -s http://localhost:15672/api/overview -u "$RABBITMQ_USER:$RABBITMQ_PASS" | head   # RabbitMQ management
curl -s http://localhost:9333/cluster/status                           # SeaweedFS master

# Inspect network
docker network ls
docker network inspect banking-go_default
```

## Anti-Patterns

```
# BAD: Using docker compose beyond local development
# Staging/prod run on Kubernetes via Argo CD (deployment.md)

# BAD: Storing data in containers without volumes
# Containers are ephemeral -- all data lost on restart without volumes

# BAD: Running as root
# Always create and use a non-root user

# BAD: Using :latest tag
# Pin to specific versions for reproducible builds

# BAD: One giant container with all services
# Separate concerns: one process per container

# BAD: Putting real secrets in compose.yaml
# Only local throwaway credentials belong there; real secrets go through the secret manager
```
