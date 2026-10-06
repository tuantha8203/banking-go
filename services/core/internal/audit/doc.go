// Package audit is a core module (hexagonal: domain <- app <- adapters).
//
// audit owns the append-only audit_records store and ingests edge audit events (AD-11). Schema: audit.
// Other modules may import only audit/app, never audit/domain or audit/adapters (AD-3, enforced by depguard).
package audit
