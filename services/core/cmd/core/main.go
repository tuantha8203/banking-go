// Command core runs core's gRPC server (AD-1). In this scaffold it exposes only the standard
// grpc.health.v1.Health service plus /livez and /readyz on the admin port (AD-26).
package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"os/signal"
	"syscall"

	"go.opentelemetry.io/contrib/instrumentation/google.golang.org/grpc/otelgrpc"
	"google.golang.org/grpc"
	grpchealth "google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"

	"banking-go/pkg/buildinfo"
	"banking-go/pkg/config"
	"banking-go/pkg/health"
	"banking-go/pkg/otelx"
)

const serviceName = "core"

// Config is read from BG_CORE_* variables.
type Config struct {
	config.Common
	GRPCAddr string `env:"GRPC_ADDR"`
}

func defaultConfig() Config {
	return Config{Common: config.Common{AdminAddr: ":9190"}, GRPCAddr: ":8090"}
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

// run starts the service and blocks until ctx is cancelled. ready, if set, receives the bound
// admin and gRPC addresses once listening.
func run(ctx context.Context, cfg Config, ready func(admin, grpcAddr net.Addr)) error {
	tel, err := otelx.Setup(ctx, otelx.Config{ServiceName: serviceName, ServiceVersion: buildinfo.Version, Environment: cfg.Environment})
	if err != nil {
		return err
	}
	var lc net.ListenConfig
	adminLn, err := lc.Listen(ctx, "tcp", cfg.AdminAddr)
	if err != nil {
		return fmt.Errorf("listen admin: %w", err)
	}
	grpcLn, err := lc.Listen(ctx, "tcp", cfg.GRPCAddr)
	if err != nil {
		_ = adminLn.Close()
		return fmt.Errorf("listen grpc: %w", err)
	}

	gs := grpc.NewServer(grpc.StatsHandler(otelgrpc.NewServerHandler()))
	hs := grpchealth.NewServer()
	healthpb.RegisterHealthServer(gs, hs)
	hs.SetServingStatus("", healthpb.HealthCheckResponse_SERVING)

	grpcComp := health.Component{
		Name:  "grpc",
		Serve: func() error { return gs.Serve(grpcLn) },
		Stop: func(ctx context.Context) error {
			hs.Shutdown() // grpc health → NOT_SERVING
			done := make(chan struct{})
			go func() { gs.GracefulStop(); close(done) }()
			select {
			case <-done:
				return nil
			case <-ctx.Done():
				gs.Stop()
				return ctx.Err()
			}
		},
	}

	if ready != nil {
		ready(adminLn.Addr(), grpcLn.Addr())
	}
	tel.Logger.InfoContext(ctx, "core listening", "grpc_addr", grpcLn.Addr().String())
	return health.Run(ctx, health.Options{
		Health:          health.NewServer(),
		AdminListener:   adminLn,
		ShutdownTimeout: cfg.ShutdownTimeout,
		Logger:          tel.Logger,
		Closers:         []func(context.Context) error{tel.Shutdown},
	}, grpcComp)
}
