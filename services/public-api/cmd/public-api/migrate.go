package main

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"syscall"

	"banking-go/pkg/buildinfo"
	"banking-go/pkg/config"
	"banking-go/pkg/migrate"
	"banking-go/services/public-api/migrations"
)

// MigrateConfig is read from BG_PUBLIC_API_* by `public-api migrate up`; only the PreSync Job sets it (AD-26).
type MigrateConfig struct {
	MigratorDSN string `env:"MIGRATOR_DSN,notEmpty"`
}

// migrateMain runs `public-api migrate up` against the embedded migrations (deployment.md D-25).
func migrateMain(args []string) error {
	if len(args) != 1 || args[0] != "up" {
		return fmt.Errorf("usage: %s migrate up", serviceName)
	}
	cfg, err := config.Load(serviceName, MigrateConfig{})
	if err != nil {
		return err
	}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	log := slog.New(slog.NewJSONHandler(os.Stdout, nil)).With("service", serviceName, "version", buildinfo.Version)
	return migrate.Up(ctx, cfg.MigratorDSN, migrations.FS, log)
}
