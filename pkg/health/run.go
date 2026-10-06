package health

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"time"
)

// Component is a long-running part of a deployable: an HTTP or gRPC server, a consumer, a relay.
type Component struct {
	Name string
	// Serve blocks until the component stops. Returning before Stop is called is treated as a failure.
	Serve func() error
	// Stop drains in-flight work and returns when done or when ctx expires.
	Stop func(ctx context.Context) error
}

// Options configure Run.
type Options struct {
	// Health serves /livez and /readyz on AdminListener.
	Health        *Server
	AdminListener net.Listener
	// DrainDelay is waited after readiness fails and before components stop, so the load balancer
	// can observe the failing probe. Kubernetes preStop sleep usually covers this; default 0.
	DrainDelay time.Duration
	// ShutdownTimeout bounds stopping components plus closers (AD-26: shorter than
	// terminationGracePeriodSeconds). Default 30s.
	ShutdownTimeout time.Duration
	// Closers run after every component stopped (close pools, flush telemetry), in order.
	Closers []func(ctx context.Context) error
	Logger  *slog.Logger
}

// Run starts the admin server and components, waits for ctx to be cancelled (SIGTERM) or a
// component to fail, then shuts down per AD-26: fail readiness → stop components in reverse
// order (drain) → run closers → stop the admin server.
func Run(ctx context.Context, opts Options, components ...Component) error {
	if opts.Health == nil || opts.AdminListener == nil {
		return errors.New("health.Run: Health and AdminListener are required")
	}
	if opts.ShutdownTimeout <= 0 {
		opts.ShutdownTimeout = 30 * time.Second
	}
	log := opts.Logger
	if log == nil {
		log = slog.Default()
	}

	admin := &http.Server{Handler: opts.Health.Handler(), ReadHeaderTimeout: 5 * time.Second}
	errCh := make(chan error, len(components)+1)
	go func() {
		if err := admin.Serve(opts.AdminListener); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- fmt.Errorf("admin server: %w", err)
		}
	}()
	for _, c := range components {
		go func() {
			if err := c.Serve(); err != nil {
				errCh <- fmt.Errorf("%s: %w", c.Name, err)
				return
			}
			errCh <- fmt.Errorf("%s: stopped unexpectedly", c.Name)
		}()
	}
	log.InfoContext(ctx, "started", slog.String("admin_addr", opts.AdminListener.Addr().String()))

	var runErr error
	select {
	case <-ctx.Done():
		log.Info("shutdown signal received")
	case runErr = <-errCh:
		log.Error("component failed, shutting down", slog.Any("error", runErr))
	}

	opts.Health.MarkShuttingDown()
	if opts.DrainDelay > 0 {
		time.Sleep(opts.DrainDelay)
	}

	// Detached from ctx: ctx is already cancelled, the drain needs its own deadline.
	sctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), opts.ShutdownTimeout)
	defer cancel()
	var errs []error
	if runErr != nil {
		errs = append(errs, runErr)
	}
	for i := len(components) - 1; i >= 0; i-- {
		if err := components[i].Stop(sctx); err != nil {
			errs = append(errs, fmt.Errorf("stop %s: %w", components[i].Name, err))
		}
	}
	for _, c := range opts.Closers {
		if err := c(sctx); err != nil {
			errs = append(errs, err)
		}
	}
	if err := admin.Shutdown(sctx); err != nil {
		errs = append(errs, fmt.Errorf("stop admin server: %w", err))
	}
	log.Info("stopped")
	return errors.Join(errs...)
}

// HTTPComponent wraps an http.Server listening on ln as a Component with graceful Shutdown.
func HTTPComponent(name string, srv *http.Server, ln net.Listener) Component {
	return Component{
		Name: name,
		Serve: func() error {
			// ErrServerClosed after Stop is expected; Run ignores results that arrive after shutdown began.
			return srv.Serve(ln)
		},
		Stop: srv.Shutdown,
	}
}
