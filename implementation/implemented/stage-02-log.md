# Stage 2 — The contribution log

**Status:** implemented · tag `stage-02-log` · decisions recorded 2026-09-17

## Plan

**Tag:** `stage-02-log` · **Spec:** 02 §1.1, §1.1a, §1.2, §1.2a, §3.1, §3.6, §5 (permissions rule only), 05 §4–5, 06 §1–2 (meta, log, contributions endpoints)

Goal: the append-only, hash-chained log with gap-free `seq`, server signatures, genesis,
key registration, delegation, revocation, verification, and the single write endpoint.
Epistemic action types are accepted into the log but produce no projections yet.

Deliverables:

- `contributions` table exactly per 02 §3.1, with unique indexes on `seq`, `entry_hash`,
  `idempotency_key`, and index `(contributor_id, seq)`.
- `agent_delegations` table per 02 §3.1.
- `Ledger::Append.call(envelope)`: validate schema and closed enums, verify client
  signature, resolve `contributor_id` from `signer_key_id` (reject mismatch), check key
  and delegation not revoked at receipt, classify CONTROL vs EPISTEMIC, check control
  authorization, take `pg_advisory_xact_lock`, assign `seq`, compute `entry_hash` per
  02 §1.2, server-sign, persist, set `current_status` (PENDING for epistemic, ACCEPTED for
  control). Returns the existing row on idempotency-key match.
- Genesis: `ledger:genesis` creates seq 0 as the self-signed system `REGISTER_KEY`; boot
  and replay verify it matches the pinned public key.
- `Ledger::Apply` skeleton with a dispatcher to `Ledger::Appliers::*`; appliers for
  `REGISTER_KEY`, `DELEGATE`, `REVOKE_KEY`, `REVOKE_DELEGATION` (contributor and delegation
  rows). `Ledger.applying?` thread-local flag.
- `Ledger::Verify` and `bin/rails ledger:verify`: recompute every `entry_hash`, check
  every client and server signature, report the first break with its `seq`.
- `Ledger::Replay` and `bin/rails ledger:replay`: truncate projections and re-apply in
  `seq` order (only key/delegation projections exist yet).
- Database role: migration creating an application role with no `DELETE` on
  `contributions` and `UPDATE` only on `current_status`; the app connects as that role in
  development and test. Document how the migration role differs.
- Endpoints: `GET /api/v1/meta` (adds `current_seq`), `GET /api/v1/log?after_seq=&limit=`,
  `GET /api/v1/contributions/:id`, `GET /api/v1/contributions/:id/verify`,
  `POST /api/v1/contributions` with the 06 §1 error format. Rate limiting keyed by
  `key_id`.
- `Contributions::ValidateEnvelope` with the closed action-type list from 02 §3.6.

Acceptance (07 Phase 1):

1. 50 concurrent appends produce a gap-free `seq` and a valid chain (#3).
2. Revoked key or delegation cannot append after its revocation `seq` (#4).
3. Historical contributions from a now-revoked key still verify (#5).
4. `ledger:verify` detects a manually corrupted row and reports its `seq` (#6).
5. Duplicate submission returns the original contribution with HTTP 200 (#7).
6. Genesis and bootstrap rules (#8).
7. Control contributions take effect without `ACCEPT`; unauthorized control contributions
   are rejected and not logged (#9).
8. The app role cannot delete a contribution or update its payload (07 "append-only DB
   permissions").

## Decision Log (2026-09-17)

- Envelope protocol for ordinary contributions is `eir-contribution-v1` with fields
  `protocol, action_type, signer_key_id, delegation_id?, task_id?, task_packet_hash?,
  client_created_at, software?, payload, payload_hash, signature`. The signature covers
  the canonical envelope minus `signature`. The spec's `04 §4` result envelope
  (`eir-result-v1`, `contributor_key_id`) is a separate protocol handled in Stage 8; the
  log column stays `signer_key_id` per `02 §1.2a`.
- Hash chain exactly per `02 §1.2`: `entry_hash = sha256(canonical({seq, prev_hash,
  envelope_hash, received_at}))`, genesis `prev_hash` is 64 zeros without a prefix,
  `received_at` is UTC RFC 3339 with six fractional digits and is floored to
  microseconds before hashing so the stored timestamptz round-trips. The server signs
  the `entry_hash` string with the system key. Appends serialize on
  `pg_advisory_xact_lock` inside the insert transaction.
- `idempotency_key = sha256("<signer_key_id>|<task_id>|<payload_hash>")` per `02 §3.1`
  (an empty task_id for non-task contributions). The duplicate check runs before any
  other validation so a resubmission always returns the original, even for a
  `REGISTER_KEY` whose key is by then already registered.
- **Deterministic projection ids.** Replay must reproduce projection rows byte for byte
  (`02 §1.1` rule 3), which UUIDv7 cannot do. Log rows keep UUIDv7; projection rows get
  `Ledger::Ids.derive(contribution_id, kind)`, a UUID (version nibble 8) from sha256.
  Projection tables also carry no `created_at`/`updated_at`; `created_seq` is the time
  axis. This narrows the spec's "UUIDv7 primary keys" to the log; recorded for the owner.
- **Custody material moved off `contributors`.** `02 §3.1` puts `encrypted_private_key`
  and `user_id` on contributors, but replay truncates projections and the log cannot
  rebuild key material. They now live in `custodied_keys` (not a projection, survives
  replay). No foreign keys point at projection tables, so `TRUNCATE` works without
  cascading; integrity is Apply's job and is covered by the replay spec.
- Control vs epistemic per `02 §1.1a`. Control types with appliers (`REGISTER_KEY`,
  `DELEGATE`, `REVOKE_KEY`, `REVOKE_DELEGATION`) are authorized before the row is
  written and rejected unlogged otherwise. Other control types and `TASK_RESULT` are
  rejected as `UNSUPPORTED_ACTION` until their stage arrives; ordinary epistemic types
  are logged `PENDING` with no payload validation yet (Stage 3 adds it). Authorization
  rules chosen: only a HUMAN may `DELEGATE`, and only to an unrevoked AGENT; a key is
  revoked by itself or by a HUMAN holding an active delegation to it; a delegation by
  its principal or delegate; the SYSTEM key is never revoked; a SYSTEM `REGISTER_KEY`
  is accepted only as genesis. AGENT signers must carry a live delegation for every
  action except `REGISTER_KEY` and `REVOKE_KEY`; task-type and domain permission
  checks arrive with tasks in Stage 8.
- `compromised_since` on `REVOKE_KEY` marks that key's contributions from that seq on
  `CHALLENGED` (cached column). Audit queueing is Stage 7.
- Genesis is explicit: `bin/rails ledger:genesis` (Compose runs it after `db:prepare`;
  the suite runs it in `before(:suite)`). An empty log accepts nothing else; every
  later append and `ledger:verify` re-check that seq 0 registers the pinned key and
  raise `GenesisMismatch` otherwise. No boot-time database access.
- `Ledger::Verify` derives public keys from `REGISTER_KEY` entries as it walks the log,
  never from projections, and reports the first break with its seq.
  `GET /contributions/:id/verify` does the local checks including the stored payload
  against `payload_hash`.
- **Database role.** `galedra_app` is a NOLOGIN role created and granted idempotently by
  `Ledger::DatabaseRole.ensure_all!`, hooked after `db:prepare`, `db:migrate`,
  `db:schema:load`, `db:setup`, `db:reset`, and `db:test:prepare`, and after the test
  schema check in `rails_helper`. Grants: everything on all tables and sequences
  (default privileges for future ones), then `REVOKE UPDATE, DELETE, TRUNCATE` on
  contributions and `GRANT UPDATE (current_status)`. Runtime connections run
  `SET ROLE galedra_app` in the adapter's `configure_connection`; `db:*` tasks are
  detected and stay on the owner. `Ledger::DatabaseRole.as_owner` is the explicit
  escape hatch (tests use it to corrupt rows; Stage 4 uses it for `TAKEDOWN`).
  Production may connect directly as a LOGIN version of the role with
  `LEDGER_DB_APP_ROLE=false`. Grants are not in `schema.rb`, which is why the hooks
  re-apply them after every schema load.
- Rails 7.2+ leases a connection to the thread for good when code calls
  `Model.connection`; the first version of Append did that in `lock!`, so a
  50-thread test starved after five appends. Services now use block-scoped
  `with_connection`. Fifty concurrent appends complete in about 0.2 s.
- Test database `checkout_timeout` is 60 s so 50 appending threads can queue for a
  pool of 5; the property under test is the append lock, not pool sizing.
- Ruby 4.0 removed `benchmark` from the default gems; nothing in the app needs it.
- Constitutional Test (identity and history are touched): 1 yes, every entry is
  hash-chained and signed twice; 2 unchanged; 3 no new hidden authority, the system
  key holder remains the open question; 4 no; 5 n/a; 6 yes, verify and replay are
  specified and tested; 7 yes, anyone can mirror `GET /log` and verify; 8 yes, the
  log is the history; 9 n/a; 10 yes.
- Acceptance: all Phase 1 items #3–#9 and the append-only permissions have specs
  (`spec/services/ledger/*`, `spec/requests/api/v1/contributions_spec.rb`);
  `bundle exec rspec`, RuboCop, and Brakeman pass; the Compose stack runs genesis on
  boot and `ledger:verify` reports `CHAIN_VERIFIED` inside the container.
