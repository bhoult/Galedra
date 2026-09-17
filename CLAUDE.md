# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

Galedra is an **epistemic ledger**: an append-only, signed, hash-chained log of claims,
evidence, provenance, audits, and deterministic scoring, contributed to by humans and AI
agents alike. It is a source of traceable reasons for believing or doubting a claim, not a
source of truth. The spec uses the working name **Epistemic Ledger**; that is the same
project. Do not spend time on branding.

**Status: specification complete (v4), implementation not started.** The repo contains
only `README.md`, `LICENSE`, and the spec under `docs/`. No application code, no
`Gemfile`, no tests yet.

## Layout

```
README.md                     public summary, derived from the spec; keep it consistent with the spec
docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/     ("SPEC" below)
  12-constitution.md          25 Articles + Constitutional Test. Outranks every other file.
  README.md                   purpose, principles, conventions, P0 Definition of Done
  01 … 11, 13                 product/scope, domain model, scoring, agent protocol, identity/security,
                              API/UI, roadmap/acceptance, public demo + golden values, deferred work,
                              coding-agent handoff, Rails architecture, constitutional compliance map
  CONSTITUTION-AMENDMENTS.md  append-only amendment log; P-1..P-4 are proposed, not adopted
  REVIEW-NOTES.md             what changed across spec revisions and why (numbered entries)
  scoring-config-v0.1.json    authoritative config for ledger-default@0.1.0
  scoring-config-strict-v0.1.json                         for ledger-strict@0.1.0
  reference/reference_scorer.py   independent Python cross-check that reproduces every golden value
  examples/watchers/README.md     internal stress test (textual/interpretive claims) with its own goldens
  build-full-spec.sh          regenerates FULL-SPEC.md
  FULL-SPEC.md                GENERATED concatenation of the above. Never edit by hand.
```

## Reading order and precedence

1. `12-constitution.md` first. Then SPEC `README.md`, then `01` through `11`, then `13`.
2. Read **either** the numbered files **or** `FULL-SPEC.md`, never both (identical content).
3. **Precedence:** the constitution outranks everything. Among spec files the more specific
   file wins: `03` for scoring, `02` for schema, `04` for agent protocol, `05` for
   identity/audits, `06` for API and display rules, `07` for build order and acceptance,
   `11` for stack and extraction policy. `09` is deferred work: do not build it.
4. If following the spec would violate an Article: stop, record the conflict, and take the
   reading that honors the Article. Never resolve a conflict silently.

## Rules for editing the spec

- **Never edit `12-constitution.md`.** Propose changes under "Proposed" in
  `CONSTITUTION-AMENDMENTS.md`, following Article XXV's five-part format.
- **Never hand-edit `FULL-SPEC.md`.** After changing any source file, run
  `build-full-spec.sh` and commit the regenerated file in the same commit.
- **Never change a golden value** in `08 §8` or `examples/watchers/README.md §7` to make
  something pass. If a number looks wrong, run the reference scorer and work out whether
  the spec or the implementation is wrong; document the finding.
- After any change to `03`, either scoring config, or a golden table, run the reference
  scorer. It must print `ALL PASS`. Its expected tuples change only for a deliberate spec
  change, recorded in `REVIEW-NOTES.md`.
- A change that touches an Article must update `13-constitutional-compliance.md`.
- Record substantive revisions as new numbered entries in `REVIEW-NOTES.md`, continuing
  the existing sequence.
- Cross-references use the form `02 §1.3`. Keep them accurate when renumbering.
- `11` is the single home for the stack rationale and the Rails/Go/Rust extraction
  policy. Do not repeat it elsewhere.
- Outward-facing examples use the public demo in `08` (the remote-work memo). Watchers is
  internal.
- The root `README.md` was rewritten from the spec. When the spec changes, check it still
  agrees.

## Canonical vocabulary

Use these names exactly. No synonyms anywhere: not in docs, code, API fields, or UI copy.

- Score fields: `probability`, `assessment_state`, `review_coverage`, `stability`,
  `support_groups`, `contradict_groups`, `independence_unreviewed`, `contested`,
  `provisional`, `not_applicable_reason`, `model_dependent`, `trace`.
- Assessment states: `SUPPORTED`, `LEANS_SUPPORTED`, `UNRESOLVED`, `LEANS_CONTRADICTED`,
  `CONTRADICTED`, `INSUFFICIENT_EVIDENCE`, `NOT_APPLICABLE`.
- Scoring models: `ledger-default@0.1.0` and `ledger-strict@0.1.0` (same code, different config).
- Enums are `UPPER_SNAKE_CASE` strings validated against a closed list, never Postgres enum types.
- Database primary keys are UUIDv7. Handles like `C2`, `E1`, `L3`, `G1`, `S4` in the docs
  are display handles only.
- Snapshots are identified by log sequence number `seq`, never by timestamp.
- **No floats in signed payloads or traces.** Decimals are strings with fixed places;
  scoring uses `BigDecimal`, rounding half-to-even (6 places for weights, 4 for probability,
  2 for coverage).
- Hashes are `sha256:` + hex over RFC 8785 canonical JSON (or raw bytes for blobs).
- Say "0.86 under `ledger-default@0.1.0` at snapshot 212", never "86% true". Never
  describe a score as objective.

## Invariants

These must hold in any code written here (from `10-agent-handoff.md`, condensed).

1. **Log first.** Every epistemic write is a signed contribution appended through
   `Ledger::Append`. `POST /api/v1/contributions` is the only write path.
2. **Projections are written only by `Ledger::Apply`.** Projection models are read-only
   outside it. Truncate projections, replay the log, and every row and snapshot digest
   comes back identical.
3. **Append-only.** Corrections are new contributions (`INVALIDATE`, `SUPERSEDE_*`,
   `ACCEPT`). The app's DB role cannot `DELETE` from `contributions` or `UPDATE` anything
   but the cached `current_status`. The one exception is a signed, visible `TAKEDOWN`.
4. **Deterministic, versioned scores.** Same `seq` + same model = byte-identical trace.
   Scorer code changes require a new model version (`code_hash` test).
5. **Unknown is explicit.** `NOT_APPLICABLE` and `INSUFFICIENT_EVIDENCE` carry no
   probability anywhere. A directional state requires evidence pointing that direction;
   the prior alone never produces one.
6. **No double counting.** Strongest-only per independence group and per direction,
   visible in the trace.
7. **AI is never evidence by itself.** `MODEL_OUTPUT` weighs 0. Agent results are
   structured ops with closed enums that pass server-side validation and stay auditable.
8. **Reputation is audit-derived, task/domain-specific, and not a scoring input in v0.1.**
9. **No self-certification.** The same contributor or principal cannot audit or accept its
   own work.
10. **Summaries only restate supplied graph content**; every sentence cites graph IDs.
11. **Untrusted text stays inert.** Contributor `note` fields and excerpts never reach
    scoring; notes never reach other agents' packets. No server-side fetching of
    agent-supplied URLs.
12. **Moderation is visible.** Quarantine and takedown leave public stubs and appear in
    the public moderation log.
13. **Shared and personal stay separate.** Personal assessments (P1) live outside the log.
14. **More than one model.** Scoring code never assumes a single model.
15. **No text-uniqueness for claims.** Similarity only proposes relationships; only an
    accepted `MERGE_CLAIMS` merges, and it is reversible.
16. **Answers first, numbers on request.** The default claim view is the answer card;
    probabilities sit behind "Show calculation".
17. **Determinism is not objectivity.**

For any change touching scoring, identity, reputation, moderation, visibility, or
history, answer the ten Constitutional Test questions (end of `12-constitution.md`) in
`IMPLEMENTATION.md`. A "no" to 1, 5, 6, 7, 8, or 9, or a "yes" to 3 or 4, is a blocker
until justified in writing.

## When implementation begins

- **Stack is decided; do not re-evaluate.** Rails 8.x monolith, PostgreSQL 16+, Solid
  Queue, Solid Cache, Active Storage on local disk, Hotwire, REST/JSON under `/api/v1`,
  Ed25519 (`ed25519` gem or OpenSSL 3; never hand-rolled), RFC 8785 via an established gem
  (e.g. `json-canonicalization`), `json_schemer`, Rails 8 authentication generator and
  `rate_limit`, Docker Compose with exactly two services (`app`, `db`).
- **Not in P0:** Redis, Sidekiq, pgvector, a JS frontend, event-sourcing frameworks, any
  external service. LLM features are optional and stubbed by default; the whole demo runs
  with no API key.
- **Build in the phase order of `07`**, each phase ending with green CI, and do not start
  a phase until the previous one's acceptance tests pass:
  `0 skeleton → 1 log/keys/canonicalization → 2 projections → 3 scoring/snapshots →
  4 audits/reputation → 5 tasks → 6 summaries/UI → 7 demo`. Phase 8 (P1) only if asked.
- **Test framework:** `07` says pick RSpec or Minitest and document it. The owner's other
  Rails projects use RSpec; prefer RSpec unless told otherwise.
- **Required artifacts** (full list in `10`): `IMPLEMENTATION.md` (versions, decisions,
  assumptions, deviations with reasons, Constitutional Test answers), `CONSTITUTION.md`
  (copy of `12`, hash served by `/api/v1/meta`), `config/scoring/ledger-default-0.1.0.json`
  and `ledger-strict-0.1.0.json` (copies of the two configs), `schemas/eir-task-v1.json`
  and `eir-result-v1.json`, `test/fixtures/canonical_json_vectors.json`,
  `lib/tasks/ledger.rake` (`ledger:verify`, `ledger:replay`), `db/seeds/demo.rb`,
  `db/seeds/examples/watchers.rb`, `bin/demo`, `examples/agent/` (standalone client with
  `fixtures.json`, no Rails dependency), `docker-compose.yml`, `.env.example`.
- **Code layout** follows `11 §5`: thin controllers, service objects under `app/services/`
  (`Crypto::`, `Ledger::`, `Scoring::`, `Audits::`, `Tasks::`, `Summaries::`, …), no
  epistemic logic in Active Record callbacks, a `Projection` concern providing
  `active_at(seq)` and read-only enforcement.
- **Concurrency:** `pg_advisory_xact_lock` around log appends so `seq` is gap-free.
  Background jobs are idempotent and keyed by `(target, seq)`.
- **Test priority:** security, log, and scoring tests before UI tests. Golden tests must
  cover every row of `08 §8` and Watchers `§7` under both models.
- **When uncertain:** choose the simplest reversible option that preserves the
  invariants, record it in `IMPLEMENTATION.md`, and continue. Stop and ask only when a
  requirement is impossible or two requirements cannot both hold.
- **Success standard:** `docker compose up -d && bin/demo` prints PASS for every golden
  row and the replay check and exits 0.

## Commands

Available now:

```bash
# Regenerate FULL-SPEC.md after editing any numbered spec file
bash docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/build-full-spec.sh

# Cross-check the scoring spec and configs against the golden values (must print ALL PASS)
python3 docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/reference/reference_scorer.py
```

Planned once Phase 0 exists (names are fixed by the spec):

```bash
docker compose up -d
bin/rails test            # or: rspec
bin/rails ledger:verify
bin/rails ledger:replay
bin/demo                  # public demo (08)
bin/demo --example watchers
```

## Git

Commit messages are one short imperative sentence in sentence case with no type prefix,
matching the existing history (e.g. "Add POC spec v4 and rewrite README from it").

## Decisions reserved for the project owner

Do not resolve these unilaterally; implement the conservative reading already in the spec
and flag them when relevant.

- Adopt, revise, or reject proposed amendments P-1 through P-4.
- Data license for the public log (CC0 vs CC-BY).
- Who holds the system key and appoints moderators after the POC.
- Whether `LEGAL` claims are scored before a legal model exists (currently not evaluable).
- Whether `TEXTUAL` stays a distinct claim type.
