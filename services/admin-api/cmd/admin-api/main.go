// Command admin-api runs the admin-api edge service: public REST (chi + Huma v2) and the admin port
// with /livez and /readyz (AD-26).
//
//	admin-api          run the server
//	admin-api openapi  print the OpenAPI 3.1 YAML (make gen writes api/openapi/admin-api.yaml)
package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"

	"banking-go/pkg/buildinfo"
	"banking-go/pkg/config"
	"banking-go/pkg/health"
	"banking-go/pkg/otelx"
	"banking-go/services/admin-api/internal/httpapi"
)

const serviceName = "admin-api"

// Config is read from BG_ADMIN_API_* variables.
type Config struct {
	config.Common
	HTTPAddr string `env:"HTTP_ADDR"`
}

func defaultConfig() Config {
	return Config{Common: config.Common{AdminAddr: ":9182"}, HTTPAddr: ":8082"}
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "openapi" {
		if err := writeOpenAPI(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
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

func writeOpenAPI() error {
	b, err := httpapi.OpenAPIYAML()
	if err != nil {
		return err
	}
	_, err = os.Stdout.Write(b)
	return err
}

// run starts the service and blocks until ctx is cancelled. ready, if set, receives the bound
// admin and HTTP addresses once listening.
func run(ctx context.Context, cfg Config, ready func(admin, httpAddr net.Addr)) error {
	tel, err := otelx.Setup(ctx, otelx.Config{ServiceName: serviceName, ServiceVersion: buildinfo.Version, Environment: cfg.Environment})
	if err != nil {
		return err
	}
	var lc net.ListenConfig
	adminLn, err := lc.Listen(ctx, "tcp", cfg.AdminAddr)
	if err != nil {
		return fmt.Errorf("listen admin: %w", err)
	}
	httpLn, err := lc.Listen(ctx, "tcp", cfg.HTTPAddr)
	if err != nil {
		_ = adminLn.Close()
		return fmt.Errorf("listen http: %w", err)
	}

	handler, _ := httpapi.New()
	srv := &http.Server{
		Handler:           otelhttp.NewHandler(handler, serviceName),
		ReadHeaderTimeout: 5 * time.Second,
	}
	if ready != nil {
		ready(adminLn.Addr(), httpLn.Addr())
	}
	tel.Logger.InfoContext(ctx, "admin-api listening", "http_addr", httpLn.Addr().String())
	return health.Run(ctx, health.Options{
		Health:          health.NewServer(),
		AdminListener:   adminLn,
		ShutdownTimeout: cfg.ShutdownTimeout,
		Logger:          tel.Logger,
		Closers:         []func(context.Context) error{tel.Shutdown},
	}, health.HTTPComponent("http", srv, httpLn))
}
