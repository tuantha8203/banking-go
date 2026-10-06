// Package otelx sets up OpenTelemetry traces, metrics and logs for a deployable (AD-13).
//
// Telemetry leaves the process only over OTLP gRPC to the Collector at OTEL_EXPORTER_OTLP_ENDPOINT
// (standard OTEL_* variables such as OTEL_EXPORTER_OTLP_INSECURE are honoured by the exporters).
// When the endpoint is unset the global providers stay no-op, so tests and local runs need no
// Collector. Logs are slog JSON on stdout, bridged to OTel via otelslog when exporting.
package otelx

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"strings"

	"go.opentelemetry.io/contrib/bridges/otelslog"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/exporters/otlp/otlplog/otlploggrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlpmetric/otlpmetricgrpc"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracegrpc"
	"go.opentelemetry.io/otel/propagation"
	sdklog "go.opentelemetry.io/otel/sdk/log"
	sdkmetric "go.opentelemetry.io/otel/sdk/metric"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	semconv "go.opentelemetry.io/otel/semconv/v1.43.0"
	"go.opentelemetry.io/otel/trace"
)

// EndpointEnv is the standard variable that switches exporting on.
const EndpointEnv = "OTEL_EXPORTER_OTLP_ENDPOINT"

// Config identifies the emitting service (resource attributes).
type Config struct {
	ServiceName    string // deployable name per AD-1, e.g. "public-api"
	ServiceVersion string // release tag or sha-<gitsha>
	Environment    string // local|ci|staging|prod
}

// Telemetry is the result of Setup.
type Telemetry struct {
	// Logger writes JSON to stdout with trace_id/span_id, and to OTel when exporting.
	Logger *slog.Logger
	// Exporting reports whether OTLP exporters are active.
	Exporting bool
	shutdown  []func(context.Context) error
}

// Shutdown flushes and stops the providers. Safe to call when not exporting.
func (t *Telemetry) Shutdown(ctx context.Context) error {
	var errs []error
	for _, fn := range t.shutdown {
		errs = append(errs, fn(ctx))
	}
	return errors.Join(errs...)
}

// Setup configures global OTel providers and returns the service logger.
func Setup(ctx context.Context, cfg Config) (*Telemetry, error) {
	otel.SetTextMapPropagator(propagation.NewCompositeTextMapPropagator(propagation.TraceContext{}, propagation.Baggage{}))

	level := parseLevel(os.Getenv("LOG_LEVEL"))
	baseAttrs := []slog.Attr{
		slog.String("service", cfg.ServiceName),
		slog.String("env", cfg.Environment),
		slog.String("version", cfg.ServiceVersion),
	}
	stdout := &traceHandler{Handler: slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: level}).WithAttrs(baseAttrs)}

	t := &Telemetry{Logger: slog.New(stdout)}
	if strings.TrimSpace(os.Getenv(EndpointEnv)) == "" {
		return t, nil
	}

	res, err := resource.New(ctx,
		resource.WithFromEnv(),
		resource.WithTelemetrySDK(),
		resource.WithHost(),
		resource.WithSchemaURL(semconv.SchemaURL),
		resource.WithAttributes(
			semconv.ServiceName(cfg.ServiceName),
			semconv.ServiceVersion(cfg.ServiceVersion),
			semconv.ServiceNamespace("banking-go"),
			semconv.DeploymentEnvironmentNameKey.String(cfg.Environment),
		),
	)
	if err != nil {
		return nil, fmt.Errorf("otel resource: %w", err)
	}

	traceExp, err := otlptracegrpc.New(ctx)
	if err != nil {
		return nil, fmt.Errorf("otlp trace exporter: %w", err)
	}
	tp := sdktrace.NewTracerProvider(sdktrace.WithBatcher(traceExp), sdktrace.WithResource(res))
	otel.SetTracerProvider(tp)
	t.shutdown = append(t.shutdown, tp.Shutdown)

	metricExp, err := otlpmetricgrpc.New(ctx)
	if err != nil {
		return nil, errors.Join(fmt.Errorf("otlp metric exporter: %w", err), t.Shutdown(ctx))
	}
	mp := sdkmetric.NewMeterProvider(sdkmetric.WithReader(sdkmetric.NewPeriodicReader(metricExp)), sdkmetric.WithResource(res))
	otel.SetMeterProvider(mp)
	t.shutdown = append(t.shutdown, mp.Shutdown)

	logExp, err := otlploggrpc.New(ctx)
	if err != nil {
		return nil, errors.Join(fmt.Errorf("otlp log exporter: %w", err), t.Shutdown(ctx))
	}
	lp := sdklog.NewLoggerProvider(sdklog.WithProcessor(sdklog.NewBatchProcessor(logExp)), sdklog.WithResource(res))
	otel.SetLoggerProvider(lp)
	t.shutdown = append(t.shutdown, lp.Shutdown)

	bridge := &levelHandler{level: level, Handler: otelslog.NewHandler(cfg.ServiceName, otelslog.WithLoggerProvider(lp))}
	t.Logger = slog.New(slog.NewMultiHandler(stdout, bridge))
	t.Exporting = true
	return t, nil
}

func parseLevel(s string) slog.Level {
	var l slog.Level
	if err := l.UnmarshalText([]byte(strings.TrimSpace(s))); err != nil {
		return slog.LevelInfo
	}
	return l
}

// traceHandler adds trace_id and span_id from the context's span (AD-13 log fields).
type traceHandler struct{ slog.Handler }

func (h *traceHandler) Handle(ctx context.Context, r slog.Record) error {
	if sc := trace.SpanContextFromContext(ctx); sc.IsValid() {
		r.AddAttrs(slog.String("trace_id", sc.TraceID().String()), slog.String("span_id", sc.SpanID().String()))
	}
	return h.Handler.Handle(ctx, r)
}

func (h *traceHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &traceHandler{h.Handler.WithAttrs(attrs)}
}

func (h *traceHandler) WithGroup(name string) slog.Handler {
	return &traceHandler{h.Handler.WithGroup(name)}
}

// levelHandler applies LOG_LEVEL to a handler that has no level option (the otelslog bridge).
type levelHandler struct {
	level slog.Leveler
	slog.Handler
}

func (h *levelHandler) Enabled(ctx context.Context, l slog.Level) bool {
	return l >= h.level.Level() && h.Handler.Enabled(ctx, l)
}

func (h *levelHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return &levelHandler{h.level, h.Handler.WithAttrs(attrs)}
}

func (h *levelHandler) WithGroup(name string) slog.Handler {
	return &levelHandler{h.level, h.Handler.WithGroup(name)}
}
