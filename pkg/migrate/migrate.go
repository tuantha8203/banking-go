// Package migrate applies a service's embedded goose migrations with the migrator role (AD-26).
// It is the body of `<svc> migrate up`, which the Argo CD PreSync Job runs (deployment.md D-25).
package migrate

import (
	"context"
	"errors"
	"fmt"
	"io/fs"
	"log/slog"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"github.com/pressly/goose/v3/lock"
)

// LockTimeout bounds how long a migration statement waits for a lock (deployment.md D-27).
const LockTimeout = "5s"

// Up applies every pending migration in fsys (<version>_<name>.sql files at its root).
// No migration file is a successful no-op that never connects. Concurrent runs are serialized by a
// Postgres advisory lock and applied versions are skipped, so re-running is safe.
func Up(ctx context.Context, dsn string, fsys fs.FS, log *slog.Logger) error {
	if strings.TrimSpace(dsn) == "" {
		return errors.New("migrate: empty DSN")
	}
	cfg, err := pgx.ParseConfig(dsn)
	if err != nil {
		return fmt.Errorf("migrate: parse DSN: %w", err)
	}
	cfg.RuntimeParams["lock_timeout"] = LockTimeout
	db := stdlib.OpenDB(*cfg)
	defer db.Close()

	locker, err := lock.NewPostgresSessionLocker()
	if err != nil {
		return fmt.Errorf("migrate: session locker: %w", err)
	}
	p, err := goose.NewProvider(goose.DialectPostgres, db, fsys,
		goose.WithExcludeNames([]string{"embed.go"}),
		goose.WithDisableGlobalRegistry(true),
		goose.WithSessionLocker(locker),
	)
	if errors.Is(err, goose.ErrNoMigrations) {
		log.InfoContext(ctx, "migrate: no migrations, nothing to do")
		return nil
	}
	if err != nil {
		return fmt.Errorf("migrate: %w", err)
	}
	results, err := p.Up(ctx)
	for _, r := range results {
		log.InfoContext(ctx, "migrate: applied", slog.Int64("version", r.Source.Version), slog.Duration("duration", r.Duration))
	}
	if err != nil {
		return fmt.Errorf("migrate: up: %w", err)
	}
	log.InfoContext(ctx, "migrate: done", slog.Int("applied", len(results)))
	return nil
}
