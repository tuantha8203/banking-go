// Package payment is a core module (hexagonal: domain <- app <- adapters).
//
// payment owns transactions, drafts, partner attempts and payment.Transition, the single state-change path (AD-7, AD-18). Schema: payment.
// Other modules may import only payment/app, never payment/domain or payment/adapters (AD-3, enforced by depguard).
package payment
