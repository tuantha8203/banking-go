// Package buildinfo holds build-time metadata injected with -ldflags (deploy/docker/go.Dockerfile).
//
//	go build -ldflags "-X banking-go/pkg/buildinfo.Version=sha-$(git rev-parse --short HEAD) -X banking-go/pkg/buildinfo.Commit=$(git rev-parse HEAD)"
package buildinfo

// Version is the release tag (vX.Y.Z) or sha-<gitsha>; "dev" for local builds.
var Version = "dev"

// Commit is the full git SHA the binary was built from; "unknown" for local builds.
var Commit = "unknown"
