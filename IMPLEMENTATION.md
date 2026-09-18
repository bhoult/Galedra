# IMPLEMENTATION.md

Staged implementation plan for the Galedra POC, plus the running decision log the spec
requires (`10-agent-handoff.md`, "Required Artifacts"). The plan is fixed; the decision
log grows as stages are executed.

Spec paths below are relative to `docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/`.
The stages follow the phase order in `07-poc-roadmap-and-acceptance.md` exactly, with the
larger phases split so each stage is a bounded unit of work that ends in a git tag.

## How a stage is executed

1. Re-read the spec sections listed for the stage before writing code.
2. Implement the deliverables. Do not pull work forward from a later stage.
3. Every acceptance item for the stage has an automated test. All tests pass locally and in CI.
4. Append this stage's entries to the Decision Log at the bottom of this file: versions,
   choices made, assumptions, any deviation from the spec with its reason. For a stage that
   touches scoring, identity, reputation, moderation, visibility, or history, also record
   the answers to the ten Constitutional Test questions (`12-constitution.md`).
5. Commit on `master` (one or more commits), then tag and push:

   ```bash
   git tag -a stage-NN-slug -m "Stage NN: <title>"
   git push origin master --tags
   ```

   Tag names are zero-padded so they sort: `stage-00-skeleton` … `stage-11-demo`.
   Stage 11 additionally gets `v0.1.0`, marking the P0 Definition of Done.
6. A stage is not done until its tag exists. The next stage does not start until asked.

**Ruby and Rails: always the latest stable release.** At planning time that is Ruby 4.0.7
and Rails 8.1.3.1 (checked against ruby-lang.org and rubygems.org on 2026-09-17). Stage 0
re-checks both, installs whatever is latest then, and pins them. If Rails does not yet
support the newest Ruby line, use the newest Ruby the Rails release supports and record
that in the Decision Log.

Environment on the development machine at planning time: Ruby 3.4.5 via asdf (the asdf
ruby plugin is stale and lists nothing newer than 3.4.5), Bundler 2.6.9, Docker 29.1.3
without the compose plugin, no local PostgreSQL, Node 22, Python 3.14. Rails is not
installed. Stage 0 records the exact versions it ends up using.

---

## Stage 0 — Skeleton

**Tag:** `stage-00-skeleton` · **Spec:** 07 Phase 0, 11 §2, §5, §10, 10 "Required Artifacts"

Goal: a Rails 8 application that boots under Docker Compose, has CI, and serves the
constitution hash. No domain logic.

Deliverables:

- Toolchain: `asdf plugin update ruby`, install the latest stable Ruby (4.0.7 at planning
  time), `gem install rails` at the latest stable (8.1.3.1 at planning time). Pin Ruby in
  `.tool-versions` and `.ruby-version`; pin Rails in the Gemfile to the exact installed
  patch line (e.g. `~> 8.1.3`).
- Rails app generated at the repo root (`--database=postgresql`, `--skip-jbuilder`, no JS
  bundler; importmap + Hotwire only). The Docker image uses the same Ruby version.
- `docker-compose.yml` with exactly two services, `app` and `db` (PostgreSQL 16). The app
  container runs web + `bin/jobs` via `Procfile.dev` or a second process in the same
  service. Installs the missing compose plugin; the Decision Log records how.
- Solid Queue, Solid Cache, Active Storage (local disk) configured against the same
  Postgres database.
- Rails 8 authentication generator run (`users`, `sessions`), with a minimal Hotwire
  layout and a home page that renders.
- RSpec (`rspec-rails`), FactoryBot, and a system-test driver. Record the choice.
- GitHub Actions CI: lint (RuboCop, rails-omakase config), `bundle exec rspec` against a
  Postgres service, `bin/brakeman`.
- `.env.example` documenting every environment variable, including
  `LEDGER_SYSTEM_PRIVATE_KEY` and `LEDGER_SYSTEM_PUBLIC_KEY` placeholders (used from
  Stage 1).
- `CONSTITUTION.md` at the repo root: a byte-identical copy of `12-constitution.md`, with
  a test asserting the two files match.
- `Governance::Constitution` service returning `{version, hash}` where the hash is
  `sha256:` + hex over the file bytes.
- `GET /api/v1/meta` returning `constitution_version` and `constitution_hash` (other
  fields are added in later stages).
- This file's Decision Log started: Ruby, Rails, Postgres, gem versions; RSpec choice;
  UUIDv7 approach chosen (Postgres 16 has no native `uuidv7()`; pick a SQL function or a
  gem and document).

Acceptance:

1. `docker compose up` serves the home page.
2. `bundle exec rspec` passes locally and in CI.
3. `/api/v1/meta` returns a constitution hash that equals `sha256sum CONSTITUTION.md`.

---

## Stage 1 — Canonicalization, hashing, and keys

**Tag:** `stage-01-crypto` · **Spec:** 02 §1.2a, §3.1 (`contributors`), §6, 05 §2–3, 10 "Implementation Notes", 11 §10

Goal: the cryptographic primitives and the contributor identity table, tested against
published vectors, with no log yet.

Deliverables:

- `Crypto::CanonicalJson` (RFC 8785 via `json-canonicalization` or equivalent; document
  the gem), `Crypto::Hashing` (`sha256:` prefix helpers for canonical JSON and raw bytes),
  `Crypto::Ed25519` (sign, verify, `key_id = "ed25519:" + hex(sha256(raw_public_key))`),
  `Crypto::Custody` (server-custodied key generation and per-request unlock using Active
  Record Encryption).
- `spec/fixtures/canonical_json_vectors.json`: the RFC 8785 examples plus project vectors
  (an envelope, a packet, a trace) with expected canonical bytes and hashes. The spec names
  `test/fixtures/`; the RSpec path is recorded as a deviation.
- `contributors` table and model exactly per 02 §3.1: `key_id`, `public_key`, `kind`
  (HUMAN | AGENT | SYSTEM), `display_name`, `identity_tier`, `encrypted_private_key`,
  `user_id`, `created_seq`, `revoked_seq`, `metadata`. UUIDv7 primary keys from here on.
- System key loaded from environment/credentials (never the database); its public key
  added to `/api/v1/meta` as `system_key_id` and `system_public_key`.
- `bin/rails ledger:keygen` to generate an Ed25519 keypair for local development.
- Signing with a server-custodied key requires an authenticated session. The
  `custody: SELF | SERVER | SYSTEM` column arrives with the log in Stage 2.

Acceptance:

1. Canonicalization matches every vector in the fixture (07 Phase 1 #1).
2. A one-byte change to any signed structure fails verification (07 Phase 1 #2).
3. `key_id` derivation matches an independently computed value in the spec.
4. The system key is never persisted; a test asserts no `contributors` row for the system
   key holds an `encrypted_private_key`.

---

## Stage 2 — The contribution log

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

---

## Stage 3 — Evidence graph projections

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

---

## Stage 4 — Quarantine, takedown, and the moderation log

**Tag:** `stage-04-moderation` · **Spec:** 02 §5, 05 §13, 06 §2 (`/moderation`), 12 Art. XII–XIII, CONSTITUTION-AMENDMENTS P-1, P-2

Goal: visible moderation. Nothing disappears without a public trace, and the chain still
verifies after a legally compelled redaction.

Deliverables:

- Moderator authorization: a `moderator` flag or role on `users`/`contributors`, checked
  for the control actions `QUARANTINE`, `RELEASE_QUARANTINE`, `TAKEDOWN`, and
  `INVALIDATE` outside the audit path.
- `QUARANTINE` / `RELEASE_QUARANTINE` appliers for sources and claims: closed reason list
  (`PRIVATE_INDIVIDUAL`, `PERSONAL_DATA`, `UNLAWFUL_CONTENT`, `UNLICENSED_MATERIAL`,
  `SPAM`), `status: QUARANTINED` on claims, text withheld from public reads, public stub
  at the same URL with moderator key, date, reason, appeal path.
- `TAKEDOWN` applier with a redaction manifest: physically deletes `payload`, `envelope`,
  and blob bytes of the target, sets `redacted_by_seq`, keeps `payload_hash`,
  `envelope_hash`, `entry_hash`, `server_signature`. Applies the manifest to projection
  rows (fields nulled).
- `ledger:verify` reports `CHAIN_VERIFIED` or `CHAIN_VERIFIED_WITH_REDACTIONS` with the
  redacted seqs; `ledger:replay` applies redacted entries from their manifests.
- `Governance::ModerationLog` and `GET /api/v1/moderation`: every quarantine, release,
  takedown, suspension, and revocation with moderator key, reason category, and appeal
  status.
- Private-individual affirmation: `CREATE_CLAIM` payload carries
  `affirms_not_private_individual: true`; missing or false is a validation error.

Acceptance:

1. After a `TAKEDOWN`, `ledger:verify` reports `CHAIN_VERIFIED_WITH_REDACTIONS` naming the
   seq, and replay reproduces the redacted projection (07 Phase 2 #8).
2. A quarantined claim URL returns a public stub, not a 404, and the claim's text is
   absent from every public read (07 Phase 6 #3, API part).
3. The moderation log lists each action with its moderator key and reason category.
4. A quarantine with a reason outside the closed list is rejected.
5. Constitutional Test answers recorded in the Decision Log for this stage.

---

## Stage 5 — Deterministic scoring

**Tag:** `stage-05-scoring` · **Spec:** 03 (all), 05 §14, 08 §8, examples/watchers §7, reference/reference_scorer.py, both scoring configs

Goal: `Scoring::Calculate` implements 03 §4 exactly for both released models and
reproduces every golden value as a pure function of serialized inputs. No cache, no
snapshots, no endpoints yet.

Deliverables:

- `config/scoring/ledger-default-0.1.0.json` and `config/scoring/ledger-strict-0.1.0.json`
  as byte-identical copies of the spec configs, with a test asserting equality.
- `scoring_models` table and `Scoring::Registry`: load configs, validate exhaustively (a
  missing enum key is a release error), compute `config_hash` and `code_hash` over
  `app/services/scoring/**/*.rb`, reject a model whose `review_checklist` names a check
  no P0 task type can satisfy.
- `RELEASE_SCORING_MODEL` control action and applier; `ledger:release_models` task that
  releases both P0 models signed by the system key.
- `Scoring::Calculate.call(input) -> trace` where `input` is the serializable structure in
  11 §12. Steps 0–5 of 03 §4 with `BigDecimal`, half-even rounding at 6/4/2 places,
  strongest-only per `(group_key, sign)` with the specified tie-break, directional states
  requiring matching groups, `INSUFFICIENT_EVIDENCE` and `NOT_APPLICABLE` with null
  probability and `not_applicable_reason`.
- `Scoring::Checklist` (03 §8), `Scoring::Stability` (03 §9), `Scoring::Trace` (03 §10
  shape, canonical JSON, `trace_hash`, `rounding_boundary` flag), `Scoring::Compare`
  (diff of two traces: differing effective weights, responsible config keys, state change).
- Golden fixtures: every row of 08 §8 and Watchers §7, for both models, expressed as
  scorer inputs (mirroring the Python reference's case tables) with expected outputs.
- Task priority heuristic `Tasks::Priority` (03 §14) as a pure function, tested.

Acceptance (07 Phase 3, the parts that do not need snapshots):

1. Every golden row reproduces exactly for both models (#1, pure-scorer form).
2. A config with a missing enum key is rejected at release (#3).
3. Changing scorer code without bumping the version fails the `code_hash` test (#4).
4. `NOT_APPLICABLE` and `INSUFFICIENT_EVIDENCE` never carry a probability (#5).
5. Strongest-only suppression is per group and direction and visible in the trace (#6).
6. Releasing `ledger-strict` changes no `ledger-default` trace (#7).
7. Every `NOT_APPLICABLE` result carries a `not_applicable_reason` (#8).
8. A claim with only supporting evidence never receives a contradicted state (#9).
9. A model declaring an unsatisfiable check is rejected (#10).
10. `rounding_boundary` is set when a value lies within the guard (#11, unit form).
11. Constitutional Test answers recorded.

---

## Stage 6 — Snapshots, score cache, and score endpoints

**Tag:** `stage-06-snapshots` · **Spec:** 02 §3.5, 03 §13, 06 §2 (score, trace, compare, snapshots, scoring-models, admin), 11 §7, §9

Goal: scores computed from the live log at any `seq`, cached, recomputed incrementally,
and reproducible after a cache wipe and after replay.

Deliverables:

- `Scoring::BuildInput.call(claim_id:, snapshot_seq:, model:)`: selects counted links at
  `seq` per 03 §4 Step 1 (accepted, active, evidence and location active, not quarantined),
  gathers task-based checklist facts, and produces the 11 §12 input.
- `graph_snapshots` table, `Snapshots::Create` (pin `seq` + `entry_hash` + label),
  `Snapshots::Digest` (`claim_score_digest` = sha256 over sorted `(claim_id, trace_hash)`
  under the default model).
- `claim_scores` cache table (unique on claim, seq, model), deletable at any time.
- `RecomputeAffectedScoresJob`: idempotent, keyed by `(claim_id, seq)`, run only for
  claims whose counted links, evidence, groups, or acceptance changed at that `seq`.
  Enqueued by `Ledger::Append` after apply. `CreateSnapshotJob` for admin pins.
- Endpoints: `GET /api/v1/claims/:id/score`, `/trace`, `/compare?models=a,b`,
  `/snapshots`, `/snapshots/:seq`, `/scoring-models`, `POST /api/v1/admin/snapshots`,
  `POST /api/v1/admin/recompute` (moderator only). Every score-bearing response carries
  `snapshot_seq`, `model`, `assessment_state`. Claim read responses gain the `assessment`
  block from 06 §3 (the `card` block arrives in Stage 9). `GET /claims?state=` filter.
- `/api/v1/meta` adds the model list.

Acceptance:

1. Same `seq` + same model yields a byte-identical canonical trace, including after a
   full cache wipe and after `ledger:replay` (07 Phase 3 #2).
2. Golden rows reproduce end to end when the 08 and Watchers graphs are built through the
   real write path in a spec (not yet the seed script; a spec helper is enough).
3. `claim_score_digest` for a pinned snapshot is unchanged after dropping projections and
   caches and replaying (07 scenario J).
4. `/compare` for a CAUSAL claim names `scored_types` as the responsible config key
   (07 scenario H, API part).
5. Incremental recompute touches only affected claims (assert on job work, not timing).

---

## Stage 7 — Audits and reputation

**Tag:** `stage-07-audits` · **Spec:** 02 §3.4 (`audits`, `audit_schedules`, `reputation_events`), 05 §4 (compromise window), §6–10, 06 §2 (`/contributors/:id/reputation`)

Goal: audits as contributions, deterministic and anchored sampling, appeals via
re-audit, and reputation reproducible from events at any `seq`. Reputation is not a
scoring input.

Deliverables:

- Tables: `audits`, `audit_schedules`, `reputation_events` per 02 §3.4.
- `AUDIT` control action and `Audits::ApplyResult`: effects table from 05 §9
  (`CONFIRMED` clears `provisional`; `SUBSTANTIVE_ERROR` / `FABRICATION` append a system
  `INVALIDATE`; `UNRESOLVED` marks `CHALLENGED` and schedules a second audit;
  `MINOR_ERROR` leaves the target counted). `RE_AUDIT` invalidates the first audit's
  reputation event and restores the target by a new `ACCEPT` when it disagrees.
- `Audits::Eligibility` (05 §8): different principal; `n ≥ 5` and `mean ≥ 0.8` in `AUDIT`
  for the domain, or a human at `ESTABLISHED` or above. Seeded moderators bootstrap.
- `Audits::Sample` (05 §9): probability formula with inputs evaluated at the target's own
  `seq`; decision `sha256(entry_hash + policy_version) < p × 2^256`; inputs, probability,
  and decision stored in `audit_schedules`. `ScheduleAuditJob` runs after each append.
  `outcome_is_unusual` per the P0 definition.
- High-impact policy thresholds (05 §10) in config; `provisional` clears only when the
  threshold is met.
- `Reputation::Calculate.call(contributor_id:, task_type:, domain:, snapshot_seq:)`:
  Beta(1,1) prior, deltas from 05 §7, principal roll-up, "limited history" when `n < 3`.
  Contributions made outside a task use `task_type: MANUAL`, `domain: general`.
- Compromise window: `REVOKE_*` with `compromised_since` marks later contributions
  `CHALLENGED` and queues audits.
- Domains: small closed admin-editable list (`general`, `ancient_near_east`, …) in config.
- Endpoint `GET /api/v1/contributors/:id/reputation?snapshot_seq=`; contribution reads
  include audits and status history.
- `Scoring::BuildInput` sets `provisional` from audit state.

Acceptance (07 Phase 4):

1. `SUBSTANTIVE_ERROR` invalidates the target, lowers reputation, triggers recompute;
   history remains visible (#1).
2. A disagreeing re-audit restores the target and invalidates the first audit's event (#2).
3. Reputation at any `seq` reproduces from events (#3).
4. The same principal cannot audit its own agents' work (#4).
5. Given an entry hash and policy version, anyone can recompute the sampling decision (#5).
6. Later audits, edges, or reputation events do not change an existing `audit_schedules`
   row (#6).
7. Constitutional Test answers recorded.

---

## Stage 8 — Tasks, leases, packets, and the example agent

**Tag:** `stage-08-agents` · **Spec:** 04 (all), 02 §3.4 (`tasks`, `task_assignments`), 06 §2 tasks endpoints, 10 "Required Artifacts" (schemas, examples/agent)

Goal: an external agent can lease a signed packet, return a signed result, and have it
validated server-side, logged, accepted, scheduled for audit, and scored.

Deliverables:

- Tables `tasks` and `task_assignments` per 02 §3.4, unique per `(task, contributor)` and
  per `(task, principal)`.
- `schemas/eir-task-v1.json` and `schemas/eir-result-v1.json`; validation with
  `json_schemer`; schema URLs in `/api/v1/meta`.
- `Tasks::BuildContext` (04 §5): deterministic, no LLM, per-type include/exclude table,
  token budget, excerpt cap, contributor notes never included. `Tasks::Lease` (04 §7):
  2-hour default, per-type configurable, priority ordering, delegation filtering,
  per-delegate daily limit, `ExpireLeasesJob`.
- Server-signed packets; `task_packet_hash` over the packet without `server_signature`.
- `Contributions::ValidateTaskResult`: the nine-step pipeline of 04 §6 returning 422 with
  the error list and creating no contribution on failure; ops with `ref` handles; max 20
  ops applied atomically; automated acceptance rules per task type (02 §1.1a);
  `EVIDENCE_VERIFICATION` evidence must reference the packet's location; new external
  sources stored metadata-only with `retrieval_pending`; no server-side URL fetching.
- Blind multi-assignment (04 §3.1): results hidden until all slots submit or expire.
- Task creation: `Tasks::Create` for the five P0 types, callable from the UI flow (Stage
  10) and from seeds; "create verification tasks" for a source's claims.
- Endpoints: `POST /api/v1/tasks/next?types=&domains=`, `GET /api/v1/tasks/:id`,
  `POST /api/v1/tasks/:id/release`.
- `examples/agent/`: single-file Ruby client with no Rails dependency (`lease_next`,
  `verify_packet!`, `submit`), `fixtures.json` mapping seeded tasks to deterministic
  answers, and a README. Canonicalization vector included so third-party clients can
  confirm identical hashing.

Acceptance (07 Phase 5):

1. The example client leases, verifies the packet signature, runs the fixture verifier,
   signs, submits, and a `TASK_RESULT` plus `ACCEPT` appear in the log (#1).
2. Expired lease, wrong packet hash, and disallowed op each return 422 and create nothing (#2).
3. Two agents under one principal cannot both hold slots on one task (#3).
4. Packets never contain contributor notes: seed a note with an injection string and
   assert absence (#4).
5. Same task inputs produce identical packet bytes excluding timestamps and signature (#5).
6. A `QUALIFIER_CHECK` result superseding another principal's links stays uncounted until
   a different principal accepts it (#6).
7. `opposing_search_done` and `qualifiers_reviewed` checklist items now flip from real
   accepted task results.
8. Constitutional Test answers recorded.

---

## Stage 9 — Why, summaries, answer cards, and weaknesses

**Tag:** `stage-09-answers` · **Spec:** 01 §6, 04 §10, 06 §2 (`/why`, `/summary`, `/weaknesses`), 06 §3 `card`, 06 §4 rule 5a, 06 §5 Weaknesses and per-source card

Goal: the deterministic answer layer over the graph, API-first, so Stage 10 renders and
Stage 11 prints it.

Deliverables:

- `Cards::MainIssue` (06 §4 rule 5a, first match wins), `Cards::ClaimCard`,
  `Cards::SourceCard` (per-source roll-up sentence, 08 §9). The `card` block joins claim
  responses.
- `GET /api/v1/claims/:id/why`: strongest counted support, strongest counted
  contradiction, suppressed dependents, review-coverage gaps, and the single hypothetical
  link addition that would move the score most under the current model (computed by
  re-running the scorer).
- `summaries` cache table keyed by `input_hash`; `Summaries::StubGenerator` (`stub-v0.1`,
  templates filled from the trace), `Summaries::Validator` (every sentence has at least
  one cite; every cite in the input set; otherwise reject and fall back), `SHORT` and
  `STANDARD` types, `GenerateSummaryJob`. `Llm::Adapter` interface with `Llm::StubAdapter`
  as the only implementation.
- `Weaknesses::Report` and `GET /api/v1/weaknesses?kind=&limit=` with the seven
  deterministic lists from 06 §5, each entry carrying its `/why` "what would most change
  this" item.
- Stub claim extractor for the Analyze-text flow: deterministic sentence split plus type
  guess, behind `Llm::Adapter`, producing `CLAIM_EXTRACTION` proposals.

Acceptance (07 Phase 6, API parts):

1. Summary sentences all cite IDs from the input set; a generator returning an unknown ID
   is rejected and the stub is served (#1).
2. Summary cache key changes when input changes; stale summaries are not served (#2).
3. The card for the 08 graph at S5 matches 08 §9 in state, main issue, and cites.
4. The Weaknesses report lists a claim whose state differs between the two models
   (07 scenario H).

---

## Stage 10 — Hotwire UI

**Tag:** `stage-10-ui` · **Spec:** 06 §4 (all display rules), §5 (all pages), §6 rule, §7 search, 02 §4 atomicity warning, 01 §7 checkbox

Goal: every P0 page, functional not polished, obeying the normative display rules, with
system tests. No JS framework; Turbo and Stimulus only.

Deliverables:

- Pages: Home; Analyze text (paste, stub proposals, edit/split/type, atomicity warnings
  inline, private-individual checkbox, submit, "create verification tasks"); Claim page
  with sections in the 06 §5 order, answer card by default, "Why?" and "Show calculation"
  disclosures, model selector, snapshot picker, collapsible trace JSON; Evidence page;
  Contribution page with signature, chain, and custody badges; Contributor page (per task
  type × domain, no aggregate prestige); Task board with "Hand this to my agent" lease
  command; Weaknesses page; Moderation log; Snapshot view; Source page with per-claim
  cards and the roll-up; Log browser.
- Display rules enforced in view helpers with unit tests: number only behind Show
  calculation and always with model and snapshot; no number for `INSUFFICIENT_EVIDENCE`
  or `NOT_APPLICABLE`; "Review checks: N of M"; `provisional` and `contested` labels;
  model-dependent notice; raw and independent counts; reason text for `NOT_APPLICABLE`;
  default model labeled as default; neutral wording and colors, no true/false coding or
  badges; reputation never on claim headlines.
- Server-custodied signing for browser users: every UI write builds an envelope, signs
  with the user's unlocked key, and goes through `POST /api/v1/contributions` internally.
  "Server-held key" badge on the contributor page.
- Search: full-text on claim text and evidence statements with filters (type, state,
  source, contributor, status).

Acceptance (07 Phase 6 #3, system tests):

1. Default claim view is the answer card and shows no probability until Show calculation
   is opened.
2. Review coverage renders as "N of M checks".
3. No number for `INSUFFICIENT_EVIDENCE`.
4. Provisional label appears for unaudited links.
5. The model selector switches traces.
6. A quarantined claim URL renders a public stub.
7. Pasting the compound sentence from 02 §4 triggers the atomicity warning and the stub
   extractor proposes the split.
8. A speech-style source view shows state counts only, never a speaker score (06 §6).

---

## Stage 11 — Seeded demos and P0 Definition of Done

**Tags:** `stage-11-demo` and `v0.1.0` · **Spec:** 07 Phase 7, 08 (all), examples/watchers (all), 10 "Success Standard", SPEC README "Definition of Done"

Goal: `bin/demo` builds the public demo through the real write path, prints every golden
value with PASS/FAIL, prints the answer cards, checks replay, and exits non-zero on any
mismatch. The twelve Definition-of-Done items are demonstrated.

Deliverables:

- `db/seeds/demo.rb` executing the 18-step script of 08 §7 exactly, including task
  leasing by the fixture-driven example agent, the poisoned verification, sampling,
  audit, independence check, qualifier check with supersessions, and checkpoints S1–S5
  pinned as labeled snapshots.
- `db/seeds/examples/watchers.rb` executing the 19-step script of Watchers §6.
- `bin/demo [--example watchers] [--reset]`: runs on a clean database, prints golden
  tables for both models, the `/compare` diff (C6 public, C3 Watchers), the answer cards
  (08 §9), the reputation table, snapshot digests, URLs, then truncates projections,
  replays, and compares S1–S5 digests. PASS/FAIL per row; non-zero exit on any FAIL.
- Assertion that no `MERGE_CLAIMS` exists between C2 and C3 while the duplicate-suggestion
  list contains the pair (08 §7 step 16).
- CI job that runs both demos against a fresh Postgres.
- Root `README.md` "Status" section updated from "implementation not started" to describe
  how to run the demo; the CLAUDE.md "Status" line updated likewise.
- Decision Log closed out for P0: final versions, every deviation, and the acceptance
  scenario checklist A–J from 07 with the test that covers each.
- `EXPERIMENTS.md` created with the five First Experiments from 07 as empty sections to
  be filled after P0.

Acceptance:

1. `docker compose up -d && bin/demo` prints PASS for every golden row and for the replay
   check and exits 0 (10 "Success Standard").
2. `bin/demo --example watchers` does the same.
3. Each of the twelve Definition-of-Done items in the SPEC README maps to a demo step or a
   system test, listed in the Decision Log.
4. `git tag v0.1.0` created on the same commit as `stage-11-demo`.

---

## After P0

Not planned in stages. `07` Phase 8 (P1) work such as the real LLM adapter, questions and
hypotheses, dedup candidate edges, export mappings, embeddable cards, and personal
assessments is built only when asked, one feature per tag, after the First Experiments in
`EXPERIMENTS.md` have results.

---

## Decision Log

Append-only. One dated entry per stage, added when the stage is executed. Each entry
records: exact versions, choices and their alternatives, assumptions, deviations from the
spec with reasons, and Constitutional Test answers where the stage requires them.

### Planning (2026-09-17)

- Test framework: RSpec, matching the owner's other Rails projects (`07` Phase 0 leaves
  the choice open).
- Tag scheme: annotated tags `stage-NN-slug`, plus `v0.1.0` at Stage 11.
- Work happens on `master`; no long-lived branches for the POC.
- The compose plugin is missing on the development machine; Stage 0 installs
  `docker-compose-plugin` (or the standalone `docker compose` binary) and records which.
- Ruby and Rails: latest stable at each stage's start, per the owner's instruction on
  2026-09-17. Planning-time values: Ruby 4.0.7, Rails 8.1.3.1. The spec's "Rails 8.x" is
  satisfied by 8.1.

### Stage 0 — Skeleton (2026-09-17)

- Versions: Ruby 4.0.7 (asdf, YJIT off: no rustc on the build machine), Rails 8.1.3.1,
  Bundler 4.0.20, Node 24.21.0 (asdf, current LTS; 26.x is not LTS until October 2026),
  PostgreSQL 16 (`postgres:16` image), pg 1.6, Solid Queue 1.7.0, RSpec via rspec-rails.
  Rails pinned `~> 8.1.3, >= 8.1.3.1`.
- `rails new` was run with `--skip-bundle`, which also skipped the after-bundle installers.
  importmap, Turbo, Stimulus, Solid Cache, Solid Queue, and Solid Cable were installed
  afterwards with their own generators.
- Test framework: RSpec, FactoryBot, Capybara, selenium-webdriver. Minitest skipped at
  generation. A system-test driver is present but no system tests run before Stage 10.
- Single database. The Solid installers' `db/*_schema.rb` files were folded into one
  migration (`create_solid_tables`) and deleted, and the production multi-database
  `connects_to` wiring removed, so development, test, and production each use one
  PostgreSQL database as 11 §2 requires. Solid Queue runs inside Puma via the
  `solid_queue` Puma plugin (`SOLID_QUEUE_IN_PUMA=true`) rather than a second process,
  so the `app` service is one container and one process tree.
- Database connection settings come from `DB_HOST`, `DB_PORT`, `DB_USERNAME`,
  `DB_PASSWORD` (documented in `.env.example`, loaded by dotenv locally and by Compose).
  CI sets the same variables against a Postgres 16 service.
- Docker Compose plugin was missing and sudo is unavailable to the agent; Compose v5.5.1
  was installed as a user-level CLI plugin in `~/.docker/cli-plugins/`. `Dockerfile.dev`
  is the development image; the generated `Dockerfile` remains the production image.
- `CONSTITUTION.md` is a byte-identical copy of `12-constitution.md`, asserted by a spec.
  `Governance::Constitution` parses the version from the file's header table and hashes
  the raw bytes. `GET /api/v1/meta` returns `constitution_version` and
  `constitution_hash`. API controllers inherit `Api::V1::BaseController`
  (`ActionController::API`), outside the session-based `Authentication` concern that the
  Rails 8 generator adds to `ApplicationController`.
- Rails 8 authentication generator was run (`users`, `sessions`, password reset). The
  home page is public via `allow_unauthenticated_access`.
- UUIDv7 primary keys are deferred to Stage 1, where the first ledger table is created.
- Deviation: `07` Phase 0 names `IMPLEMENTATION.md` as a deliverable; it already existed
  as the plan. `10` names `test/fixtures/`; RSpec uses `spec/fixtures/` (Stage 1).
- CI workflow triggers on `master` (the repo's branch), not the generated `main`.
- Acceptance: `docker compose up` serves the home page on port 3000; `bundle exec rspec`
  passes; `/api/v1/meta` hash equals `sha256sum CONSTITUTION.md`.

### Stage 1 — Canonicalization, hashing, and keys (2026-09-17)

- Canonical JSON: `json-canonicalization` 1.0.0 (`to_json_c14n`). Verified against the
  RFC 8785 §3.2.3 examples, including UTF-16 code-unit key ordering (emoji before
  U+FB33). `Crypto::CanonicalJson.call` rejects floats (ledger policy);
  `Crypto::CanonicalJson.serialize` is the pure RFC path, used only by the RFC vectors.
- Ed25519: Ruby's OpenSSL bindings (openssl gem 4.0.2 over OpenSSL 3.5.5) with raw key
  import/export; no `ed25519` gem. Keys and signatures are unpadded base64url.
  Verified against RFC 8032 §7.1 test vectors 1 and 2; Ed25519 is deterministic so the
  published signatures reproduce exactly.
- Test vectors live in `spec/fixtures/canonical_json_vectors.json` (the spec names
  `test/fixtures/`; RSpec path recorded as a deviation). Expected values were generated
  by an independent Python script, `spec/fixtures/gen_canonical_json_vectors.py` (stdlib `json.dumps(sort_keys=True,
  separators=(",", ":"))` for the float-free project vectors, RFC transcriptions for the
  RFC vectors, `hashlib` for digests), so the Ruby code is checked against a second
  implementation as 04 §11 intends.
- **json gem pinned to 2.x (2.21.2).** Ruby 4.0.7 bundles json 3.0.2, whose
  `JSON.parse` takes keyword-only options; ActiveSupport 8.1.3.1 passes a positional
  hash, so every jsonb column read and JSON request body raised `ArgumentError`, and the
  schema dumper silently omitted the contributors table. Rails `8-1-stable` already
  carries the fix (`JSON.parse(json, **options)`); remove the pin at the next Rails
  patch release. This is the only deviation from "latest stable" and it keeps both Ruby
  4.0.7 and Rails 8.1.3.1 in place.
- UUIDv7 primary keys are assigned in Ruby (`SecureRandom.uuid_v7`, Ruby 3.3+) by an
  `ApplicationRecord` callback for any table whose `id` is a uuid column; the migration
  sets no database default so a v4 id can never be generated silently. The Rails 8
  authentication tables (`users`, `sessions`) keep bigint ids: they are not ledger
  tables. Generators are configured for uuid.
- `contributors` per 02 §3.1. `identity_tier` defaults to `PSEUDONYMOUS`; there is no
  `UNSIGNED`. Validations enforce `key_id == ed25519:sha256(public_key)` and that a
  `SYSTEM` contributor never carries `encrypted_private_key`.
- Custody: `Crypto::Custody.create_server_custodied(user:)` generates a key and stores
  the private half with Active Record Encryption on the contributor row;
  `Crypto::Custody.signer_for(user)` refuses a nil user. Direct row creation is a
  Stage 1 convenience; from Stage 2 contributors are created only by `REGISTER_KEY`
  through `Ledger::Apply`.
- Active Record Encryption keys come from `ACTIVE_RECORD_ENCRYPTION_*` environment
  variables (documented in `.env.example`, generated by `bin/rails db:encryption:init`)
  rather than credentials, so Docker and CI need no master key. The test environment
  hardcodes non-secret keys.
- System key: `Crypto::SystemKey` reads `LEDGER_SYSTEM_PRIVATE_KEY` and checks it
  against `LEDGER_SYSTEM_PUBLIC_KEY` when both are set. `bin/rails ledger:keygen`
  prints a pair. The test suite pins RFC 8032 test vector 1 as the system key.
  `/api/v1/meta` now returns `system_key_id` and `system_public_key`.
- Development `db:prepare` also prepares the test database (Rails behaviour), which is
  how a broken schema dump left the test database half built; noted so the symptom is
  recognised if it recurs.
- Constitutional Test (identity is touched): 1 more traceable (every key has a stable
  id and published vectors); 2 unchanged; 3 no new hidden authority (system key holder
  remains the open governance question); 4 no; 5 n/a; 6 yes, vectors reproduce across
  implementations; 7 yes, anyone can verify; 8 n/a until the log exists; 9 n/a; 10 yes.
- Acceptance: all four Stage 1 items have specs; `bundle exec rspec`, RuboCop, and
  Brakeman pass; the Compose stack publishes the system key at `/api/v1/meta`.
- The tag was moved once: the first tagged commit had a tampering spec that replaced a
  signature's first character with "A" and so passed vacuously when the signature already
  began with "A" (about one run in 64). Fixed, and the suite now runs in random order.

### Stage 2 — The contribution log (2026-09-17)

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

### Stage 3 — Evidence graph projections (2026-09-17)

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

### Stage 4 — Quarantine, takedown, and the moderation log (2026-09-17)

- **Moderators are designated outside the log**: key ids in `LEDGER_MODERATOR_KEY_IDS`,
  or a `users.moderator` flag whose server-custodied key then counts. `09 §15` leaves
  appointment open, and inventing an `APPOINT_MODERATOR` action would extend the closed
  list in `02 §3.6`. The current list is published by `/api/v1/meta` and `/api/v1/moderation`
  so the power is visible. The system key is never a moderator. Moderators may
  `QUARANTINE`, `RELEASE_QUARANTINE`, `TAKEDOWN`, `INVALIDATE` any epistemic contribution,
  and `REVOKE_KEY` (suspension) any non-system key.
- Quarantines are a windowed projection (`quarantines`: target, reason from the closed
  list of `05 §13`, `created_seq`, `released_seq`). `claims.status` shows `QUARANTINED`
  while one is live; `status_at(seq)` answers history. Withheld while live: the claim's
  text and qualifiers; a source's title, content, and metadata; its locations' excerpts
  and locators; its evidence items' statements; and the payload and envelope of the
  contributions that carry that text in `GET /log` and `GET /contributions/:id`
  (hashes stay, plus a `withheld` marker). Quarantined claims are also dropped from
  lists, search, and duplicate suggestions. The public stub at the same URL carries the
  quarantine seq and time, moderator key id, reason, appeal status, and appeal path.
  Old snapshots of a quarantined claim also show the stub: the point is not to serve
  the text, though the claim's existence and status history remain visible.
- **TAKEDOWN carries the redaction manifest in its signed payload**: for every projection
  row of the target, the fields removed and the retained (non-sensitive) values. The
  server validates that the manifest covers exactly the target's rows, removes only
  redactable fields (`Ledger::Redaction::REDACTABLE`), and matches the current row
  values; `GET /contributions/:id/redaction_manifest` produces the default manifest
  for the moderator to review and sign. On append the fields are nulled (jsonb NOT NULL
  columns get `{}`), `redacted_by_seq` is stamped, and the target's payload and envelope
  are deleted under the owner role (`Ledger::DatabaseRole.as_owner`), since the
  application role cannot update those columns. Hashes, entry hash, and server
  signature remain, so `ledger:verify` reports `CHAIN_VERIFIED_WITH_REDACTIONS` with
  the seqs, checks that every redacted entry points at a `TAKEDOWN` that names it, and
  breaks on bytes removed any other way. Replay rebuilds redacted rows from the
  manifest. Only epistemic contributions can be taken down; a control entry such as
  `REGISTER_KEY` carries key material the chain needs.
- Deployment note: in direct-role mode (`LEDGER_DB_APP_ROLE=false`) the connection
  cannot escalate, so takedowns must run through a connection with owner rights.
- The private-individual affirmation (`01 §7`) is `affirms_not_private_individual: true`
  on `CREATE_CLAIM` and `SUPERSEDE_CLAIM` payloads; missing or false is rejected.
- `Governance::ModerationLog` is a view over the log: every quarantine, release, and
  takedown, plus key and delegation revocations signed by a moderator (labelled
  `SUSPENSION`). Appeal status is `OPEN` or `RELEASED` for quarantines and `NONE` for
  takedowns; the `RE_AUDIT` appeal path arrives in Stage 7.
- Constitutional Test (moderation, visibility, history): 1 unchanged; 2 unchanged;
  3 moderation power exists but every use is a signed, logged, publicly listed
  contribution with a closed reason list, and the moderator list is published; 4 no;
  5 n/a; 6 yes, redacted logs still verify and replay; 7 yes, releases and later
  re-audits are the same contribution path; 8 yes, stubs and the moderation log keep
  the history of removals; 9 n/a; 10 the residual risk named in `13` (moderation power)
  stands, mitigated by visibility and appeal, not eliminated.
- Acceptance: the five Stage 4 items have specs in `spec/services/governance/`;
  `bundle exec rspec`, RuboCop, and Brakeman pass.

### Stage 5 — Deterministic scoring (2026-09-17)

- `Scoring::Calculate` implements `03 §4` Steps 0–5, `03 §8` (checklist), `03 §9`
  (stability), and `03 §10` (trace) as a pure function of the `11 §12` input and a model
  config. `BigDecimal` throughout; half-even rounding at 6 (weights), 4 (probability),
  2 (coverage); decimals serialized as fixed-place strings; `ln` and `exp` via
  `BigMath` at 40 digits, then rounded.
- **Golden fixture generated from the spec's reference scorer.**
  `spec/fixtures/gen_scoring_golden.py` imports `reference/reference_scorer.py` and emits
  every row of `08 §8` and Watchers `§7` for both models (20 cases, 40 expectations) as
  scorer inputs with expected outputs, so the Ruby scorer is checked against an
  independent implementation. Fixture link ids are zero-padded (`L03`) so string order
  equals the reference's integer order; `contested` and `provisional` expectations come
  from the golden tables' flags, with the unaudited links (`L10`, Watchers `L2`, `L5`)
  marked `audit_confirmed: false` at the checkpoints where the tables say `provisional`.
- Input shape: `claim {id, type, truth_evaluable, not_evaluable_reason}`, `snapshot_seq`,
  `links [{id, evidence_id, direction, relevance_strength, interpretive_steps,
  audit_confirmed, evidence {observation_type, independence_group_id, source_type,
  assessment}}]`, `task_checks [{check, by}]`. Stage 6 builds it from the graph;
  Stage 7 supplies `audit_confirmed`; Stage 8 supplies task checks. `provisional` is
  true when any counted link's contribution lacks a confirming audit.
- `independence_unreviewed` counts distinct counted evidence items without a group;
  the reference counts links, and the two agree on every golden row.
- `rounding_boundary` applies the absolute guard (1e-6) to the 4-place probability and
  its two variants only. At 6 places an absolute 1e-6 guard equals a whole unit and
  would flag every value; the 6-place prior log-odds is a per-type constant every
  implementation can pin. Recorded as an interpretation of `03 §10`.
- The trace carries `code_hash` alongside `config_hash` (03 §1: a probability is never
  shown without both), plus per-link authenticity, extraction, source type, and audit
  state. Golden tests compare output fields, not trace hashes, so a scorer refactor
  changes `code_hash` without invalidating the goldens.
- `Scoring::Registry` validates configs exhaustively (`03 §4` Step 2: a missing enum
  key is a release error), requires every declared review check to be satisfiable by a
  P0 task type (`03 §8`), hashes `app/services/scoring/**/*.rb` for `code_hash`, and
  exposes `verify_code_hash!` so a code change without a new version fails.
  `RELEASE_SCORING_MODEL` is signed only by the system key and rejects a stale
  `code_hash`, a wrong `config_hash`, an invalid config, or a duplicate version.
  `bin/rails ledger:release_models` releases every `config/scoring/*.json` not yet
  released. `scoring_models` carries `released_seq` instead of the spec's `created_at`
  so replay reproduces it.
- `Scoring::Compare` reports the config-key paths that differ, the links whose
  effective weights differ with the responsible keys, and any state change; an
  applicability change names `scored_types` (07 scenario H).
- `Tasks::Priority` implements `03 §14` as a pure function with `BigDecimal`.
- Constitutional Test (scoring): 1 unchanged; 2 yes, two models and `/compare`
  localize disagreement to config keys; 3 no, the scorer is open code with published
  hashes; 4 no, reputation is not an input; 5 yes, null probabilities and directional
  states requiring evidence; 6 yes, byte-identical traces and cross-implementation
  goldens; 7 yes; 8 yes, traces cite snapshot and model; 9 n/a; 10 yes.
- Acceptance: 07 Phase 3 #1 (pure-scorer form), #3–#11 have specs in
  `spec/services/scoring/` and `spec/services/tasks/`; `bundle exec rspec`, RuboCop,
  and Brakeman pass; the reference scorer still prints ALL PASS.

### Stage 6 — Snapshots, score cache, and score endpoints (2026-09-17)

- `Scoring::BuildInput` selects counted links per `03 §4` Step 1 as of the seq: accepted,
  active, not superseded, with an active evidence item, location, and source, and no
  quarantine active on the source at that seq. Evidence facts (independence group,
  evaluability) are read as of the seq through the Stage 3 windows. `audit_confirmed`
  comes from `Audits::Status` (Stage 7; nothing is confirmed yet, so every counted link
  is provisional) and task checks from `Tasks::Checks` (Stage 8; none yet).
- `claim_scores` is a pure cache keyed by (claim, seq, model), upserted, deleted on
  replay and by the admin recompute. A cache hit rebuilds the result from the stored
  trace, so it reproduces the same bytes as a recomputation; the end-to-end spec proves
  byte-identical canonical traces after a cache wipe and after replay.
- `RecomputeAffectedScoresJob(seq)` recomputes only the claims `Scoring::Affected` derives
  from the contribution at that seq (links, evidence, locations, sources, groups,
  assignments, merges, evaluability settings, and the targets of ACCEPT, INVALIDATE,
  QUARANTINE, RELEASE_QUARANTINE, TAKEDOWN, AUDIT), under every released model. It is
  enqueued with `ActiveRecord.after_all_transactions_commit` so it runs after the
  enclosing transaction, including the auto-ACCEPT appended inside it. Key-management
  and model-release actions enqueue nothing.
- `graph_snapshots` pins `(seq, entry_hash, label)`; it is operational, not a
  projection, and survives replay. `GET /snapshots/:seq` reads any seq without pinning;
  only the signed admin call pins. `claim_score_digest` hashes the sorted
  `(claim_id, trace_hash)` pairs of every claim that existed and was not quarantined at
  the seq, under the default model.
- **Admin endpoints are authenticated by a signed body** (`eir-admin-v1`: signer key,
  timestamp within five minutes, payload, Ed25519 signature over the canonical body)
  from a moderator key. Pins and recomputes are not log entries.
- Claim reads carry the `06 §3` `assessment` block for `?model=` (default model when
  omitted); `GET /claims?state=` filters on the assessment state under that model.
  Quarantined claims return their stub from every score endpoint.
- **End-to-end golden check.** `spec/support/demo_graphs.rb` builds both demo graphs
  through the write path without the task and audit steps: agent results are appended
  under a delegation and accepted by a different principal, and the poisoned link is
  invalidated by its principal. Every golden row reproduces for both models except
  `provisional` and `review_coverage`, which depend on audits (Stage 7) and task-derived
  checks (Stage 8); `DemoGraphs::DEFERRED_GOLDEN_FIELDS` lists them and each later stage
  removes its entry. States, probabilities, stability, group counts, unreviewed counts,
  contested flags, and reasons all match now, including the S1→S4→S5 collapse of C2.
- Constitutional Test (visibility, history): 1 unchanged; 2 yes, `/compare` is served;
  3 no, admin actions require a moderator signature and are visible in the snapshot
  list; 4 no; 5 yes; 6 yes, traces and digests reproduce after replay; 7 yes; 8 yes,
  any seq is scorable and pinned snapshots carry the chain hash; 9 n/a; 10 yes.
- Acceptance: Stage 6 items 1–5 have specs in `spec/services/scoring/end_to_end_spec.rb`,
  `spec/services/scoring/affected_spec.rb`, and `spec/requests/api/v1/scores_spec.rb`;
  `bundle exec rspec`, RuboCop, and Brakeman pass.

### Stage 7 — Audits and reputation (2026-09-17)

- Tables `audits`, `audit_schedules`, `reputation_events` per `02 §3.4`, all projections
  rebuilt by replay. `audit_schedules` gains `forced_by_seq` (compromise windows) and
  `rescheduled_by_seq` (UNRESOLVED results).
- **Sampling runs inside `Ledger::Apply`, not as a job.** `05 §9` makes the inputs a
  function of the log at the contribution's own seq, so `Audits::Sample.schedule!`
  computes `n`, `mean`, `downstream_count`, and `outcome_is_unusual` there, stores them,
  and decides with `sha256(entry_hash + policy_version) < p × 2^256`. Replay reproduces
  every schedule row byte for byte; the plan's `ScheduleAuditJob` is unnecessary.
  Reputation inputs are read at `seq - 1`, the state the contribution arrived into.
  `outcome_is_unusual` for direct links compares the link's direction with the claim's
  groups just before it, under the default model as of that seq
  (`Registry.default_model_at`), so a later model release cannot change past decisions.
- Policy values live in `config/audit_policy.yml` (base rate, factors, the `05 §10`
  high-impact bands, auditor thresholds, established tiers, the closed domain list).
- Eligibility (`05 §8`): a different principal from the target's, and either an
  ESTABLISHED+ human, a moderator (the seeded bootstrap), or a track record in `AUDIT`
  for the domain (`n ≥ 5`, `mean ≥ 0.8`). The system key never audits.
- Effects (`05 §9`): CONFIRMED counts toward clearing `provisional`, which requires the
  band's number of confirming audits from distinct principals (the ≥ 10 band also needs
  an accepted opposing search, Stage 8). SUBSTANTIVE_ERROR and FABRICATION invalidate
  through a system-signed INVALIDATE that names the audit. UNRESOLVED marks the target
  CHALLENGED and reschedules it. MINOR_ERROR leaves it counted and unconfirmed.
- **Challenged contributions do not count until confirmed** (`05 §4`, `05 §9`):
  `Audits::Status.challenged?` derives, as of any seq, whether a compromise window or a
  latest-UNRESOLVED audit covers a contribution with no later CONFIRMED audit, and
  `Scoring::BuildInput` drops such links. REVOKE_KEY with `compromised_since` also
  forces audit schedules on the affected contributions.
- **Re-audits and restoration** (`05 §9` appeals): a RE_AUDIT targets an audit; if it
  disagrees, the first audit and its reputation event are invalidated and, when that
  audit had invalidated its target, the system appends an ACCEPT with basis
  `RESTORED_AFTER_RE_AUDIT`. `Ledger::Restore` recreates the invalidated rows as new
  rows with ids derived from the restoring ACCEPT and `created_seq` at that seq, so
  history shows the gap exactly as the spec says. The re-audit records a reputation
  event for the first auditor under task type `AUDIT`.
- Reputation (`05 §7`): Beta(1,1) prior, the spec's deltas, computed from events active
  at a snapshot; events on a delegate carry `principal_contributor_id` and count for
  both. Contributions outside a task are bucketed `MANUAL × general` (`02 §3.4`); task
  buckets arrive in Stage 8. `GET /contributors/:id/reputation` lists buckets with mean,
  n, raw counts, and the limited-history flag, and states that reputation is not
  authority. Contribution reads now include audits, the stored schedule, and a status
  history derived from the log.
- The demo builders now perform the spec's audit steps, so `provisional` matches every
  golden row end to end; `review_coverage` remains the only deferred field (Stage 8).
  Reputation golden tables need task buckets and are checked in Stage 11.
- Constitutional Test (reputation, history): 1 yes, audits are attributed contributions;
  2 yes, disagreement between auditors is a visible re-audit; 3 no, sampling is
  recomputable by anyone and moderators only bootstrap eligibility; 4 no, reputation is
  not a scoring input and never gates evidence; 5 yes, UNRESOLVED and CHALLENGED are
  first-class; 6 yes, schedules and restorations replay; 7 yes, appeals use the same
  path; 8 yes, restoration creates new rows rather than rewriting; 9 n/a; 10 yes.
- Acceptance: 07 Phase 4 #1–#6 have specs in `spec/services/audits/audits_spec.rb`;
  `bundle exec rspec`, RuboCop, and Brakeman pass.

### Stage 8 — Tasks, leases, packets, and the example agent (2026-09-17)

- `tasks` and `task_assignments` per `02 §3.4` are operational tables, not projections:
  task creation is not an action in the closed list, so replay leaves them alone.
  Consequence for mirrors: `GET /log` alone does not carry task targets, so
  task-derived review checks need the task registry (`GET /tasks/:id` is public).
  Recorded for the owner as a gap in log self-containment.
- **One signed packet per task**, built by `Tasks::BuildContext` at creation and shared
  by every assignee, so blind multi-assignment (`04 §3.1`) means literally identical
  packets. `lease_expires_at` therefore lives on the assignment (returned beside the
  packet) rather than inside it, a deviation from the `04 §3` example that keeps one
  `task_packet_hash` per task. Packets are byte-identical apart from `task_id`,
  `issued_at`, and the signature; contributor notes never enter them; excerpts are
  labelled untrusted and capped at 2,000 characters. Qualifier packets carry up to five
  trigram-near claims as `candidate_claims` so an agent can propose a NARROWS edge
  without seeing the graph.
- Leasing (`04 §7`) and releasing are signed `eir-lease-v1` requests (same shape as
  admin requests). Selection: OPEN or partly leased tasks by priority, filtered by the
  delegation's task types and domains, never a task already held by the same
  contributor or principal (two unique indexes), per-delegate daily limits,
  per-type lease lengths from `Tasks::Types`. `ExpireLeasesJob` and every lease call
  expire stale leases. Task reads hide results until the task is closed: all slots
  submitted, or leases expired with none live; an unleased slot keeps it blind. The
  public log itself is not blind, which `04 §3.1` cannot fully achieve on a
  transparency log; recorded.
- `TASK_RESULT` arrives as `eir-result-v1` (`contributor_key_id` maps to the
  `signer_key_id` column), validated against `schemas/eir-result-v1.json` with
  json_schemer, then by the `04 §6` pipeline: task and lease, packet hash, delegation
  permits type and domain, outcome in the type's list, ops in `allowed_ops` and under
  `max_ops`, refs declared before use, and type-scope rules (verification evidence on
  the packet's location and linking the packet's claim; independence assignments only
  on the packet's counted evidence; qualifier links QUALIFY or CONTRADICT; supersessions
  only of the packet's counted links). **Per-op semantic checks run inside the append
  transaction after refs resolve**; a rejection rolls the whole append back, so
  nothing is logged and no seq is consumed. Rows get ids derived from the contribution
  and the op index.
- Agent sources inside a task are metadata-only (`retrieval_pending`, no content or
  content hash accepted), so the server never fetches an agent-supplied URL (`04 §6`
  step 9); CHAR_RANGE locations are refused on such sources until content is imported.
- Acceptance of results (`02 §1.1a`): verification, search, independence, and qualifier
  results that only add objects are accepted by the system; extraction results and any
  result that supersedes another principal's link or claim stay pending for a different
  principal, as one contribution. Per-claim acceptance of an extraction (04 §4.3 "each")
  would need row-level ACCEPT, which `02 §1.1a` does not define; acceptance is per result.
- `Tasks::Checks` now derives the three task-based review checks from accepted, not
  invalidated results (via `Contributions::Standing` over ACCEPT/INVALIDATE entries), and
  `Audits::Status` uses the opposing-search check for the highest-impact band. Audits of
  task results are bucketed by the task's type and domain.
- The example agent (`examples/agent/agent.rb`) is one file over Ruby's standard library
  with its own RFC 8785 subset canonicalizer (no floats, UTF-16 key order), key
  generation, registration, leasing, packet verification against `/meta`, fixture-driven
  behaviours, signing, and submission. The spec exercises it in-process through a Rack
  transport and checks its canonicalizer against the published vectors.
- The demo builders now run T0–T4 as leased tasks answered by result envelopes, and the
  end-to-end golden check compares every field: `DemoGraphs::DEFERRED_GOLDEN_FIELDS` is
  empty.
- Constitutional Test (agents as contributors): 1 yes, every result is signed, scoped,
  and attributed with software metadata; 2 unchanged; 3 no, packets are server-signed
  and validation is server-side; 4 no; 5 yes, NONE_FOUND and CANNOT_DETERMINE are valid
  outcomes; 6 yes, packets are deterministic; 7 yes; 8 yes; 9 n/a; 10 yes.
- Acceptance: 07 Phase 5 #1–#6 have specs in `spec/services/tasks/tasks_spec.rb`;
  `bundle exec rspec`, RuboCop, and Brakeman pass.

### Stage 9 — Why, summaries, answer cards, and weaknesses (2026-09-17)

- `Cards::ClaimCard` renders the `06 §3` card: state in neutral words
  (`Cards::Headline`, never true/false/debunked/confirmed), `independent_lineages` as
  support plus contradiction groups, review checks as "N of M", stability, the main
  issue, related claims with their own headlines, and the `06 §4` labels
  (provisional, contested, model-dependent, low-coverage-with-strong-state, and the
  plain-words reason for NOT_APPLICABLE). The number is only in the assessment block.
- `Cards::MainIssue` follows `06 §4` rule 5a in order: an overturned or UNRESOLVED audit
  on a counted link, unreviewed independence, a QUALIFY link (cites the qualifying
  evidence), contested, the first unmet review check, else none recorded.
- `Cards::Why` (`01 §6`) reads the trace for the strongest counted support and
  contradiction and the suppressed dependents, lists review gaps, and finds the single
  addition that would move the score most by re-running the scorer with one
  hypothetical independent DIRECT MEASUREMENT link in each direction. Ties go to the
  contradicting addition, so the answer favours self-critique.
- Summaries (`04 §10`): `Summaries::Input` is the deterministic input (claim, state,
  checklist, kept links with evidence statements, never notes, qualifiers, suppressed
  items, related claims, audits on counted links); its hash is the cache key and its
  cite set is the only thing a sentence may cite (evidence, group, claim, task, and
  audit ids, plus `coverage:<claim>`). `Summaries::Validator` rejects any sentence
  without a cite or with a cite outside the set, and `Summaries::Generate` then serves
  `stub-v0.1`. A cached summary is served only while its input hash still matches;
  otherwise it is regenerated in place (no mutable stale flag). SHORT is two sentences,
  STANDARD six.
- `Llm::Adapter` is the optional LLM boundary; `Llm::StubAdapter` is the only P0
  implementation, selected by `LEDGER_LLM_ADAPTER=stub`. A real adapter must pass the
  same validator, which the specs prove by injecting adapters that cite unknown ids or
  nothing.
- `Cards::SourceCard` (`06 §5`) lists one card per claim created by a CLAIM_EXTRACTION
  result on the source, with a one-sentence roll-up in the shape of `08 §9`.
- `Weaknesses::Report` (`06 §5`, Art. XXII) computes the seven lists at a seq under the
  default model, each entry carrying the most-moving addition; "high downstream" is
  three or more counted outgoing edges.
- `Claims::Extract` is the stub extractor for Analyze text: sentence split on
  terminal punctuation, semicolons, and colons before capitals; type guess from cues
  (should/ought → NORMATIVE, causes/boosts → CAUSAL, will → FORECAST, numbers →
  QUANTITATIVE, reports/says → TEXTUAL, else OBSERVATIONAL); and a separate TEXTUAL
  claim for each parenthetical "(Name, YYYY)" citation. On the demo memo it proposes
  the four claims of `08 §5` (with "boosts" left as written; the seed's fixture agent
  proposes the spec's wording).
- **Tie-break found by the summary check.** `03 §4` Step 3 breaks equal magnitudes by
  the lowest evidence id, then link id, which assumes time-ordered ids. Projection ids
  here are hash-derived (Stage 2), so on the S5 supersessions a different tied link won
  and the summary cited an article instead of the survey (scores were identical either
  way). The scorer input now carries each row's `created_seq` and the scorer compares
  it first, then ids, which is the order UUIDv7 ids would have given and what the
  reference scorer's integer handles encode. Golden fixtures (no `created_seq`) are
  unaffected.
- Constitutional Test (visibility): 1 yes, every sentence cites the graph; 2 yes, the
  weaknesses page and why bundle expose where disagreement and doubt live; 3 no; 4 no;
  5 yes, unknown states get words, not numbers; 6 yes, all of it is deterministic; 7
  yes; 8 yes, cards and summaries are as of a seq; 9 n/a; 10 yes.
- Acceptance: 07 Phase 6 #1 and #2 (API parts), scenario E and scenario H (weaknesses)
  have specs in `spec/services/cards/answers_spec.rb`; the S5 cards match `08 §9` in
  state, main issue, and cites; `bundle exec rspec`, RuboCop, and Brakeman pass.

### Stage 10 — Hotwire UI (2026-09-17)

- Every `06 §5` page exists, functional not polished, Turbo only, no Stimulus controllers
  needed: home, analyze text, claim, evidence, contribution, contributor, task board and
  task, weaknesses, moderation log, snapshot view (with a two-seq state comparison),
  source with per-claim cards, and the log browser. Web controllers reuse the API's
  services and presenters; the display rules live in `DisplayHelper` with unit tests.
- **The number and the trace are rendered only on request.** `06 §4` rule 1 puts the
  probability behind "Show calculation"; a closed `<details>` still ships the number in
  the HTML, and the rack_test driver reads it, so the calculation card and the trace are
  rendered only when `?calculation=1` is present. The default claim page contains no
  probability at all, which is stricter than the rule and testable without a browser.
  "Why?" stays a native `<details>` because it carries no number.
- Sign-up creates a user and registers a server-custodied key through the log
  (`Crypto::Custody.create_server_custodied`); every UI write goes through
  `Ui::Write`, which signs an ordinary envelope with the user's unlocked key and appends
  it with custody `SERVER`. Contributor and contribution pages show the server-held-key
  badge.
- Analyze text: the pasted text becomes a signed `CREATE_SOURCE` plus a full-range
  location; `Llm::Adapter.current.extract_claims` proposes claims with inline atomicity
  warnings; the user edits, splits, types, includes, and affirms each; each included
  proposal becomes the user's own `CREATE_CLAIM` carrying `source_id`, a new optional
  payload field stored as `claims.extracted_from_source_id` so the per-source card can
  list UI-extracted claims next to task-extracted ones. "Create verification tasks" makes
  an opposing search, a qualifier check, and a verification against the pasted text for
  each claim. The private-individual checkbox is unchecked by default; an unaffirmed
  claim is refused with the spec's error and nothing is logged.
- The source page shows descriptive counts by assessment state with the note that counts
  depend on extraction granularity and that there is never a score for the source or its
  author (`06 §6`); no ranking anywhere.
- Model selector and snapshot picker are plain GET forms; the default model is labelled
  "the default model, not the answer" and any other "an alternative model".
- System specs use Capybara's rack_test driver (`spec/support/system.rb`): no browser is
  installed on the build machine, and every interaction is a form or a link. Switching to
  `driven_by :selenium, using: :headless_chrome` needs no spec changes.
- Constitutional Test (visibility): 1 unchanged; 2 yes, alternative models and the
  weaknesses page are one click away; 3 no, the default model is labelled as such;
  4 no, contributor pages show audited reliability only, no followers or prestige;
  5 yes, unknown states show words and reasons, never numbers; 6 unchanged; 7 yes,
  anyone can browse the log; 8 yes, every page takes a snapshot seq; 9 yes, no personal
  views exist in P0; 10 yes, neutral wording and colours throughout.
- Acceptance: 07 Phase 6 #3 (all eight items) has system specs in `spec/system/`;
  `bundle exec rspec`, RuboCop, and Brakeman pass.

### Stage 11 — Seeded demos and P0 Definition of Done (2026-09-17)

- `lib/demo/` holds the seed scripts as plain Ruby (`Demo::PublicDemo`, 18 steps of
  `08 §7`; `Demo::Watchers`, the `examples/watchers §6` script), a helper that mirrors the
  spec support step for step, and `Demo::Report`, which prints every golden row for both
  models with PASS/FAIL, the `/compare` diff (C6 public, C3 Watchers), the compact
  answers of `08 §9`, the reputation tables, the claim-identity assertion, snapshot
  digests, `ledger:verify`, the replay check, and URLs, and exits non-zero on any FAIL.
  `bin/demo [--example watchers] [--reset]` runs it through `bin/rails runner`;
  `db/seeds.rb` seeds the public demo on a clean database.
- Tasks in the seeds are answered by the fixture-driven example agent running in-process
  through `Rack::MockRequest`, so the demo exercises the real lease, packet verification,
  and result submission path over HTTP semantics. Verification packets now list the
  existing evidence on the location, and a `confirm_existing` behaviour links it, so the
  agents produce the spec's exact links (L10 on E2, Watchers L2 and L5 on E1).
- The golden tables read `spec/fixtures/scoring_golden.json` (generated from the
  reference scorer); the reputation tables are transcribed from `08 §8` and Watchers
  `§7` into `Demo::Report`. All match: 11 public and 9 Watchers rows under both models,
  plus 6 and 5 reputation buckets.
- `bin/demo` refuses a log that already holds contributions unless `--reset` truncates
  every table under the owner role first (development only); `01 §7`'s "runs on a clean
  database" is enforced rather than assumed.
- CI gains a `demo` job that prepares a fresh Postgres and runs both demos with
  `--reset` under the test environment, using RFC 8032 test vector 1 as the system key.
- Two bugs found by the demos: the example agent's canonicalizer turned `false` into
  `null` (fixed, regression assertion added), and the summary input ignored audits on
  links that were later invalidated (fixed in Stage 9).
- The in-process agent sends `Host: localhost`; `Rack::MockRequest` defaults to
  `example.org`, which development host authorization rejects with 403. The reset uses
  `truncate_tables` rather than a hand-built statement so Brakeman stays at zero.
- `README.md` "Status" and `CLAUDE.md` now say P0 is complete and how to run the demo;
  `EXPERIMENTS.md` holds the five First Experiments as empty sections.

#### P0 Definition of Done (SPEC README) → where it is demonstrated

1. Import a source and mark an exact location — `bin/demo` steps 2, 4; UI Analyze text
   (`spec/system/analyze_text_spec.rb`).
2. Create atomic claims and attach evidence with support/contradict/qualify links — demo
   steps 4–6, 14; `spec/requests/api/v1/graph_spec.rb`.
3. Every write is a signed contribution in the hash-chained log — every step; `spec/services/ledger/*`.
4. Paste an AI paragraph, see claims extracted, get a cited answer card per claim with score,
   trace, and review checks one click away — Analyze text system spec; demo answers
   (`08 §9`) and the source page.
5. Request a task packet, run the example agent, submit a signed result — demo T0–T4;
   `spec/services/tasks/tasks_spec.rb` (#1 runs the standalone client).
6. Audit a prior contribution, see it invalidated and the score recomputed — demo steps
   10–11 (S2 → S3); `spec/services/audits/audits_spec.rb`.
7. Switch between the two scoring models and see where and why they differ — demo
   `/compare`; model selector system spec; `spec/services/scoring/compare_spec.rb`.
8. Open the Weaknesses page and the public moderation log — system specs;
   `spec/services/cards/answers_spec.rb`, `spec/services/governance/*`.
9. See task/domain reputation change and reproduce it from audit history — demo
   reputation tables; `spec/services/audits/audits_spec.rb` (#3).
10. View a stubbed summary whose every sentence cites graph ids — demo answers;
    `spec/services/cards/answers_spec.rb`.
11. Pick an old snapshot seq and reproduce its scores byte for byte — demo digests;
    `spec/services/scoring/end_to_end_spec.rb`.
12. Drop every projection table, replay the log, and get the same snapshot hashes and
    scores — demo replay check; `spec/services/ledger/replay_spec.rb`,
    `spec/services/scoring/end_to_end_spec.rb`, `spec/services/governance/takedown_spec.rb`.

#### Acceptance scenarios A–J (07) → covering test

A quote verification: `spec/services/tasks/tasks_spec.rb` #1 and `audits_spec.rb` #2 ·
B poisoned contribution: demo S2 → S3, `end_to_end_spec.rb`, `audits_spec.rb` #1 ·
C dependent evidence: `end_to_end_spec.rb` (C2 S1 → S4) · D omitted qualifier:
`end_to_end_spec.rb` (C2/C3 at S5) · E fabricated citation: `answers_spec.rb` (C4 card and
source card) · F coverage vs probability: `display_helper_spec.rb`, claim page system spec ·
G non-scoreable claim: `answers_spec.rb`, `scores_spec.rb` · H alternative model:
`compare_spec.rb`, `answers_spec.rb` (weaknesses), system spec (model selector) · I visible
moderation: `quarantine_spec.rb`, claim page system spec · J replay: `end_to_end_spec.rb`,
`replay_spec.rb`, demo replay check.

#### Final versions

Ruby 4.0.7, Rails 8.1.3.1, PostgreSQL 16 (`postgres:16`), json 2.21.2 (pinned, see Stage
1), json-canonicalization 1.0.0, json_schemer 2.5.0, Solid Queue 1.7.0, RSpec via
rspec-rails, Node 24.21.0 (unused at runtime; importmap only), Docker Compose v5.5.1.

#### Deviations from the spec, collected

UUIDv7 only on log rows, deterministic ids on projections (Stage 2); custody material in
`custodied_keys` (Stage 2); source text inside the payload, Active Storage deferred (Stage
3); the idempotency-key consequence (Stage 3); moderators designated outside the log
(Stage 4); the rounding-boundary guard applied to 4-place values (Stage 5);
`scoring_models.released_seq` instead of `created_at` (Stage 5); audit sampling inside
Apply, no job (Stage 7); one packet per task with `lease_expires_at` on the assignment
(Stage 8); tasks as operational tables, a gap in log self-containment for mirrors (Stage
8); per-result rather than per-claim acceptance of extractions (Stage 8); tie-breaks by
`created_seq` before id (Stage 9); the number rendered only on request (Stage 10); the
json gem pin (Stage 1). Each is explained in its stage above.
