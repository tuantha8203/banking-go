// Command mock-gateway mocks the deposit/withdrawal payment gateway partner (AD-12).
package main

import (
	"context"
	"net"

	"banking-go/services/mocks/internal/mockserver"
)

const serviceName = "mock-gateway"

func defaultConfig() mockserver.Config { return mockserver.Defaults(":8104", ":9204") }

func main() { mockserver.Main(serviceName, defaultConfig()) }

func run(ctx context.Context, cfg mockserver.Config, ready func(admin, httpAddr net.Addr)) error {
	return mockserver.Run(ctx, serviceName, cfg, ready)
}
