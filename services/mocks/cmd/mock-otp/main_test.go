package main

import (
	"context"
	"io"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"

	"banking-go/pkg/config"
	"banking-go/services/mocks/internal/mockserver"
)

func TestMockStartsAndServesPingAndHealth(t *testing.T) {
	t.Setenv("OTEL_EXPORTER_OTLP_ENDPOINT", "")
	cfg := mockserver.Config{
		Common:   config.Common{AdminAddr: "127.0.0.1:0", Environment: "ci", ShutdownTimeout: 5 * time.Second},
		HTTPAddr: "127.0.0.1:0",
	}
	ctx, cancel := context.WithCancel(t.Context())
	addrs := make(chan [2]net.Addr, 1)
	done := make(chan error, 1)
	go func() { done <- run(ctx, cfg, func(a, h net.Addr) { addrs <- [2]net.Addr{a, h} }) }()

	var a [2]net.Addr
	select {
	case a = <-addrs:
	case err := <-done:
		t.Fatalf("run exited early: %v", err)
	case <-time.After(5 * time.Second):
		t.Fatal("mock did not start")
	}
	for _, p := range []string{"/livez", "/readyz"} {
		if code, _ := get(t, "http://"+a[0].String()+p); code != http.StatusOK {
			t.Fatalf("%s = %d", p, code)
		}
	}
	code, body := get(t, "http://"+a[1].String()+"/v1/ping")
	if code != http.StatusOK || strings.TrimSpace(body) != `{"status":"ok"}` {
		t.Fatalf("/v1/ping = %d %q", code, body)
	}

	cancel()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("run: %v", err)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("mock did not stop")
	}
}

func get(t *testing.T, url string) (int, string) {
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
	b, _ := io.ReadAll(resp.Body)
	return resp.StatusCode, string(b)
}
