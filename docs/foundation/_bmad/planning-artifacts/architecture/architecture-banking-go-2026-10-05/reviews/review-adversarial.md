---
review: adversarial
target: ../ARCHITECTURE-SPINE.md
context: [../../../../../business-flows.md, ../../../../../glossary.md, ../../../prds/prd-banking-go-2026-10-05/prd.md]
date: '2026-10-05'
reviewer: BMAD adversarial architecture reviewer
verdict: 'NOT READY TO BIND: the ADs pick the right paradigm (single-DB ACID core, outbox, edge-authN/core-authZ), but they leave enough unspecified that two agents can follow every AD exactly and still double-post money, skip OTP/authZ, or lose the link between a login and a customer.'
---

# Adversarial Review — ARCHITECTURE-SPINE (banking-go)

## Method

For each hole, I picture two units one level below the spine (core modules, services, or features) built by
different AI agents. Each unit follows every AD exactly as written, and the two still don't fit together. Each finding gives:

- **Severity**: Critical (money incorrectness or security breach is reachable), High (likely incident or rework across units), Medium (drift or rework).
- **Units**: the two units that clash.
- **Divergence**: how both comply and still diverge.
- **Consequence**: what goes wrong.
- **Proposed AD**: the new or tightened rule text, ready to paste into the spine.

The findings are ordered by severity, then by blast radius.

## Summary

| # | Sev | Hole | Fix |
|---|---|---|---|
| F1 | Critical | A cross-module port call can open its own DB tx, so the journal and its business record commit separately | New AD-16 Unit of Work |
| F2 | Critical | Balance, available balance, holds and account status have no single owner, row or mutation path | New AD-17 Balance & hold model, tighten AD-5 |
| F3 | Critical | Several writers mutate transaction state (callback, timeout, scan, manual recon) with no CAS or lock order, and callback amounts aren't checked | New AD-18 Transaction state transitions |
| F4 | Critical | The internal token doesn't bind which actor types an edge may assert, and authZ doesn't require resource ownership | Tighten AD-10 |
| F5 | Critical | The link between a public-api credential and a core customer is undefined. Registration spans two DBs with no saga, and phone/status have two owners | New AD-19 Customer identity |
| F6 | High | Idempotency scope, hash and in-flight semantics are undefined, and system-originated commands have no key rule | Tighten AD-6 |
| F7 | High | Maker-checker execution: approval truth is split between admin-api and core, retries can double-execute, and maker≠checker isn't re-verified | New AD-20 Approved-command execution |
| F8 | High | Fees, limits and OTP: computed twice, rounding undefined, limit counters racy, OTP enforced only by the edge | New AD-21 Pricing, limits, step-up |
| F9 | High | `business_date` has no owner, timezone or cutover rule; daily limits and interest disagree on what a "day" is | New AD-22 Business day |
| F10 | High | Partner calls: redelivery can re-send a payout, a webhook can be replayed, and pending→unknown has no deadline owner | Tighten AD-7, AD-12 |
| F11 | High | Audit: edge and core both (or neither) write the record for one admin action; IP isn't in `x-actor`; no schema | Tighten AD-11 |
| F12 | High | Event ordering and versioning: out-of-order status events can re-enable a rejected customer; edges have no namespace; no major version in the event type | Tighten AD-8, AD-9 conventions |
| F13 | High | Corrections: TRANSACTION–JOURNAL is 0..1, so a reversal can be bolted onto the original or float without a transaction | New AD-23 Transaction kinds & corrections |
| F14 | Medium | Where the outbox, inbox and idempotency tables live inside core (per module or shared) and who runs the relay (core or core-worker) | Tighten AD-3, AD-8 |
| F15 | Medium | Customer addressing: account_id UUID vs 12-digit number in REST and proto; statement balance_after and ordering | Conventions row |

---

## F1 — Critical — Cross-module transaction boundary (Unit of Work) is undefined

**Units:** core `payment` (Transfer use case) and core `ledger` (Post port), built by different agents.

**Divergence while compliant:**
- AD-3 says a module touches only its own tables and reaches other modules through their `app` port.
- AD-4 says the journal is written "in one DB transaction together with its business record".
- The Conventions table says "one use case = at most one DB transaction".
- Nothing says *who opens the transaction* or how a port joins it.
- The ledger agent writes `ledger.Post(ctx, Journal) error`, which runs `BEGIN … COMMIT` itself. That's reasonable: it's "its own use case", and the agent wants Post to be safe to call alone.
- The payment agent writes `Transfer`, which opens a tx, inserts the `transactions` row, calls `ledger.Post`, and commits.
- Both are compliant.

**Consequence:**
- The payment tx and the ledger tx are separate connections. A crash between them leaves `transactions.status = succeeded` with no journal, or a journal with no transaction.
- The idempotency row (AD-6 "same transaction as the effect") lands in a third connection's tx.
- The `FOR UPDATE` locks taken in one tx don't protect writes in the other, so the AD-5 locking guarantee is void.
- This is the most likely way to break SM-1.

**Proposed AD-16 — Unit of Work across core modules [PROPOSED]**
- **Binds:** all core modules, core-worker, `pkg/idempotency`, `pkg/outbox`, `pkg/inbox`
- **Rule:**
  - Only the **entry use case** (a gRPC handler in core, or a consumer or job handler in core-worker) begins and commits the DB transaction, through `uow.Do(ctx, func(tx Tx) error)`.
  - Every cross-module `app` port method that reads or writes state takes the transaction handle explicitly, as its first parameter after `ctx` (`Post(ctx, tx, …)`).
  - Port methods never call `Begin`, `Commit` or `Rollback`. Calling them inside a module adapter is an import-lint and code-review failure.
  - Idempotency record, outbox message, inbox record and audit record are written through the same `tx`.
  - Isolation level is READ COMMITTED plus explicit row locks (AD-5, AD-18). SERIALIZABLE is not used on the hot path.
  - Pool exhaustion or a lock timeout (`lock_timeout` = 2 s, `statement_timeout` = 5 s on the hot path) aborts the whole UoW.

---

## F2 — Critical — Balance, available balance, holds and status have no single owner or mutation path

**Units:** core `account` (open, close, block, owns `accounts`) and core `ledger` (posting, holds, FR-10..13 per the Capability map). A third party is any payment feature (withdraw, interbank).

**Divergence while compliant:**

1. **Two homes for the balance.** The ERD gives ACCOUNT "is a" LEDGER_ACCOUNT, so there are two tables.
   - AD-5 says the posting tx updates "their `balance` / `available_balance` columns". Whose columns?
   - Agent A puts the balances on `accounts` (owned by `account`). The ledger then must call `account.ApplyDelta` through a port.
   - Agent B puts them on `ledger_accounts`.
   - AD-5 locks "in ascending `account_id` order". If `ledger_account.id ≠ account.id`, the two agents lock different rows in different orders, which causes deadlocks. Worse, one agent locks a row the other never reads.

2. **Status checked outside the lock.**
   - BF-3 checks status ("source can be debited") under the lock.
   - If status lives on `accounts` while balance lives on `ledger_accounts`, Agent A locks only the balance row.
   - A concurrent BF-6 `debit_blocked` commits in between, and a debit posts after the block.

3. **Holds and the available balance.**
   - FR-12 says available = balance − Σholds.
   - Agent A's `ledger.Post` decrements both `balance` and `available_balance` by the debit, and `ReleaseHold` adds the hold back to `available`.
   - Agent B's `Post` decrements only `balance`, on the theory that "available is derived", and `PlaceHold` decrements `available`.
   - Mixing them on the withdraw success path:
     - A-Post with B-Release subtracts twice.
     - B-Post with A-Release leaves available too high, by the hold amount, which lets money be spent twice.
   - For transfers with no hold, B-Post never lowers `available`, so concurrent transfers overspend. The FR-13 invariant checks only balance = Σentries, so neither bug is caught.

4. **Hold expiry.** Nothing forbids an agent from adding a hold TTL that releases holds on old `unknown` transactions. BF-4 says the hold must be *kept* while the transaction is unknown, so a TTL is money loss if the partner actually paid out.

5. **Sign convention.**
   - Customer accounts are liabilities, with a credit-normal balance.
   - Agent A computes balance = ΣC − ΣD. Agent B (the invariant job) computes ΣD − ΣC.
   - Every customer account then "mismatches", so the alert gets muted and real drift is hidden.

**Proposed AD-17 — Balance & hold model [PROPOSED] (tightens AD-5)**
- **Binds:** core `account`, `ledger`, `payment`, `savings`, invariant job
- **Rule:**
  - **One row per customer account.** A customer account has one row in `accounts` (owned by `ledger` for balance columns, by `account` for metadata). It holds `id` (= its ledger account id, the same UUID), `status`, `balance`, `available_balance` and `version`.
  - **What a posting locks.** Every posting and every status change takes `SELECT … FOR UPDATE` on that row, in ascending `id`. No money operation reads status without that lock.
  - **Hold lifecycle.** Holds live in `holds` (owned by `ledger`) with states `active → captured | released`.
    - A hold references exactly one transaction and one account.
    - Holds never expire by time. Only that transaction's terminal transition (AD-18) captures or releases them, in the same UoW.
  - **The only mutators of `balance` and `available_balance`:**
    - `Post`: a debit lowers both, a credit raises both.
    - `PlaceHold`: available −= amount.
    - `ReleaseHold`: available += amount.
    - `CaptureHold(hold, journal)`: in one call, release the hold and post exactly the hold amount. A capture that doesn't equal the hold amount is rejected; any remainder must be released explicitly.
  - **Normal balance.** Every ledger account has `normal_side` (customer accounts: C).
    - balance = Σ(normal_side) − Σ(opposite side).
    - Customer balance ≥ 0 and available_balance ≥ 0 are enforced by CHECK constraints.
  - **Invariant job (FR-13)** also verifies that `available_balance = balance − Σ active holds` and that no `active` hold belongs to a terminal transaction.

---

## F3 — Critical — Transaction state has many writers and no single transition path

**Units:** core-worker callback handler (MOCK→WRK webhook) and core-worker unknown-scan job (AD-15). Third and fourth units: admin-triggered "reconcile now" (admin-api→core→?), and the worker's own timeout handling after a partner call (AD-7).

**Divergence while compliant:**

1. **The timeout race.**
   - The timeout path runs `UPDATE transactions SET status='unknown' WHERE id=$1`.
   - At the same moment, the callback path posts the journal and sets `succeeded`.
   - Both pass the state-machine check they read earlier, and nothing in AD-7 demands a row lock or CAS.
   - The last writer wins: the status reads `unknown` but a journal exists. Recon later sees partner = success and posts again, so the deposit is credited twice.

2. **Late callbacks.**
   - AD-7 says "only reconciliation moves `unknown` to a final state".
   - Callback agent A treats a late signed success callback for an `unknown` transaction as recon evidence and finalizes it.
   - Agent B drops it, so the customer waits for the next backoff tick or the 30-minute alert.
   - Both readings are defensible, and they behave differently in the chaos tests.

3. **Duplicate callbacks.**
   - Webhooks aren't RabbitMQ messages (no AD-8 inbox) and don't carry `Idempotency-Key` (no AD-6).
   - Agent A dedupes on the partner's event id. Agent B dedupes on the current state.
   - The "duplicate callback" mock mode (AD-12) can send a *different* event id for the same result, which defeats A.

4. **Amount mismatch.**
   - A deposit callback carries an amount.
   - Agent A posts the callback amount. Agent B posts the requested amount. Neither is told to compare them.

5. **Conflicting terminal evidence.** For example, the callback says failed while recon says succeeded.
   - The `succeeded`/`failed` states are terminal.
   - One agent "fixes" the record by updating the status. Another ignores the evidence.

**Proposed AD-18 — Single transition path for transactions [PROPOSED] (tightens AD-7)**
- **Binds:** core `payment`, `recon`, `savings`; every core-worker handler and job
- **Rule:**
  - **One function.** Every change to a transaction's state goes through `payment.Transition(ctx, tx, txnID, expectedFrom, to, evidence)`, inside the caller's UoW (AD-16).
  - **Lock and CAS.** It locks the transaction row (`FOR UPDATE`) **before** any account row; account rows follow in ascending id. It applies the transition only if `status = expectedFrom`, and `version` is bumped.
  - **Effects live inside it.** Posting, `CaptureHold` and `ReleaseHold` happen only inside `Transition`, so no other code path changes money for a transaction.
  - **Idempotent terminal transitions.**
    - A repeated transition to the *same* terminal state with the same evidence returns success and has no effect.
    - A transition to a *different* terminal state is refused. It is recorded as a `PARTNER_ATTEMPT` with `outcome=conflict` and raises a critical `recon_conflict` alert. Fixing it requires an AD-23 correction transaction.
  - **Signed partner evidence.** A verified callback carrying a final result is reconciliation evidence and may move `pending|unknown → succeeded|failed`.
    - The callback must match `(our_txn_id, amount, currency)` exactly. On a mismatch, nothing is posted, the transaction moves to `unknown` (if it was pending), and a critical alert is raised.
  - **Callback dedupe** is by `(partner, our_txn_id, outcome)` through the state CAS above. The partner's event id is stored but never relied on.
  - **Who may finalize.**
    - Manual "reconcile now" from admin-api calls a core command, which enqueues a recon request through the outbox. Only core-worker queries the partner.
    - Only `Transition` may move `pending → unknown`. It does so when the partner call times out, or when the per-partner `callback_deadline` (config) passes, as detected by the scan job.

---

## F4 — Critical — The internal token doesn't constrain what an edge may assert, and authZ doesn't require ownership

**Units:** public-api (mints the internal token for customers) and admin-api (mints it for staff). Third unit: core authZ middleware.

**Divergence while compliant:**

1. **No issuer-to-actor-type binding.**
   - AD-10 says core "verifies the internal token and authorizes every use case against the actor", and the token is "signed by the edge".
   - Core agent A accepts any token signed by *any* trusted edge key, possibly one shared EdDSA key in `pkg/authn`, and authorizes by `actor.roles`.
   - Under that design, a compromised or buggy public-api can mint `actor_type=admin, roles=[quan_tri]`. This is exactly what AD-10's "Prevents" line claims to stop.

2. **Roles alone, no ownership check.**
   - The public-api agent passes the account id from the URL path. The core agent checks that the role is `customer` and that the account exists.
   - Nobody checks `account.customer_id == actor.subject_id`. The result is IDOR on transfer, statement and close.

3. **Edge-assigned admin roles.**
   - Admin roles are owned by admin-api (AD-1), so core sees whatever roles admin-api claims.
   - FR-22 says no one may assign themselves a role. That check exists only in admin-api, and nothing in core can detect when it is bypassed.

4. **Replay.** A token's 60 s TTL with no audience or `jti` lets a token captured on one RPC be replayed on another RPC within the window.

**Proposed tightening of AD-10 [PROPOSED]**
- **Rule (append):**
  - **Signing keys.**
    - Each edge has its own signing key pair (`kid` per edge). Core holds an allow-list mapping `kid → {issuer, allowed actor_types}`.
    - public-api may assert only `actor_type=customer`, and its roles are fixed to `[customer]`.
    - admin-api may assert only `actor_type=staff`.
    - core-worker and jobs use in-process `actor_type=system, subject=<job-name>` and never cross the network with it.
    - Core rejects a token whose actor type isn't allowed for its `kid`.
  - **Token claims.** The token carries `aud=core`, `iss`, `kid`, `jti`, `iat`, `exp` (≤ 60 s), `rpc` (the full gRPC method name), `actor_type`, `sub`, `roles`, `session_id`, `client_ip`, `user_agent`, `request_id`.
    - Core rejects the token if `rpc` ≠ the method being called.
  - **Customer actors.** Every use case resolves the target resources and checks `owner_customer_id == sub`, inside the UoW, before any effect. An ownership failure returns `not_found` (not `forbidden`), so callers can't enumerate accounts.
    - Core also rejects customer actors whose core customer status ≠ `active` for money commands (see AD-19).
  - **Staff actors.**
    - The permission matrix (role → use case) lives in core as code (`authz` table-driven tests).
    - Roles in the token are trusted as asserted by admin-api. This trust boundary is explicit: admin-api's signing key is a Tier-0 secret.
    - Role-change commands are themselves core-audited events from admin-api (AD-11).

---

## F5 — Critical — Customer identity linkage and registration ownership are undefined

**Units:** public-api `auth/registration` (owns credentials, AD-1) and core `customer` (owns profile, eKYC, phone and CCCD uniqueness, AD-1).

**Divergence while compliant:**

1. **Which side creates the customer first?** BF-1 is one HTTP request that creates state in *two* databases, and "no transaction spans services".
   - Agent A (public-api) inserts the credential first, then calls `core.RegisterCustomer`. A core 409 or a timeout leaves an orphan credential that can log in.
   - Agent B (core) creates the customer and emits `customer.registered`. public-api then has to create the credential from the event, but the password hash isn't in the event (it mustn't be), so the credential can never be created.

2. **What is the JWT `sub`?**
   - Agent A uses the public-api `credential_id`. Agent B (core) expects `customer_id` in `x-actor.sub` for ownership checks.
   - The result is either that every ownership check fails, or that someone "fixes" it by having core look the customer up by phone from the token. Phone is mutable and has two owners, so that's an identity confusion risk.

3. **Phone has two owners.** It's the login identifier in public-api and a profile field with a uniqueness rule in core (FR-1). A phone change done by either side diverges from the other.

4. **Customer status at login.**
   - FR-4 doesn't say whether `pending_ekyc` or `rejected` customers may log in.
   - public-api can't see core status. A rejected customer keeps working refresh tokens indefinitely.

5. **Images.**
   - FR-1 images go to "an object store" that appears in no AD, deployable or Stack row.
   - The public-api agent uploads them under its own bucket and credentials. The core-worker agent (eKYC submit) needs to read them and was never granted access.
   - Neither side owns deletion or retention for the images.

**Proposed AD-19 — Customer identity & registration [PROPOSED]**
- **Binds:** public-api, core `customer`, core-worker eKYC, object storage
- **Rule:**
  - **One identity.**
    - `customer_id` (UUIDv7, minted by core) is the single customer identity.
    - The public-api credential row is keyed by `customer_id` (PK, no separate credential id).
    - JWT `sub` and `x-actor.sub` = `customer_id`.
  - **Who owns phone and CCCD.** Core owns phone and CCCD and their uniqueness. public-api stores `login_phone` only as a lookup copy, updated solely from core event `banking.customer.customer.phone_changed.v1`.
  - **Registration order (public-api):**
    1. Verify the password policy and hash with argon2id (the hash never leaves public-api).
    2. Upload images to the object store under `kyc/<registration_id>/…` with a pre-signed, write-only URL. The registration id is derived from `Idempotency-Key`.
    3. Call `core.RegisterCustomer` (idempotency key `reg:<Idempotency-Key>`). Core dedupes phone and CCCD (409) and returns `customer_id`.
    4. Insert the credential keyed by `customer_id` in public-api's tx.
    - A retry with the same key replays steps 3 and 4. A core customer with no credential after 24 h is swept to `rejected(reason=registration_abandoned)` by a core job.
  - **Login gate.**
    - Login is allowed only for customers whose status is in the `login_allowed` set, which is `{active, pending_ekyc, pending_review}` (read-only).
    - public-api keeps that status from core events (versioned, AD-8 tightening).
    - When the status becomes `rejected` or another blocking state, public-api revokes all of the customer's refresh tokens.
    - Core independently enforces `active` for money commands (AD-10 tightening).
  - **Object store.**
    - The object store is a named dependency: S3 in prod, MinIO in staging.
    - Buckets and roles: public-api has write-only access to the `kyc/` prefix, and core-worker has read-only access.
    - Core stores only the object keys. Images are never logged, audited or put in events.

---

## F6 — High — Idempotency scope, hash and in-flight semantics are undefined

**Units:** public-api transfer endpoint (forwards the key) and core `payment` (stores the key, AD-6). Third unit: admin-api and core-worker calling core commands without a client key.

**Divergence while compliant:**

1. **Scope.**
   - AD-6 stores `(scope, key, …)` but doesn't define scope.
   - Agent A uses scope = RPC method. Customer X's key `abc` and customer Y's key `abc` then collide: Y receives **X's stored response**, which leaks X's transaction, or gets a spurious 422.
   - Agent B uses scope = customer + method.

2. **Request hash.**
   - Agent A hashes the REST JSON body at the edge. Agent B (core) hashes `proto.Marshal(req)`.
   - Protobuf marshaling isn't canonical, and the edge may inject fields (trace, OTP assertion, timestamps), so honest retries come back as 422.

3. **Concurrent first use.**
   - Two simultaneous requests with the same key both miss the lookup and both execute.
   - The unique constraint fires only at commit, after locks and work. Agent A returns 500. Agent B retries and replays.
   - For the async withdraw flow the stored response is `202 pending`, so a retry sees `pending` forever, even after the transaction is `succeeded`.

4. **Failed outcomes.**
   - BF-3 rolls back and then "records a failed transaction". If the idempotency row isn't written with that failed record, a retry after a top-up succeeds under the same key, giving two different outcomes for one key.

5. **System-originated commands.** Maker-checker execution, saga steps and worker retries have no client key. An agent invents a random UUID per attempt, and the retry double-executes (see F7).

**Proposed tightening of AD-6 [PROPOSED]**
- **Rule (replace the scope and hash sentences):**
  - **Scope** = `(actor_type, actor_sub, full_rpc_method)`.
  - **Request hash** = SHA-256 of a canonical encoding: the RPC's declared *business fields only* (an annotated proto option), deterministically marshaled. The edge sends the original key. Core computes the hash, and the edge's own copy (if any) is advisory.
  - **Insert first.** The idempotency row is inserted at the **start** of the UoW (`INSERT … ON CONFLICT DO NOTHING RETURNING`).
    - On a conflict whose existing row is `in_progress` (the other UoW hasn't committed), the caller waits on the row lock up to `lock_timeout`, then returns 409 `idempotency_in_progress` (retryable).
  - **Stored results.**
    - Business outcomes are stored and replayed: success, and domain rejection that yields a `failed` transaction.
    - Validation errors that create no record are not stored.
  - **Async replays.** For async flows the stored response is the resource reference (`transactionId`). A replay returns **the current state of that resource**, not the original 202 body.
  - **System-originated keys** are deterministic: `<origin>:<origin_entity_id>:<step>` (for example `mc:<approval_request_id>:execute`, `reg:<client_key>`, `recon:<txn_id>:<attempt_no>`). Random keys are forbidden.
  - **Retention:** 72 h. That's ≥ 24 h per FR-14, plus margin for the R3 recon window.

---

## F7 — High — Maker-checker execution has two sources of truth

**Units:** admin-api `makerchecker` (owns requests, AD-1, BF-9) and core command handlers (balance adjustment, block, limit/fee change, AD-2).

**Divergence while compliant:**

1. **Retries without a stable key.**
   - Agent A (admin-api) marks the request `approved`, calls core synchronously, and marks it `executed` on success.
   - The gRPC call times out after core committed. admin-api retries with a new idempotency key, so a **balance adjustment is posted twice**.
   - Agent B executes through admin-api's outbox: a consumer calls core. At-least-once redelivery has the same problem unless the key is stable.

2. **Who checks maker≠checker.**
   - The maker≠checker check, the checker's role and request expiry are checked only in admin-api.
   - Core receives a plain `AdjustBalance` command from a staff actor whose roles allow it, which bypasses the whole maker-checker control. A single staff user with the right role can call the core RPC directly through any admin-api path that forwards it.

3. **Stale before-value.**
   - The maker captured the "before" value (the old limit) at request time. Another change lands first.
   - The checker then approves an edit built on a stale before-value, and core applies it over the newer value.

**Proposed AD-20 — Approved-command execution [PROPOSED]**
- **Binds:** admin-api maker-checker, core commands marked `requires_approval`
- **Rule:**
  - **Approval proof required.** Core commands annotated `requires_approval` refuse to run without an `approval` block: `{request_id, maker_sub, checker_sub, approved_at, expires_at, payload_hash, expected_target_version}`.
  - **Core re-verifies every time:**
    - `maker_sub ≠ checker_sub`;
    - the checker's role allows that command;
    - `now < expires_at`;
    - `payload_hash` matches the command;
    - the target's current `version == expected_target_version`. Otherwise the command is rejected with `approval_stale`.
  - **Stable key.** The idempotency key is always `mc:<request_id>:execute` (AD-6 tightening).
  - **admin-api states:** `waiting_approval → approved → executing → executed | execution_failed | expired | rejected`.
    - `executed` and `execution_failed` are set only from core's response or its idempotent replay.
    - Execution is driven by admin-api's outbox, retried until core answers.
  - **Audit.** Core audits the executed change with both maker and checker as actors (AD-11).

---

## F8 — High — Fees, limits and OTP: computed twice, rounding undefined, counters racy, OTP edge-only

**Units:** core `pricing` (fee and limit, R2) and core `payment` (interbank, BF-8). Third unit: public-api OTP sessions (AD-1).

**Divergence while compliant (AD-2 is satisfied, since "only core computes", but core computes twice):**

1. **Fee computed twice.**
   - The quote shown to the customer comes from `pricing.Quote`.
   - At execution `payment` recomputes from the *current* schedule. A maker-checker fee change approved in between charges a different fee than the customer saw.

2. **Fee recomputed at capture.**
   - The hold is placed for amount + fee computed at hold time. At the callback (tx2) the agent recomputes the fee, so the capture ≠ the hold.
   - Under F2/AD-17 this capture is rejected. Without AD-17 it drifts.

3. **Rounding.**
   - A percentage fee on VND: agent A uses `math.Round(float64)`, which violates "never floats" but only in an intermediate value. Agent B uses integer floor.
   - The interest accrual agent rounds each day and loses up to 1 đồng per account per day. After a year the figure no longer matches the "total for the term" computation.

4. **Limit consumption.**
   - Agent A counts daily usage as Σ`succeeded`. Agent B counts on creation.
   - With A, ten concurrent interbank transfers all `pending` pass a succeeded-only daily limit, so the **limit is bypassed**.

5. **OTP enforcement.**
   - public-api owns OTP sessions, and core owns the OTP threshold (UJ-9 config through maker-checker).
   - Agent A (public-api) fetches and caches the threshold and decides whether OTP is needed. Core then executes whatever public-api forwards.
   - A buggy edge, or a client splitting amount and fee around the threshold, skips OTP. Core can't tell.

**Proposed AD-21 — Pricing, limits and step-up are decided once, in core [PROPOSED]**
- **Binds:** core `pricing`, `payment`, `savings`; public-api OTP
- **Rule:**
  - **Two steps.** Fee-bearing and limit-bearing payments are created in two steps:
    1. `CreatePaymentDraft` computes fee, limit check and `step_up_required`, and persists `{amount, fee, fee_schedule_version, limit_snapshot}` with an expiry of 5 min.
    2. `ConfirmPayment(draft_id, step_up_assertion?)`.
  - **Persisted amounts are final.** Hold = amount + fee from the draft. Capture and posting use only the persisted values and are never recomputed.
  - **Rounding.** All rates are integers: fee in basis points, interest in ppm per annum. Each money result is computed in integer arithmetic with a defined rounding mode per product, in the fee/interest spec. The default is round-half-up to the đồng, with fee min/max clamps applied after rounding.
    - Interest is accrued **cumulatively**: post `round(total_to_date) − posted_to_date` each business day, so daily rounding never drifts.
  - **Limit usage.**
    - Usage is held in a per `(customer_id, limit_kind, period_key)` counter row, locked `FOR UPDATE` inside the confirming UoW.
    - Usage is consumed at creation, counting pending, unknown and succeeded, and returned only by a `failed` transition (AD-18).
  - **Step-up.**
    - When `step_up_required`, core accepts confirmation only with a `step_up_assertion`: a public-api-signed JWT `{draft_id, payload_hash, sub, method=otp, iat, exp ≤ 120 s}`, verified by core against public-api's `kid`.
    - Core decides the requirement. public-api only performs the challenge.

---

## F9 — High — `business_date` has no owner, timezone or cutover rule

**Units:** core `ledger` (stamps journals) and core `eod` (R3, "locks the day, opens a new day"). Third units: `pricing` daily limits, `savings` accrual, recon file matching.

**Divergence while compliant (Conventions say only "`business_date` (DATE) for accounting"):**
- **R1 ledger agent:** `business_date = (now() AT TIME ZONE 'UTC')::date`, because R1 has no EOD. Vietnamese 00:00–07:00 postings then get yesterday's date.
- **R3 EOD agent:** reads an `eod.current_business_date` row, which R1 never created. Migrating R1 journals is impossible, because they're append-only and can't be fixed in place.
- **Limits agent:** uses the calendar day in Asia/Ho_Chi_Minh. A transfer at 23:59 local after EOD has already advanced is counted against a different "day" than its journal.
- **Withdraw:** tx1 runs on day D and the callback (tx2) on D+1. One agent stamps the journal with the transaction's creation date; another stamps it with the posting date.
- **EOD while postings are in flight:** agent A blocks all postings while EOD runs (which breaks SM-2). Agent B doesn't lock at all, so journals land in a closed day.

**Proposed AD-22 — Business day [PROPOSED]**
- **Binds:** core `ledger`, `eod`, `pricing`, `savings`, `recon`
- **Rule:**
  - **Owner and R1 behavior.** Core `eod` owns a single `business_day` row `{open_date, state: open|closing}` from **R1**. In R1 a core-worker job rolls it forward at 00:00 Asia/Ho_Chi_Minh; in R3 EOD replaces that job.
  - **Stamping journals.** Each journal's `business_date` = `open_date`, read with `FOR SHARE` on `business_day` inside the posting UoW. Its value is the business date of the **posting** (tx2), not of the transaction's creation.
  - **EOD cutover.**
    - EOD first takes `FOR UPDATE` on `business_day`, which waits only for in-flight postings, and flips `open_date := D+1, state := closing(D)`, then commits.
    - From then on new postings go to D+1. EOD steps for D (accrual, invariant, balance report) run on the frozen D.
    - No journal may ever be inserted with `business_date < open_date` except by EOD for D while closing.
  - **Customer-facing periods** (daily limits, statements by day) use the local calendar date in Asia/Ho_Chi_Minh of `created_at`, not `business_date`. All accounting and interest use `business_date`.

---

## F10 — High — Partner calls: re-send vs query, webhook replay, deadline ownership

**Units:** core-worker payout dispatcher (consumes the AD-7 tx1 outbox message) and mock-gateway (AD-12). Third unit: core-worker webhook receiver.

**Divergence while compliant:**

1. **Redelivery after a crash.**
   - The worker calls the partner and crashes before tx2. RabbitMQ redelivers the message (AD-8 at-least-once). The inbox row was never committed, because the effect tx never ran.
   - Agent A re-sends the payout "with our transaction id as idempotency key", which is fine only if the partner dedupes.
   - The mock agent implements the six failure modes of AD-12, none of which is "dedupe by idempotency key". The result is a **double payout** that the SM-1 chaos test will flag as "real" behavior and might get papered over.

2. **Webhook replay.**
   - HMAC-SHA256 with no timestamp lets a captured success callback be replayed. AD-18's state CAS mitigates this for the same transaction.
   - Agent A verifies the signature over the parsed-and-re-serialized JSON, so valid callbacks fail at random. Agent B uses non-constant-time compare.

3. **Who moves pending to unknown, and when?** AD-7 says "timeout or missing callback → `unknown`" without naming the deadline or the actor that applies it.

**Proposed tightening of AD-7 and AD-12 [PROPOSED]**
- **AD-7 (append):**
  - **Attempts table.** Before the first network call, core-worker commits a `partner_attempts` row `{txn_id, attempt_no, kind=submit|query, sent_at}`.
  - **Redelivery queries, never re-sends.** If a `submit` attempt already exists when a message is redelivered, the worker sends a **status query**, never a second submit.
  - **Deadlines.** Each partner has `submit_timeout` and `callback_deadline` in config. The unknown-scan job (AD-15) applies `pending → unknown` through AD-18 when `callback_deadline` passes.
- **AD-12 (append):**
  - **Mocks behave like real partners.** Every mock dedupes submits by `idempotency_key` (our txn id) for ≥ 7 days and exposes `GET /v1/transactions/{our_txn_id}` for status.
  - **Webhook signing.**
    - Headers: `X-Signature: v1=<hex(HMAC-SHA256(secret, timestamp + "." + raw_body))>` and `X-Timestamp`.
    - Receivers verify over the **raw body bytes** before parsing, with constant-time compare and a ±300 s window.
    - Secrets are per partner and per environment, and rotation is supported by accepting two active secrets.
  - **Receiving host.** The webhook receiver is a dedicated HTTP listener in core-worker, exposed through Gateway API on a separate host. It is never routed through public-api or admin-api.

---

## F11 — High — Audit: double, missing or partial records for one action

**Units:** admin-api (publishes audit events through its outbox, AD-11) and core `audit` (writes in the same tx as core changes, AD-11).

**Divergence while compliant:**

1. **Double or missing records.**
   - A GDV blocks an account. admin-api emits `audit: account.block`, and core also writes an audit record in its tx, so there are two records with different shapes.
   - Or each side assumes the other writes it, and there are none, which violates SM-4's "100% of admin operations audited".

2. **No IP in core.** FR-23 requires the IP. `x-actor` carries "actor type, subject id, roles, session id" but no IP or user agent, so every core-written audit record lacks the IP.

3. **No schema.**
   - Each edge invents its own audit payload, and core's consumer maps them ad hoc.
   - "before/after" for a password change: one agent puts the hash in `after`, because a hash is "not the password".

4. **Duplicate edge events.** Edge audit events are at-least-once. If the consumer inbox is keyed by RabbitMQ delivery and not by the event id, they're duplicated.

**Proposed tightening of AD-11 [PROPOSED]**
- **Rule (append):**
  - **Who writes the record.**
    - **The service that commits the change writes the audit record.** Core writes it for every core state change.
    - Edges emit audit events only for edge-owned facts: login success or failure, lockout, logout, session expiry, TOTP enrolment, admin user and role changes, maker-checker request lifecycle, and OTP challenge results.
    - An edge never emits an audit event for a change that core commits.
  - **One schema.** The single schema is `banking.audit.v1.AuditRecord` in `/proto`: `{id (UUIDv7 = source event id), occurred_at, actor{type, sub, roles, session_id}, approver?{sub}, client_ip, user_agent, request_id, trace_id, action (enum-like string "<module>.<entity>.<verb>"), target{type, id}, outcome (success|denied|failed), reason_code?, before?, after?}`.
  - **before/after** contain only fields from a per-entity allow-list. Credential material (hashes, TOTP secrets, tokens, OTPs) and images are never included, not even hashed.
  - **IP and user agent come from the token.** `client_ip` and `user_agent` come from `x-actor` (AD-10 tightening). The edge derives `client_ip` from the Gateway's trusted forwarded header only.
  - **Ingestion dedupe.** Ingestion dedupes on `AuditRecord.id`. Denied authZ decisions in core are also audited (`outcome=denied`).

---

## F12 — High — Event ordering, namespace and versioning

**Units:** core `customer` (emits status events) and public-api (consumes them for the login gate and phone, AD-19). Also any two edges emitting events.

**Divergence while compliant:**

1. **Out-of-order delivery.**
   - AD-8's delayed retry and DLQ replay reorder messages.
   - public-api receives `customer.rejected`, then a retried earlier `customer.activated`. It applies the latter, so a **rejected customer can log in**.
   - The inbox dedupes by id; it doesn't order.

2. **Edges have no namespace.** The naming convention is `banking.<module>.<entity>.<past_verb>`, but edges have no modules. public-api emits `banking.auth.login.failed` while admin-api emits `banking.auth.login.failed` for staff, and the types collide.

3. **No major version.**
   - `buf breaking` blocks wire-incompatible changes but not semantic ones. For example, `amount` starts including the fee.
   - With no version in `type`, consumers can't distinguish the old and new meaning.

4. **Commands vs events.** The AD-7 tx1 "outbox message" is a command to core-worker, yet the naming covers only past-tense events. One agent names it `banking.payment.withdrawal.requested` and fans it out on the events exchange, so every subscriber sees it. Another publishes to a direct queue.

**Proposed tightening of AD-8 and AD-9 and the Naming convention [PROPOSED]**
- **Event types** are `banking.<context>.<entity>.<past_verb>.v<major>`.
  - `<context>` = the core module name, or `identity` for public-api, or `backoffice` for admin-api.
  - The CloudEvents `subject` = the aggregate id, and the extension `aggregateversion` = a monotonic per-aggregate version.
  - A semantic change to a field bumps `<major>`, and producers dual-publish during migration.
- **Ordering.** Consumers that maintain state from events store the last applied `aggregateversion` per subject and ignore older ones. No consumer may assume delivery order.
- **Commands** (work requests for core-worker) are `banking.<module>.<command_verb>.v<major>` (imperative), routed to a direct exchange `banking.commands` with one queue per command type. They're never published on the topic exchange `banking.events`.
- **Topology** is defined once in `deploy/` (exchanges `banking.events` topic, `banking.commands` direct, `banking.retry.<n>` delayed, `<queue>.dlq`). Services declare only their own queues.

---

## F13 — High — Corrections and transaction kinds: reversals can be attached anywhere

**Units:** core `ledger` (AD-4 "corrections are reversing journals") and core `recon` (R3, BF-10, an after-the-fact mismatch on a `succeeded` transaction). Also admin balance adjustment (BF-9).

**Divergence while compliant:**
- The ERD says TRANSACTION `||--o|` JOURNAL, so a transaction has zero or one journal.
- The recon agent finds that NAPAS never settled a `succeeded` transfer and posts a reversing journal:
  - Agent A attaches it to the same transaction, which violates 0..1, or quietly changes the relation to 1..n.
  - Agent B posts a journal with **no** transaction, because it's "a ledger correction". That journal is invisible to statements, which are built from transactions, and to idempotency.
  - Agent C flips the original's status to `failed`, which violates the terminal-state rule (FR-18).
- Balance adjustments (maker-checker) and savings accrual journals have the same hole: does each get a transaction, and of what kind?

**Proposed AD-23 — Transaction kinds & corrections [PROPOSED]**
- **Binds:** core `payment`, `ledger`, `recon`, `savings`, `eod`
- **Rule:**
  - **Every journal belongs to exactly one transaction.** `journals.transaction_id NOT NULL UNIQUE`, so the relation is 1:1.
  - **Transaction kinds.** Transactions have `kind ∈ {deposit, withdrawal, internal_transfer, interbank_transfer, fee, balance_adjustment, reversal, interest_accrual, interest_payout, savings_open, savings_settle}`. The kind list is extended only by spine amendment.
  - **Corrections are new transactions.** A correction is a new transaction of kind `reversal` with `reverses_transaction_id`. Its journal mirrors the original's entries, with sides swapped, partially if needed, and it's created only through an approved command (AD-20).
  - **Terminal states never change.** The original keeps its terminal state, and statements show both transactions.
  - **Internal-only journals** (accrual, snapshots excluded) are transactions with `actor_type=system` and an AD-6 system key.

---

## F14 — Medium — Shared infrastructure tables inside core and relay ownership

**Units:** core `payment` and core `customer` (both write outbox messages); also core vs core-worker (both are the same codebase and the same DB, AD-1).

**Divergence while compliant:**
- AD-3 says "a module accesses only its own tables". Agent A therefore builds `payment_outbox` and `customer_outbox`. Agent B uses one `outbox` table through `pkg/outbox`.
- The relay must know every table.
- Both `cmd/core` and `cmd/core-worker` start the relay "because it's in the shared code", so N replicas publish the same rows.
  - At-least-once makes that tolerable, but it multiplies duplicates and destroys per-aggregate ordering.
  - Advisory locks (AD-15) cover only periodic jobs.
- The same split happens for `inbox` and `idempotency_keys`.

**Proposed tightening of AD-3 and AD-8 [PROPOSED]**
- **Exempt tables.** In each service DB, the tables `outbox`, `inbox`, `idempotency_keys` and `audit_records` (core only) are owned by `pkg/*` infrastructure and are exempt from the module-table rule. Modules write to them only through the `pkg` API, in the UoW.
- **Relay.** The outbox relay runs **only** in core-worker (and, for the edges, in their own process). It claims rows with `FOR UPDATE SKIP LOCKED` in `(aggregate_id, seq)` order, so a single aggregate is published in order.

---

## F15 — Medium — Customer-facing addressing and statement shape

**Units:** web-customer (generated client) and core `account` and `payment` (proto).

**Divergence while compliant:**
- The transfer destination is typed by a human as a 12-digit account number, while internal ids are UUIDv7 (Conventions).
  - Agent A exposes `destinationAccountId` (UUID). The SPA then needs a lookup endpoint, which nobody specified, and that endpoint is an enumeration/PII oracle (name disclosure).
  - Agent B exposes `destinationAccountNumber`.
- FR-9 requires "balance after each transaction".
  - Agent A computes it with a window function over entries ordered by `created_at`. UUIDv7 and `created_at` aren't commit order under concurrency, so the running balances come out non-monotonic.
  - Agent B stores `balance_after` on the entry at post time, under the AD-5 lock.

**Proposed Conventions rows [PROPOSED]**
- **Addressing.**
  - External APIs address *own* accounts by `accountId` (UUID) and *counterparty* accounts by `accountNumber` (12-digit, Luhn validated at the edge and in core).
  - Name lookup returns a masked holder name only. It is rate-limited per customer in public-api and audited.
- **Statements.**
  - Customer-account entries store `balance_after` and a per-account monotonic `seq`, both assigned under the account row lock (AD-17).
  - Statements order by `seq` and paginate by `seq` cursor.

---

## Also noted (not expanded)

- AD-15's "idempotent per (job, business_date / window)" needs AD-22 to define business_date. Until then the R1 jobs have no key.
- AD-5's internal-account snapshot and the FR-13 "Σdebit = Σcredit system-wide" check must read at a consistent snapshot. Use `REPEATABLE READ`, or bound the check by journal `seq`. Otherwise in-flight commits produce false alerts.
- Account close (BF-6/FR-8) must lock the account row and check `balance = 0 ∧ no active holds ∧ no pending/unknown transactions` in one UoW. Otherwise a deposit in flight is credited to a `closed` account. Covered by AD-17 once status shares the locked row.
- The Deferred list postpones R2–R4 data shapes. F7, F8, F9 and F13 show that their *ownership and invariants* can't be deferred without forcing R1 schema migrations of append-only tables. Decide the invariants now, and defer only the field lists.
