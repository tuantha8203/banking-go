// Command mock-otp mocks the OTP step-up challenge (R2) partner (AD-12).
package main

import (
	"context"
	"net"

	"banking-go/services/mocks/internal/mockserver"
)

const serviceName = "mock-otp"

func defaultConfig() mockserver.Config { return mockserver.Defaults(":8103", ":9203") }

func main() { mockserver.Main(serviceName, defaultConfig()) }

func run(ctx context.Context, cfg mockserver.Config, ready func(admin, httpAddr net.Addr)) error {
	return mockserver.Run(ctx, serviceName, cfg, ready)
}
