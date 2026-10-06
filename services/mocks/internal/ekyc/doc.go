// Package ekyc will hold the mock behaviour of eKYC (CCCD OCR + selfie face match): idempotent submit keyed by our
// transaction id, status query GET /v1/transactions/{id}, configurable failure modes and
// HMAC-signed callbacks (AD-12). Empty in the scaffold.
package ekyc
