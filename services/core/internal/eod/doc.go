// Package eod is a core module (hexagonal: domain <- app <- adapters).
//
// eod owns the business_day row from R1 and end-of-day processing from R3 (AD-22). Schema: eod.
// Other modules may import only eod/app, never eod/domain or eod/adapters (AD-3, enforced by depguard).
package eod
