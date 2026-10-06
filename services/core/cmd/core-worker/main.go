// Command core-worker runs core's background work in the same codebase and database as core
// (AD-1): outbox relay, consumers, periodic jobs and the partner webhook listener. In this
// scaffold it only serves /livez and /readyz on the admin port (AD-26).
package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"

	"banking-go/pkg/buildinfo"
	"banking-go/pkg/config"
	"banking-go/pkg/health"
	"banking-go/pkg/otelx"
)

const serviceName = "core-worker"

// Config is read from BG_CORE_WORKER_* variables.
type Config struct {
	config.Common
}

func defaultConfig() Config {
	return Config{Common: config.Common{AdminAddr: ":9191"}}
}

func main() {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	cfg, err := config.Load(serviceName, defaultConfig())
	if err == nil {
		err = run(ctx, cfg, nil)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// run starts the worker and blocks until ctx is cancelled. ready, if set, receives the bound
// admin address once listening.
func run(ctx context.Context, cfg Config, ready func(admin net.Addr)) error {
	tel, err := otelx.Setup(ctx, otelx.Config{ServiceName: serviceName, ServiceVersion: buildinfo.Version, Environment: cfg.Environment})
	if err != nil {
		return err
	}
	var lc net.ListenConfig
	adminLn, err := lc.Listen(ctx, "tcp", cfg.AdminAddr)
	if err != nil {
		return fmt.Errorf("listen admin: %w", err)
	}
	if ready != nil {
		ready(adminLn.Addr())
	}
	// Relay, consumers and jobs are added here as health.Components (stopped before pools close).
	return health.Run(ctx, health.Options{
		Health:          health.NewServer(),
		AdminListener:   adminLn,
		ShutdownTimeout: cfg.ShutdownTimeout,
		Logger:          tel.Logger,
		Closers:         []func(context.Context) error{tel.Shutdown},
	})
}
