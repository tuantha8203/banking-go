// Command mock-ekyc mocks the eKYC (CCCD + selfie) verification partner (AD-12).
package main

import (
	"context"
	"net"

	"banking-go/services/mocks/internal/mockserver"
)

const serviceName = "mock-ekyc"

func defaultConfig() mockserver.Config { return mockserver.Defaults(":8102", ":9202") }

func main() { mockserver.Main(serviceName, defaultConfig()) }

func run(ctx context.Context, cfg mockserver.Config, ready func(admin, httpAddr net.Addr)) error {
	return mockserver.Run(ctx, serviceName, cfg, ready)
}
