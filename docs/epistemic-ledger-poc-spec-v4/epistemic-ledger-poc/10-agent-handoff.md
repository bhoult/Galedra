# 10 — AI Coding Agent Handoff

You are implementing the initial POC of the Epistemic Ledger. Read `12-constitution.md` first, then README and files 01–11 and 13 (or `FULL-SPEC.md`, not both), before writing production code.

**Precedence:** the constitution outranks everything. Among spec files, the more specific file wins: 03 for scoring, 02 for schema, 04 for protocol, 07 for order and acceptance. If following the spec would violate an Article, stop, record the conflict in `IMPLEMENTATION.md`, and choose the reading that honors the Article.

## Primary Objective

A locally runnable POC meeting the README's P0 Definition of Done, demonstrated by `bin/demo` against the golden values in 08 §8 (and `bin/demo --example watchers` against `examples/watchers/README.md` §7).

## Invariants

1. **Log first.** Every epistemic mutation is a signed contribution appended through `Ledger::Append`; projections are written only by `Ledger::Apply`.
2. **Replayable.** Truncating projections and replaying the log reproduces identical projections and snapshot digests.
3. **Append-only.** Accepted history is never silently rewritten; corrections are new contributions.
4. **Deterministic, versioned scores.** Same seq + same model → byte-identical trace.
5. **Unknown is explicit.** `NOT_APPLICABLE` and `INSUFFICIENT_EVIDENCE` carry no probability anywhere.
6. **No double counting.** Dependent evidence is suppressed per independence group and direction, visibly.
7. **AI is never evidence by itself.** `MODEL_OUTPUT` weighs 0; agent results are ops that pass validation and remain auditable.
8. **Reputation is audit-derived, task/domain-specific, and not a scoring input in v0.1.**
9. **No self-certification** by the same contributor or the same principal.
10. **Summaries only restate supplied graph content**, and every sentence cites it.
11. **Untrusted text stays inert.** Contributor notes and excerpts never reach scoring, and notes never reach other agents.
12. **Moderation is visible.** Quarantine and takedown leave public stubs; nothing disappears without a trace.
13. **Shared and personal stay separate.** Nothing user-specific or opinion-shaped is written to the log except as an ordinary, evidence-bearing contribution.
14. **More than one model.** Scoring code must never assume a single model; the second model exists to keep that honest.
15. **No text-uniqueness for claims.** Similarity proposes relationships; only an accepted `MERGE_CLAIMS` merges.
16. **Answers first, numbers never the headline.** The default claim view is the answer card. A probability, when there is one, sits under the headline with its model and snapshot (owner decision, 2026-09-23); the trace sits behind Show calculation.
17. **Determinism is not objectivity.** Never describe a score as objective in UI copy, docs, or API field names.

## Constitutional Test

For every change that touches scoring, identity, reputation, moderation, visibility, selection, or history, answer the ten questions at the end of `12-constitution.md` in the stage's file under `implementation/`. Treat any "no" to 1, 2, 5, 6, 7, 8, 9, or 10, or any "yes" to 3 or 4, as a blocker until a justification is published with the change. Do not edit `12-constitution.md`; propose changes in `CONSTITUTION-AMENDMENTS.md` under "Proposed". An amendment takes effect when the owner adopts it and it is recorded as a signed `AMEND_CONSTITUTION` (Article XXV).

## Framework Decision (already made)

Rails 8.x. Record exact Ruby, Rails, PostgreSQL, and gem versions in `IMPLEMENTATION.md`. Do not evaluate alternatives unless there is a hard blocker. Runtime and extraction policy: 11 §12–13.

## Required Artifacts

```text
IMPLEMENTATION.md          versions, decisions, assumptions, deviations from spec (with reasons)
docker-compose.yml
.env.example
db/migrate/*
app/…                      per 11 §5
schemas/eir-task-v1.json, schemas/eir-result-v1.json
test/fixtures/canonical_json_vectors.json
config/scoring/ledger-default-0.1.0.json   (copy of scoring-config-v0.1.json)
config/scoring/ledger-strict-0.1.0.json    (copy of scoring-config-strict-v0.1.json)
CONSTITUTION.md                            (copy of 12-constitution.md; hash served by /meta)
db/seeds/demo.rb
examples/agent/            (client + fixtures.json)
bin/demo                   (public demo; --example watchers for the stress test)
db/seeds/examples/watchers.rb
EXPERIMENTS.md             (after P0; 07 First Experiments)
lib/tasks/ledger.rake      (ledger:verify, ledger:replay)
```

## Order of Work

Follow the phases in 07 exactly:

```text
0 skeleton → 1 log/keys/canonicalization → 2 projections → 3 scoring/snapshots
→ 4 audits/reputation → 5 tasks → 6 summaries/UI → 7 demo → (8 P1 only if asked)
```

`reference/reference_scorer.py` is an independent implementation of 03 that already reproduces both golden tables (public demo and Watchers). Use it to cross-check, not as code to port line by line.

## Implementation Notes

- **Crypto:** well-maintained Ed25519 library; never hand-roll primitives. Test vectors in CI.
- **Canonical JSON:** RFC 8785 via an established gem (e.g. `json-canonicalization`). If you must deviate, document exact rules and ship vectors.
- **Decimals:** `BigDecimal` throughout scoring; serialize as strings.
- **Concurrency:** `pg_advisory_xact_lock` around log appends.
- **DB permissions:** the app role cannot `DELETE` from `contributions` or `UPDATE` anything but `current_status`.
- **Service objects, not callbacks** (11 §4); plain serializable inputs/outputs at the scoring and context-compiler boundaries.
- **Background jobs:** Solid Queue; every job idempotent and keyed by `(target, seq)`.
- **Frontend:** Hotwire only; functional, not polished.
- **LLM:** optional. The whole demo runs with no API key using stubs.
- **Tests:** security, log, and scoring tests before UI tests.

## When Uncertain

Choose the simplest reversible option that preserves the invariants, record it in `IMPLEMENTATION.md`, and continue. Stop and ask only if a requirement is impossible or two requirements cannot both hold. **Never** "fix" a golden value by editing 08; if your result differs, either your implementation or the spec is wrong — find out which and document it.

## Success Standard

```bash
docker compose up -d
bin/demo        # prints PASS for every golden row and for the replay check, exits 0
```

Then a developer can open the UI, read the answer cards for the AI-drafted memo, and drill into signatures, the hash chain, score traces, audits, reputation changes, and each snapshot. The POC should be understandable and credible, not production-ready.
