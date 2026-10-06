package main

import (
	"strings"
	"testing"
)

func TestMigrateRequiresUp(t *testing.T) {
	err := migrateMain([]string{"down"})
	if err == nil || !strings.Contains(err.Error(), "usage: core migrate up") {
		t.Fatalf("migrateMain(down) = %v, want usage error", err)
	}
}

func TestMigrateRequiresMigratorDSN(t *testing.T) {
	t.Setenv("BG_CORE_MIGRATOR_DSN", "")
	if err := migrateMain([]string{"up"}); err == nil || !strings.Contains(err.Error(), "MIGRATOR_DSN") {
		t.Fatalf("migrateMain(up) without DSN = %v, want MIGRATOR_DSN error", err)
	}
}

func TestMigrateUpWithoutMigrationsIsNoop(t *testing.T) {
	t.Setenv("BG_CORE_MIGRATOR_DSN", "postgres://core_migrator:x@127.0.0.1:1/core?connect_timeout=1")
	if err := migrateMain([]string{"up"}); err != nil {
		t.Fatalf("core migrate up = %v, want nil (no migrations yet)", err)
	}
}
