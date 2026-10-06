// Package platform is a core module (hexagonal: domain <- app <- adapters).
//
// platform wires core to the shared infrastructure tables outbox, inbox and idempotency_keys, which are written only through pkg/outbox, pkg/inbox and pkg/idempotency (AD-3, AD-6, AD-8). Schema: platform.
// Other modules may import only platform/app, never platform/domain or platform/adapters (AD-3, enforced by depguard).
package platform
