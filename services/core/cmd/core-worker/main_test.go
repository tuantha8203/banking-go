package main

import (
	"context"
	"io"
	"net"
	"net/http"
	"testing"
	"time"

	"banking-go/pkg/config"
)

func TestCoreWorkerStartsAndServesHealth(t *testing.T) {
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
	cfg := Config{Common: config.Common{AdminAddr: "127.0.0.1:0", Environment: "ci", ShutdownTimeout: 5 * time.Second}}
	ctx, cancel := context.WithCancel(t.Context())
	addrs := make(chan net.Addr, 1)
	done := make(chan error, 1)
	go func() { done <- run(ctx, cfg, func(a net.Addr) { addrs <- a }) }()

	var admin net.Addr
	select {
	case admin = <-addrs:
	case err := <-done:
		t.Fatalf("run exited early: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("service did not start")
	}
	for _, p := range []string{"/livez", "/readyz"} {
		if code := httpStatus(t, "http://"+admin.String()+p); code != http.StatusOK {
			t.Fatalf("%s = %d", p, code)
		}
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
