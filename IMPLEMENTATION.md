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
