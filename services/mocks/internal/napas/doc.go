// Package napas will hold the mock behaviour of NAPAS (interbank transfer, name inquiry, R3 recon files): idempotent submit keyed by our
// transaction id, status query GET /v1/transactions/{id}, configurable failure modes and
// HMAC-signed callbacks (AD-12). Empty in the scaffold.
package napas
