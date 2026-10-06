// Package buildinfo holds build-time metadata injected with -ldflags.
//
//	go build -ldflags "-X banking-go/pkg/buildinfo.Version=sha-$(git rev-parse --short HEAD)"
package buildinfo

// Version is the release tag (vX.Y.Z) or sha-<gitsha>; "dev" for local builds.
var Version = "dev"
