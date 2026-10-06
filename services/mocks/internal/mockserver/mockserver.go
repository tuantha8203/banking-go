// Package mockserver is the shared runtime of the partner mocks (mock-napas, mock-ekyc,
// mock-otp, mock-gateway). Mocks are separate deployables that core never imports; they speak
// HTTP/JSON like the real partners (AD-12). Partner behaviour lives in each mock's own package.
package mockserver

import (
	"context"
	"encoding/json"
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
)

// Config is read from BG_<MOCK>_* variables, e.g. BG_MOCK_NAPAS_HTTP_ADDR.
type Config struct {
	config.Common
	HTTPAddr string `env:"HTTP_ADDR"`
}

// Defaults returns a Config with the mock's default ports.
func Defaults(httpAddr, adminAddr string) Config {
	return Config{Common: config.Common{AdminAddr: adminAddr}, HTTPAddr: httpAddr}
}

// Main loads config for name and runs the mock until SIGINT/SIGTERM.
func Main(name string, defaults Config) {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	cfg, err := config.Load(name, defaults)
	if err == nil {
		err = Run(ctx, name, cfg, nil)
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

// Handler returns the mock's partner-facing routes. Only GET /v1/ping exists in the scaffold.
func Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/ping", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
	})
	return mux
}

// Run starts the mock and blocks until ctx is cancelled. ready, if set, receives the bound
// admin and HTTP addresses once listening.
func Run(ctx context.Context, name string, cfg Config, ready func(admin, httpAddr net.Addr)) error {
	tel, err := otelx.Setup(ctx, otelx.Config{ServiceName: name, ServiceVersion: buildinfo.Version, Environment: cfg.Environment})
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
	srv := &http.Server{Handler: otelhttp.NewHandler(Handler(), name), ReadHeaderTimeout: 5 * time.Second}
	if ready != nil {
		ready(adminLn.Addr(), httpLn.Addr())
	}
	tel.Logger.InfoContext(ctx, name+" listening", "http_addr", httpLn.Addr().String())
	return health.Run(ctx, health.Options{
		Health:          health.NewServer(),
		AdminListener:   adminLn,
		ShutdownTimeout: cfg.ShutdownTimeout,
		Logger:          tel.Logger,
		Closers:         []func(context.Context) error{tel.Shutdown},
	}, health.HTTPComponent("http", srv, httpLn))
}
