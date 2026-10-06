package config_test

import (
	"testing"
	"time"

	"banking-go/pkg/config"
)

type svcConfig struct {
	config.Common
	HTTPAddr string `env:"HTTP_ADDR"`
}

func TestPrefix(t *testing.T) {
	if got := config.Prefix("public-api"); got != "BG_PUBLIC_API_" {
		t.Fatalf("Prefix = %q", got)
	}
}

func TestLoadFromUsesPrefixAndDefaults(t *testing.T) {
	defaults := svcConfig{Common: config.Common{AdminAddr: ":9181"}, HTTPAddr: ":8081"}
	cfg, err := config.LoadFrom("public-api", defaults, map[string]string{
		"BG_PUBLIC_API_HTTP_ADDR":        ":18081",
		"BG_PUBLIC_API_SHUTDOWN_TIMEOUT": "5s",
		"BG_ADMIN_API_ADMIN_ADDR":        ":1", // other service's key is ignored
	})
	if err != nil {
		t.Fatal(err)
	}
	if cfg.HTTPAddr != ":18081" || cfg.AdminAddr != ":9181" || cfg.Environment != "local" || cfg.ShutdownTimeout != 5*time.Second {
		t.Fatalf("unexpected config: %+v", cfg)
	}
}

func TestLoadFromRejectsBadValue(t *testing.T) {
	_, err := config.LoadFrom("core", svcConfig{}, map[string]string{"BG_CORE_SHUTDOWN_TIMEOUT": "soon"})
	if err == nil {
		t.Fatal("expected error for invalid duration")
	}
}
