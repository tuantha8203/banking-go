package health_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"banking-go/pkg/health"
)

func get(t *testing.T, h http.Handler, path string) int {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequestWithContext(t.Context(), http.MethodGet, path, nil))
	return rec.Code
}

func TestLivezOK(t *testing.T) {
	s := health.NewServer()
	s.AddCheck("db", func(context.Context) error { return errors.New("down") })
	if code := get(t, s.Handler(), "/livez"); code != http.StatusOK {
		t.Fatalf("/livez = %d, want 200 (liveness ignores dependency checks)", code)
	}
}

func TestReadyz(t *testing.T) {
	tests := []struct {
		name  string
		check health.Check
		want  int
	}{
		{"no checks", nil, http.StatusOK},
		{"check ok", func(context.Context) error { return nil }, http.StatusOK},
		{"check fails", func(context.Context) error { return errors.New("db down") }, http.StatusServiceUnavailable},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			s := health.NewServer()
			if tt.check != nil {
				s.AddCheck("db", tt.check)
			}
			if code := get(t, s.Handler(), "/readyz"); code != tt.want {
				t.Fatalf("/readyz = %d, want %d", code, tt.want)
			}
		})
	}
}

func TestReadyzFailsAfterMarkShuttingDown(t *testing.T) {
	s := health.NewServer()
	if code := get(t, s.Handler(), "/readyz"); code != http.StatusOK {
		t.Fatalf("before shutdown /readyz = %d", code)
	}
	s.MarkShuttingDown()
	if code := get(t, s.Handler(), "/readyz"); code != http.StatusServiceUnavailable {
		t.Fatalf("after shutdown /readyz = %d, want 503", code)
	}
	if code := get(t, s.Handler(), "/livez"); code != http.StatusOK {
		t.Fatalf("after shutdown /livez = %d, want 200", code)
	}
}

// TestRunFailsReadinessBeforeDraining proves the AD-26 order: on SIGTERM readiness flips to 503
// first, then components are stopped (drained), then closers run.
func TestRunFailsReadinessBeforeDraining(t *testing.T) {
	s := health.NewServer()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	adminURL := "http://" + ln.Addr().String()

	ctx, cancel := context.WithCancel(t.Context())
	stopCalled := make(chan struct{})
	release := make(chan struct{})
	var order []string
	comp := health.Component{
		Name:  "worker",
		Serve: func() error { <-release; return nil },
		Stop: func(context.Context) error {
			order = append(order, "stop")
			close(stopCalled)
			// Readiness must already be failing while we drain.
			if !s.ShuttingDown() {
				t.Error("component stopped before readiness failed")
			}
			if code := httpGet(t, adminURL+"/readyz"); code != http.StatusServiceUnavailable {
				t.Errorf("/readyz during drain = %d, want 503", code)
			}
			close(release)
			return nil
		},
	}
	done := make(chan error, 1)
	go func() {
		done <- health.Run(ctx, health.Options{
			Health:          s,
			AdminListener:   ln,
			ShutdownTimeout: 5 * time.Second,
			Logger:          slog.New(slog.NewTextHandler(io.Discard, nil)),
			Closers: []func(context.Context) error{func(context.Context) error {
				order = append(order, "close")
				return nil
			}},
		}, comp)
	}()

	waitFor(t, func() bool { return httpGet(t, adminURL+"/readyz") == http.StatusOK })
	cancel()

	select {
	case <-stopCalled:
	case <-time.After(5 * time.Second):
		t.Fatal("component Stop not called")
	}
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("Run returned %v", err)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("Run did not return")
	}
	if len(order) != 2 || order[0] != "stop" || order[1] != "close" {
		t.Fatalf("shutdown order = %v, want [stop close]", order)
	}
}

func TestRunReturnsComponentFailure(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	boom := errors.New("boom")
	err = health.Run(t.Context(), health.Options{
		Health:        health.NewServer(),
		AdminListener: ln,
		Logger:        slog.New(slog.NewTextHandler(io.Discard, nil)),
	}, health.Component{
		Name:  "broken",
		Serve: func() error { return boom },
		Stop:  func(context.Context) error { return nil },
	})
	if !errors.Is(err, boom) {
		t.Fatalf("Run = %v, want wrapped boom", err)
	}
}

func httpGet(t *testing.T, url string) int {
	t.Helper()
	req, err := http.NewRequestWithContext(context.Background(), http.MethodGet, url, nil)
	if err != nil {
		t.Fatal(err)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		return 0
	}
	defer resp.Body.Close()
	_, _ = io.Copy(io.Discard, resp.Body)
	return resp.StatusCode
}

func waitFor(t *testing.T, cond func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !cond() {
		if time.Now().After(deadline) {
			t.Fatal("condition not met in time")
		}
		time.Sleep(10 * time.Millisecond)
	}
}
