# 07 — POC Roadmap and Acceptance Criteria

The previous draft built the graph tables in Phase 1 and added signed contributions in Phase 3, while `10-agent-handoff.md` recommended the opposite order. Retrofitting a log under an existing CRUD model is the most expensive mistake available here, so **the log comes first**.

Each phase ends with green CI. Do not start a phase until the previous one's acceptance tests pass.

---

## Phase 0 — Skeleton

Deliver: `12-constitution.md` copied into the repo root with its hash exposed by `/api/v1/meta`; Rails 8.x app, Docker Compose (app + postgres), Solid Queue, Active Storage (local), Hotwire baseline layout, Rails 8 authentication generator, RSpec or Minitest (pick one; document it), CI, `.env.example`, `IMPLEMENTATION.md`.

Not in this phase: pgvector, Redis, Sidekiq, a JS frontend, any external service.

Acceptance: `docker compose up` serves a page; `bin/rails test` (or `rspec`) passes in CI.

---

## Phase 1 — Log, Keys, Canonicalization

Implement: RFC 8785 canonicalization, SHA-256 helpers, Ed25519 sign/verify, `contributors` (incl. server custody and system key), `contributions` with `seq` and hash chain, `Ledger::Append`, `Ledger::Apply` skeleton, `ledger:verify`, `ledger:replay`, `REGISTER_KEY`, `DELEGATE`, `REVOKE_*`.

Acceptance:

1. Canonicalization matches the published test vectors (include RFC 8785 examples).
2. Modified payload or envelope fails verification.
3. Concurrent appends (e.g., 50 threads) produce a gap-free `seq` and a valid chain.
4. Revoked key or delegation cannot append after its revocation `seq`.
5. Historical contributions from a now-revoked key still verify.
6. `ledger:verify` detects a manually corrupted row and reports its `seq`.
7. Duplicate submission returns the original contribution.
8. Genesis: seq 0 is the self-signed system `REGISTER_KEY` and matches the pinned deployment key; a `REGISTER_KEY` with `contributor_id = null` creates its contributor; any other contribution whose `signer_key_id` and `contributor_id` disagree is rejected.
9. Control contributions take effect on append without an `ACCEPT`; an unauthorized control contribution is rejected and not logged.

---

## Phase 2 — Evidence Graph Projections

Implement via `Ledger::Apply` only: sources, source locations, claims, evidence items, evidence–claim links, claim edges, independence groups, `ACCEPT`, `INVALIDATE`, `QUARANTINE`, validity windows.

Acceptance:

1. Create source → location (excerpt hash verified) → claim → evidence → support link → contradiction link, all via `POST /contributions`.
2. Query a claim with all relationships as of the latest seq and as of an earlier seq.
3. Invalidation hides a link at later seqs but not earlier ones.
4. **Replay:** truncate projections, `ledger:replay`, and every projection row is identical (compare a table digest).
5. Projection models raise if written outside `Ledger::Apply`.
6. Epistemic rows have `accepted_seq = null` until accepted and are not counted before that; extraction-proposed claims cannot receive links until accepted by a different principal.
7. **Claim identity:** two claims whose normalized texts are near-identical but differ in population (08 `C2`/`C3`) can coexist; creating a duplicate `canonical_text` succeeds; `MERGE_CLAIMS` requires acceptance and is reversible by `INVALIDATE`.
8. **Takedown:** after a `TAKEDOWN`, `ledger:verify` reports `CHAIN_VERIFIED_WITH_REDACTIONS` with the redacted seq; replay reproduces the redacted projection; earlier traces either reproduce or are reported `UNREPRODUCIBLE_REDACTED`.

---

## Phase 3 — Deterministic Scoring and Snapshots

Implement: scoring model registry and release contribution, config validation, `Scoring::Calculate` exactly per 03, **both** `ledger-default@0.1.0` and `ledger-strict@0.1.0`, `/compare`, review checklist, stability, traces, `claim_scores` cache, `RecomputeAffected`, snapshots, `claim_score_digest`.

Acceptance:

1. **Golden tests:** every row in 08 §8 and `examples/watchers/README.md` §7 reproduces exactly (state, probability string, stability, coverage, group counts, reason), for both models, and `reference/reference_scorer.py` passes.
2. Same seq + same model → byte-identical canonical trace, including after a full cache wipe and after replay.
3. A config with a missing enum key is rejected at release.
4. Changing scorer code without bumping the version fails the `code_hash` test.
5. `NOT_APPLICABLE` and `INSUFFICIENT_EVIDENCE` never carry a probability.
6. Strongest-only suppression is per group *and* direction and is visible in the trace.
7. Golden rows for `ledger-strict` pass; releasing it changes no `ledger-default` trace.
8. Every `NOT_APPLICABLE` result carries a `not_applicable_reason`.
9. A claim with only supporting evidence never receives `LEANS_CONTRADICTED`/`CONTRADICTED` (08 `C6`), and vice versa.
10. A model whose checklist declares a check with no available task type is rejected at release.
11. Same-implementation traces are byte-identical; `rounding_boundary` is set when a value lies within the guard of a rounding boundary.

---

## Phase 4 — Audits and Reputation

Implement: `AUDIT` action, audit effects table (05 §9), `RE_AUDIT`, deterministic sampling, auditor eligibility, reputation events with principal roll-up, reputation calculation at a seq, `provisional` clearing.

Acceptance:

1. `SUBSTANTIVE_ERROR` invalidates the target, lowers reputation, and triggers recompute; history remains visible.
2. A re-audit that disagrees restores the target and invalidates the first audit's reputation event.
3. Reputation at any seq reproduces from events.
4. The same principal cannot audit its own agents' work.
5. Given a contribution hash and policy version, anyone can recompute whether it was sampled.
6. Adding audits, edges, or reputation events after a contribution does not change its `audit_schedules` row or sampling decision.

---

## Phase 5 — Agent Tasks

Implement: tasks, assignments, leases, priority, context compiler, server-signed packets, JSON Schemas, validation pipeline (04 §6), blind multi-assignment, example agent client, per-delegate limits.

Acceptance:

1. The standalone example client leases, verifies the packet signature, runs the stub verifier, signs, submits, and a `TASK_RESULT` + `ACCEPT` appear in the log.
2. Expired lease → 422; wrong `task_packet_hash` → 422; disallowed op → 422; none create contributions.
3. Two agents under one principal cannot both hold slots on the same task.
4. Packets never contain contributor notes (test by seeding a note with an injection string and asserting absence).
5. Same task inputs → identical packet bytes (excluding timestamps and signature).
6. A `QUALIFIER_CHECK` result that supersedes another principal's links stays uncounted until a different principal accepts it.

---

## Phase 6 — Summaries and UI

Implement: stub summary generator and validator, `/why`, pages in 06 §5 (including Weaknesses and Moderation log), display rules in 06 §4, model selector, snapshot picker.

Acceptance:

1. Summary sentences all cite IDs from the input set; a generator returning an unknown ID is rejected.
2. Summary cache key changes when input changes; stale summaries are not served as current.
3. System tests: the claim page's default view is the answer card and shows no probability until **Show calculation** is opened; review coverage appears as "N of M checks"; claim page shows no number for `INSUFFICIENT_EVIDENCE`; provisional label appears for unaudited links; the model selector switches traces; a quarantined claim URL renders a public stub rather than a 404.

---

## Phase 7 — Seeded Demo

Implement `db/seeds/demo.rb` and `bin/demo` per 08, and `db/seeds/examples/watchers.rb` behind `bin/demo --example watchers`.

Acceptance: both run on a clean database, print every golden value with PASS/FAIL, print URLs, and exit non-zero on any mismatch. The public demo also prints the answer cards in 08 §9.

---

## Phase 8 (P1) — Extensions

Real LLM adapter behind `Llm::Adapter` (stub remains default), questions/hypotheses, dedup candidate edges (pg_trgm → pgvector), export bundles and PROV/nanopublication mappings, embeddable answer cards, verification-diversity constraints, audit-cost reporting, political-speech view.

---

## Acceptance Scenarios (end-to-end)

The scenarios below are exercised by the public demo (08) unless marked *(Watchers)*.

**A — Quote verification.** Create source and passage; create `TEXTUAL` claim "Source S says X"; agent verification task → `CONFIRMED`; claim shows `SUPPORTED`, `provisional`; reviewer audit `CONFIRMED` → provisional clears; verifier reputation rises.

**B — Poisoned contribution.** Agent links a real passage to a claim it does not support; automated checks pass (the excerpt is real) so the link is accepted and the claim shows `SUPPORTED` + `provisional`; sampled audit returns `SUBSTANTIVE_ERROR`; link invalidated; claim returns to its earlier state (08: `C4` LEANS_SUPPORTED + contested → LEANS_CONTRADICTED; Watchers: `C5` → INSUFFICIENT_EVIDENCE); reputation falls; old snapshot still shows the poisoned state with its trace. *(This scenario exists to demonstrate that validation ≠ correctness and that the `provisional` flag matters.)*

**C — Dependent evidence.** Three articles and a press release repeat one survey. Before the independence check they count as four lineages and `C2` reads SUPPORTED 0.9085; afterward, one lineage, LEANS_SUPPORTED 0.7146 (08 S1 → S4). *(Watchers S4 → S5 shows the same with two lineages.)*

**D — Omitted qualifier.** The qualifier check finds the survey sampled only customers; supersessions are accepted; `C2` becomes UNRESOLVED while the narrower `C3` stays SUPPORTED (08 S5).

**E — Fabricated citation.** `C4` leans contradicted; the per-source card for the AI draft flags the citation as unverified.

**F — Coverage vs. probability.** A claim is `SUPPORTED` with 1 of 4 review checks (08 `C2` at S1); UI renders display rule 5.

**G — Non-scoreable claim.** "Society ought to prioritize equality over growth." → `NORMATIVE`, `NOT_APPLICABLE`, no number; supporting premises can still be linked and displayed.

**H — Alternative model.** `C6` (causal) is `UNRESOLVED` under `ledger-default` and `NOT_APPLICABLE` (`NOT_SCORED_BY_MODEL`) under `ledger-strict`; `/compare` names `scored_types` as responsible; the Weaknesses page lists `C6` under "models disagree." *(Watchers: `C3`, with `observation_weight.EXPERT_ANALYSIS` also named.)*

**I — Visible moderation.** A moderator quarantines a claim as `PRIVATE_INDIVIDUAL`; the claim's text disappears from public reads, its URL shows a stub with moderator key, date, and reason; the moderation log lists it; an old snapshot still records that the claim existed.

**J — Replay.** Drop projections and caches; replay; `claim_score_digest` for every pinned snapshot is unchanged.

---

## First Experiments (after P0 passes)

P0 proves the mechanics. These test the product hypothesis (01 §1.1). Record results in `EXPERIMENTS.md`.

1. **Claim identity.** Import several real documents with similar but non-identical claims. Measure how often candidate `SAME_AS` suggestions are wrong, and confirm no distinctions are lost.
2. **Single-user value.** Verify the citations and quotations in 5–10 real AI-generated documents with no community contributions. Record time spent, errors caught, and whether the user would do it again.
3. **Audit multiplier.** For several agent/model configurations: `useful accepted contributions ÷ (audits + corrections required)`. A configuration below 1 costs more than it helps.
4. **Answers without graphs.** Can users explain a claim's status from the answer card alone? Test with people who never open the graph.
5. **Independence impact.** How often does grouping change a state (not just the number) in real material?

---

## Required Test Areas

Constitution hash exposed · Genesis/bootstrap · control vs. epistemic effect · Canonicalization vectors · signatures · hash chain and concurrency · append-only DB permissions · replay equivalence · validity-window queries · scoring golden values · independence suppression · config validation · reputation reproducibility · audit sampling determinism · delegation/revocation · lease/validation pipeline · packet content exclusions · summary citation validation · display rules for null probabilities · multi-model isolation · quarantine stubs · personal data never written to the log · claim identity (no merge without acceptance) · takedown redaction and verify status · audit-schedule anchoring · directional-state rule · checklist executability · answer-card default view.

Security and scoring tests matter more than UI tests.

---

## Scale Expectations

The schema should not preclude ~100k claims, ~500k links, ~1M contributions (indexes in 11 §6). Load testing is not required for the POC. Do not optimize prematurely; the runtime/extraction policy is in 11 §12–13.
