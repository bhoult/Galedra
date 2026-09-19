# Stage 3 — Evidence graph projections

**Status:** implemented · tag `stage-03-projections` · decisions recorded 2026-09-17

## Plan

**Tag:** `stage-03-projections` · **Spec:** 02 §1.1a, §1.3, §2, §3.2–3.3, §3.6, §4, 06 §2 graph reads, 11 §5–6

Goal: every P0 epistemic action type produces projection rows through `Ledger::Apply`
only, with validity windows, acceptance, invalidation, supersession, merges, and replay
equivalence. No scoring.

Deliverables:

- `Projection` concern: `created_seq`, `invalidated_seq`, optional `accepted_seq`,
  `active_at(seq)` and `counted_at(seq)` scopes, `readonly?` unless `Ledger.applying?`.
- Tables and models: `sources`, `source_locations`, `claims`, `claim_edges`,
  `independence_groups`, `evidence_items`, `evidence_claim_links`, with the indexes in
  11 §6. Enums as validated string columns. JSONB for `qualifiers`, `locator`,
  `structured_value`, `assessment`, `metadata`.
- Appliers for `CREATE_SOURCE`, `CREATE_SOURCE_LOCATION`, `CREATE_CLAIM`,
  `SUPERSEDE_CLAIM`, `SET_TRUTH_EVALUABLE`, `CREATE_EVIDENCE`, `LINK_EVIDENCE`,
  `CREATE_CLAIM_EDGE`, `CREATE_INDEPENDENCE_GROUP`, `ASSIGN_INDEPENDENCE_GROUP`,
  `SUPERSEDE_LINK`, `MERGE_CLAIMS`, `ACCEPT`, `INVALIDATE`.
- Acceptance rules from 02 §1.1a: system auto-`ACCEPT` after validation for direct
  human-created sources, locations, evidence, and links; a different principal required
  for extraction-proposed claims, cross-principal supersessions and merges, and
  `SET_TRUTH_EVALUABLE`. Claims created directly by a human are auto-accepted.
- Source content via Active Storage; `content_hash` over bytes; `CHAR_RANGE` excerpt must
  equal the stored slice and its hash must match.
- Claim atomicity heuristic (coordinating conjunctions joining verb phrases, multiple
  finite verbs, more than 25 words) returned as a warning in the API response, never a
  block.
- `truth_evaluable` and `not_evaluable_reason` defaults by claim type per 01 §4.
- Read endpoints: `GET /api/v1/sources/:id`, `/sources/:id/locations`, `/claims?type=&q=`
  (full-text search; the `state` filter arrives in Stage 6), `/claims/:id?snapshot_seq=`,
  `/claims/:id/evidence`, `/evidence/:id`, `/contributors/:id`. Responses omit the
  `assessment` block until Stage 6.
- `pg_trgm` extension and a near-duplicate candidate query for claims (suggestions only).
- `Ledger::Replay` extended to all projections; a table-digest helper for equivalence tests.

Acceptance (07 Phase 2):

1. Source → location → claim → evidence → support link → contradiction link, all through
   `POST /contributions` (#1).
2. A claim with all relationships as of latest `seq` and as of an earlier `seq` (#2).
3. Invalidation hides a link at later seqs but not earlier ones (#3).
4. Replay: truncate projections, replay, every table digest identical (#4).
5. Projection models raise when written outside `Ledger::Apply` (#5).
6. Epistemic rows have `accepted_seq = null` until accepted; extraction-proposed claims
   cannot receive links until accepted by a different principal (#6).
7. Claim identity: near-identical claims coexist; duplicate `canonical_text` succeeds;
   `MERGE_CLAIMS` requires acceptance and is reversed by `INVALIDATE` (#7).

## Decision Log (2026-09-17)

- Tables per `02 §3.2–3.3` plus three additions: every projection row carries
  `contribution_id` (attribution and the target of ACCEPT / INVALIDATE), and two small
  windowed tables, `claim_merges` and `independence_group_assignments`, hold MERGE_CLAIMS
  and ASSIGN_INDEPENDENCE_GROUP as rows of their own. `claim_evaluability_settings` does
  the same for SET_TRUTH_EVALUABLE. A claim created by SUPERSEDE_CLAIM records
  `supersedes_claim_id`.
- **Merges, supersessions, and evaluability are derived from windows, never by
  rewriting the affected row.** "Claim X is merged at S" means an accepted, active
  `claim_merges` row exists at S; "link L is superseded at S" means an accepted, active
  link with `supersedes_link_id = L` exists at S. INVALIDATE-ing the merge or the
  revision therefore reverses it with no row restoration, which is what `02 §3.3`
  promises for merges. `claims.status`, `superseded_by_id`, `merged_into_id`,
  `truth_evaluable`, `not_evaluable_reason` and `evidence_items.independence_group_id`
  are the cached current view, recomputed by `Projections::Refresh` after every ACCEPT
  and INVALIDATE and rebuilt by replay. `*_at(seq)` methods answer history.
- Counted links (the scoring input from Stage 5) are `EvidenceClaimLink.effective_at(S)`:
  active, accepted, and not superseded at S. Evidence and location activity are checked
  by the scorer's input builder in Stage 6, as `03 §4` Step 1 lists them.
- **Source content is text in the CREATE_SOURCE payload.** `content_hash` is over the
  UTF-8 bytes and CHAR_RANGE offsets are Unicode code points. This keeps the log
  self-contained (a mirror of `GET /log` rebuilds every source) and makes replay
  trivial. `11 §8` names Active Storage; it is deferred to a binary-source import flow
  (P1), and the `content` column would then hold extracted text. Recorded for the owner.
- Acceptance per `02 §1.1a`, implemented as a system-signed ACCEPT appended in the same
  transaction: a human's own sources, locations, claims, evidence, links, edges,
  groups, and assignments; own-principal supersessions and merges. Never for
  SET_TRUTH_EVALUABLE. Agent contributions made outside a task (possible from Stage 2,
  no task packets yet) are proposals; Stage 8 adds the automatic acceptance of
  object-adding task results. ACCEPT by a human of a different principal, or by an
  agent whose delegation lists `"ACCEPT"` under `permissions.allowed_actions`; never by
  the same principal. INVALIDATE by the contribution's own principal (including a
  principal withdrawing its agent's work) or by the system.
- Proposed claims cannot receive links or edges (`CLAIM_NOT_ACCEPTED`), nor can merged,
  superseded, retired, or invalidated ones (`CLAIM_NOT_CURRENT`, `TARGET_INVALIDATED`).
- **Idempotency consequence (spec `02 §3.1`):** the key is the signer, task, and payload
  hash, so a signer resubmitting a byte-identical payload always gets the original back,
  even after it was invalidated or the claim it targets changed state. To make a second,
  distinct identical claim a contributor changes something (qualifiers, note) or a
  different contributor makes it. Whether `client_created_at` should enter the key is a
  question for the owner; the code follows the spec.
- Atomicity (`02 §4`) is `Claims::Atomicity`: warnings for length over 25 words, a
  conjunction joining clauses, a comma-separated series, and inference words. Returned
  with the POST response and on claim reads; never a block.
- Near-duplicate suggestions use `pg_trgm` similarity at 0.3 (`Claims::Duplicates`),
  exposed as `GET /claims?similar_to=<id>` rather than a new route.
- Reads (`06 §2`) render as of `?snapshot_seq=` (default head): claim with history-aware
  status, evaluability, edges, counted and pending counts; claim evidence grouped into
  counted, pending, and superseded; evidence with its location and source; sources with
  content; locations; contributors. Lists show accepted, live claims; proposals are
  reachable by id. `assessment` and `card` blocks arrive in Stages 6 and 9.
- `Ledger::TableDigest` hashes every projection table (rows ordered by id, attributes as
  JSON) for the replay-equivalence test and the later snapshot digest. Renamed from
  `Ledger::Digest` because that shadowed Ruby's `Digest` inside the namespace.
- Foreign keys exist among projection tables; none point at them from outside, so a
  single `TRUNCATE` of the whole set is valid.
- Constitutional Test (history and visibility touched): 1 yes, excerpt and content
  hashes bind evidence to bytes; 2 yes, contradicting links and edges coexist; 3 no,
  acceptance is by a different principal or the system after validation, both logged;
  4 no; 5 yes, `truth_evaluable` overrides are themselves contributions; 6 yes, replay
  digest test; 7 yes; 8 yes, every state answers at any seq; 9 n/a; 10 yes.
- Acceptance: 07 Phase 2 #1–#7 each have specs (`spec/requests/api/v1/graph_spec.rb`,
  `spec/models/projection_spec.rb`, `spec/services/graph/*`, `spec/services/ledger/replay_spec.rb`);
  `bundle exec rspec`, RuboCop, and Brakeman pass.
