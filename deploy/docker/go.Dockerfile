# syntax=docker/dockerfile:1
# Go deployables (spec platform v1 §1): one image per Go module, every ./cmd/* binary in /usr/local/bin.
#   docker buildx build --load -f deploy/docker/go.Dockerfile --build-arg SERVICE=core -t banking-go/core:local .
# SERVICE = module dir under services/: core (core, core-worker) | public-api | admin-api | mocks (4 mocks).
ARG GO_IMAGE=golang:1.27.1-trixie
ARG RUNTIME_IMAGE=gcr.io/distroless/static-debian12:nonroot

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS build
ARG SERVICE
ARG VERSION=dev
ARG COMMIT=unknown
ARG TARGETOS
ARG TARGETARCH
ENV GOTOOLCHAIN=local CGO_ENABLED=0
WORKDIR /src
COPY go.work go.work.sum ./
COPY pkg/go.mod pkg/go.sum pkg/
COPY services/core/go.mod services/core/go.sum services/core/
COPY services/public-api/go.mod services/public-api/go.sum services/public-api/
COPY services/admin-api/go.mod services/admin-api/go.sum services/admin-api/
COPY services/mocks/go.mod services/mocks/go.sum services/mocks/
RUN --mount=type=cache,target=/go/pkg/mod go mod download
COPY pkg/ pkg/
COPY services/ services/
RUN --mount=type=cache,target=/go/pkg/mod --mount=type=cache,target=/root/.cache/go-build \
    test -n "$SERVICE" && \
    GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath \
      -ldflags "-s -w -X banking-go/pkg/buildinfo.Version=${VERSION} -X banking-go/pkg/buildinfo.Commit=${COMMIT}" \
      -o /out/ ./services/${SERVICE}/cmd/...

FROM ${RUNTIME_IMAGE}
ARG VERSION=dev
ARG COMMIT=unknown
LABEL org.opencontainers.image.version="${VERSION}" org.opencontainers.image.revision="${COMMIT}"
COPY --from=build /out/ /usr/local/bin/
USER 65532:65532
