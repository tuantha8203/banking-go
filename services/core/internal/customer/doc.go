// Package customer is a core module (hexagonal: domain <- app <- adapters).
//
// customer owns the customer profile, phone/CCCD (encrypted + blind index) and eKYC state (AD-19, AD-25). Schema: customer.
// Other modules may import only customer/app, never customer/domain or customer/adapters (AD-3, enforced by depguard).
package customer
