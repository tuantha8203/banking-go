package migrate

import (
	"log/slog"
	"strings"
	"testing"
	"testing/fstest"
)

// unreachableDSN points at a closed port: a no-op Up must never dial it.
const unreachableDSN = "postgres://core_migrator:x@127.0.0.1:1/core?connect_timeout=1"

func TestUpWithoutMigrationFilesIsNoop(t *testing.T) {
	fsys := fstest.MapFS{
		"embed.go": {Data: []byte("package migrations\n")},
		".gitkeep": {Data: nil},
	}
	if err := Up(t.Context(), unreachableDSN, fsys, slog.New(slog.DiscardHandler)); err != nil {
		t.Fatalf("Up with no migrations = %v, want nil", err)
	}
}

func TestUpRejectsEmptyDSN(t *testing.T) {
	err := Up(t.Context(), "  ", fstest.MapFS{}, slog.New(slog.DiscardHandler))
	if err == nil || !strings.Contains(err.Error(), "empty DSN") {
		t.Fatalf("Up(empty DSN) = %v, want empty DSN error", err)
	}
}

func TestUpRejectsMalformedDSN(t *testing.T) {
	err := Up(t.Context(), "postgres://%zz", fstest.MapFS{}, slog.New(slog.DiscardHandler))
	if err == nil || !strings.Contains(err.Error(), "parse DSN") {
		t.Fatalf("Up(malformed DSN) = %v, want parse DSN error", err)
	}
}
