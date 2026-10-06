// Command mock-napas mocks the NAPAS interbank transfer and name inquiry partner (AD-12).
package main

import (
	"context"
	"net"

	"banking-go/services/mocks/internal/mockserver"
)

const serviceName = "mock-napas"

func defaultConfig() mockserver.Config { return mockserver.Defaults(":8101", ":9201") }

func main() { mockserver.Main(serviceName, defaultConfig()) }

func run(ctx context.Context, cfg mockserver.Config, ready func(admin, httpAddr net.Addr)) error {
	return mockserver.Run(ctx, serviceName, cfg, ready)
}
