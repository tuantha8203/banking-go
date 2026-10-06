// Package ledger is a core module (hexagonal: domain <- app <- adapters).
//
// ledger owns ledger accounts, journals, entries and holds; the only place balances change (AD-4, AD-5, AD-17). Schema: ledger.
// Other modules may import only ledger/app, never ledger/domain or ledger/adapters (AD-3, enforced by depguard).
package ledger
