package otelx_test

import (
	"context"
	"testing"
	"time"

	"banking-go/pkg/otelx"
)

func TestSetupWithoutEndpointIsNoop(t *testing.T) {
	t.Setenv(otelx.EndpointEnv, "")
	tel, err := otelx.Setup(t.Context(), otelx.Config{ServiceName: "test", ServiceVersion: "dev", Environment: "ci"})
	if err != nil {
		t.Fatal(err)
	}
	if tel.Exporting {
		t.Fatal("expected no-op telemetry without an endpoint")
	}
	if tel.Logger == nil {
		t.Fatal("logger must be set")
	}
	if err := tel.Shutdown(t.Context()); err != nil {
		t.Fatal(err)
	}
}

func TestSetupWithEndpointExports(t *testing.T) {
	// Exporters connect lazily, so no Collector is needed for Setup itself.
	t.Setenv(otelx.EndpointEnv, "http://127.0.0.1:1")
	t.Setenv("OTEL_EXPORTER_OTLP_INSECURE", "true")
	tel, err := otelx.Setup(t.Context(), otelx.Config{ServiceName: "test", ServiceVersion: "dev", Environment: "ci"})
	if err != nil {
		t.Fatal(err)
	}
	if !tel.Exporting {
		t.Fatal("expected exporting telemetry")
	}
	tel.Logger.InfoContext(t.Context(), "hello")
	// Shutdown may fail to flush to the unreachable endpoint; it must still return.
	ctx, cancel := context.WithTimeout(t.Context(), 300*time.Millisecond)
	defer cancel()
	_ = tel.Shutdown(ctx)
}
