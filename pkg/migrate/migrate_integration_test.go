//go:build integration

package migrate

import (
	"log/slog"
	"testing"
	"testing/fstest"

	"github.com/jackc/pgx/v5"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
)

func TestUpAppliesOnceAndIsSafeToRerun(t *testing.T) {
	ctx := t.Context()
	pg, err := postgres.Run(ctx, "postgres:18.6",
		postgres.WithDatabase("core"), postgres.WithUsername("core_migrator"), postgres.WithPassword("pw"),
		postgres.BasicWaitStrategies())
	testcontainers.CleanupContainer(t, pg)
	if err != nil {
		t.Fatal(err)
	}
	dsn, err := pg.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	fsys := fstest.MapFS{"00001_create_probe.sql": {Data: []byte(
		"-- +goose Up\nCREATE TABLE probe (id int PRIMARY KEY);\n\n-- +goose Down\nDROP TABLE probe;\n")}}

	for run := 1; run <= 2; run++ {
		if err := Up(ctx, dsn, fsys, slog.New(slog.DiscardHandler)); err != nil {
			t.Fatalf("run %d: %v", run, err)
		}
	}

	conn, err := pgx.Connect(ctx, dsn)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close(ctx)
	var applied int
	if err := conn.QueryRow(ctx, "SELECT count(*) FROM goose_db_version WHERE version_id = 1").Scan(&applied); err != nil {
		t.Fatal(err)
	}
	if applied != 1 {
		t.Fatalf("version 1 recorded %d times, want 1", applied)
	}
}
