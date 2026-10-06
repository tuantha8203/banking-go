package main

import (
	"context"
	"io"
	"net"
	"net/http"
	"testing"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"

	"banking-go/pkg/config"
)

func TestCoreStartsAndServesHealth(t *testing.T) {
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
	cfg := Config{
		Common:   config.Common{AdminAddr: "127.0.0.1:0", Environment: "ci", ShutdownTimeout: 5 * time.Second},
		GRPCAddr: "127.0.0.1:0",
	}
	ctx, cancel := context.WithCancel(t.Context())
	addrs := make(chan [2]net.Addr, 1)
	done := make(chan error, 1)
	go func() { done <- run(ctx, cfg, func(a, g net.Addr) { addrs <- [2]net.Addr{a, g} }) }()

	var a [2]net.Addr
	select {
	case a = <-addrs:
	case err := <-done:
		t.Fatalf("run exited early: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("service did not start")
	}

	if code := httpStatus(t, "http://"+a[0].String()+"/livez"); code != http.StatusOK {
		t.Fatalf("/livez = %d", code)
	}
	if code := httpStatus(t, "http://"+a[0].String()+"/readyz"); code != http.StatusOK {
		t.Fatalf("/readyz = %d", code)
	}

	conn, err := grpc.NewClient(a[1].String(), grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	resp, err := healthpb.NewHealthClient(conn).Check(ctx, &healthpb.HealthCheckRequest{})
	if err != nil {
		t.Fatalf("grpc health: %v", err)
	}
	if resp.GetStatus() != healthpb.HealthCheckResponse_SERVING {
		t.Fatalf("grpc health status = %v", resp.GetStatus())
	}

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run: %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("service did not stop")
	}
}

func httpStatus(t *testing.T, url string) int {
	t.Helper()
	req, err := http.NewRequestWithContext(t.Context(), http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode
}
