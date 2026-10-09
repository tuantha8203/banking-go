package buildinfo

import "testing"

// Unset -ldflags must leave recognisable local defaults (platform v1 T3).
func TestDefaults(t *testing.T) {
	if Version != "dev" {
		t.Errorf("Version = %q, want %q", Version, "dev")
	}
	if Commit != "unknown" {
		t.Errorf("Commit = %q, want %q", Commit, "unknown")
	}
}
