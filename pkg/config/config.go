// Package config loads service configuration from environment variables.
//
// Every key is named BG_<SERVICE>_<KEY> (spine: Consistency Conventions / Config), where
// <SERVICE> is the deployable name upper-cased with '-' replaced by '_' (public-api → PUBLIC_API).
// Apps read config only from the environment (AD-14); .env.example lists every key.
package config

import (
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/caarlos0/env/v11"
)

// Common holds keys every Go deployable has. Embed it in the service's Config struct.
type Common struct {
	// AdminAddr is the listen address of the admin port serving /livez and /readyz (AD-26).
	AdminAddr string `env:"ADMIN_ADDR"`
	// Environment is the deployment.environment.name resource attribute: local|ci|staging|prod.
	Environment string `env:"ENVIRONMENT" envDefault:"local"`
	// ShutdownTimeout bounds the drain after SIGTERM; keep it below terminationGracePeriodSeconds.
	ShutdownTimeout time.Duration `env:"SHUTDOWN_TIMEOUT" envDefault:"30s"`
}

// Prefix returns the environment variable prefix for a deployable, e.g. "BG_PUBLIC_API_".
func Prefix(service string) string {
	return "BG_" + strings.ToUpper(strings.ReplaceAll(service, "-", "_")) + "_"
}

// Load fills cfg from the process environment using the service prefix. Fields already set in cfg
// act as defaults when the variable is absent.
func Load[T any](service string, cfg T) (T, error) {
	return LoadFrom(service, cfg, envMap(os.Environ()))
}

// LoadFrom is Load with an explicit environment, for tests.
func LoadFrom[T any](service string, cfg T, environ map[string]string) (T, error) {
	opts := env.Options{Prefix: Prefix(service), Environment: environ}
	if err := env.ParseWithOptions(&cfg, opts); err != nil {
		return cfg, fmt.Errorf("config %s: %w", service, err)
	}
	return cfg, nil
}

func envMap(kv []string) map[string]string {
	m := make(map[string]string, len(kv))
	for _, e := range kv {
		if k, v, ok := strings.Cut(e, "="); ok {
			m[k] = v
		}
	}
	return m
}
