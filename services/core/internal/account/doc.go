// Package account is a core module (hexagonal: domain <- app <- adapters).
//
// account owns account metadata (number, owner, default flag); status changes go through ledger.SetStatus (AD-17). Schema: account.
// Other modules may import only account/app, never account/domain or account/adapters (AD-3, enforced by depguard).
package account
