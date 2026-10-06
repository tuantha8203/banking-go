// Package health implements the admin port (/livez, /readyz) and the graceful shutdown sequence
// every Go deployable uses (AD-26).
package health

import (
	"context"
	"encoding/json"
	"net/http"
	"sync"
	"sync/atomic"
	"time"
)

// Check reports whether a dependency (DB, broker, ...) is usable. A non-nil error marks the
// service not ready.
type Check func(ctx context.Context) error

type namedCheck struct {
	name  string
	check Check
}

// Server serves /livez and /readyz. The zero value is not usable; call NewServer.
type Server struct {
	mu           sync.RWMutex
	checks       []namedCheck
	shuttingDown atomic.Bool
	checkTimeout time.Duration
}

// NewServer returns a Server with no readiness checks.
func NewServer() *Server {
	return &Server{checkTimeout: 2 * time.Second}
}

// AddCheck registers a readiness check. Readiness must cover DB and broker (AD-26).
func (s *Server) AddCheck(name string, c Check) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.checks = append(s.checks, namedCheck{name: name, check: c})
}

// MarkShuttingDown makes /readyz fail from now on, so the load balancer stops routing new work.
func (s *Server) MarkShuttingDown() { s.shuttingDown.Store(true) }

// ShuttingDown reports whether shutdown has started.
func (s *Server) ShuttingDown() bool { return s.shuttingDown.Load() }

// Handler returns the admin HTTP handler.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /livez", func(w http.ResponseWriter, _ *http.Request) {
		writeJSON(w, http.StatusOK, status{Status: "ok"})
	})
	mux.HandleFunc("GET /readyz", s.readyz)
	return mux
}

type status struct {
	Status string            `json:"status"`
	Checks map[string]string `json:"checks,omitempty"`
}

func (s *Server) readyz(w http.ResponseWriter, r *http.Request) {
	if s.ShuttingDown() {
		writeJSON(w, http.StatusServiceUnavailable, status{Status: "shutting_down"})
		return
	}
	s.mu.RLock()
	checks := append([]namedCheck(nil), s.checks...)
	s.mu.RUnlock()

	ctx, cancel := context.WithTimeout(r.Context(), s.checkTimeout)
	defer cancel()
	res := status{Status: "ok"}
	code := http.StatusOK
	for _, c := range checks {
		// Error details stay in logs/traces of the check itself; the probe body only names the check.
		if err := c.check(ctx); err != nil {
			if res.Checks == nil {
				res.Checks = map[string]string{}
			}
			res.Checks[c.name] = "fail"
			res.Status = "unavailable"
			code = http.StatusServiceUnavailable
			continue
		}
		if res.Checks == nil {
			res.Checks = map[string]string{}
		}
		res.Checks[c.name] = "ok"
	}
	writeJSON(w, code, res)
}

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Cache-Control", "no-store")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}
