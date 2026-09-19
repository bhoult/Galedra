# Stage 11 — Seeded demos and P0 Definition of Done

**Status:** implemented · tag `stage-11-demo` · decisions recorded 2026-09-17

## Plan

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

## Decision Log (2026-09-17)

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
  every table under the owner role first; `01 §7`'s "runs on a clean database" is
  enforced rather than assumed. `--reset` raises outside development and test
  (`Rails.env.local?`), and unknown arguments or examples abort with usage, so a typo
  cannot truncate a log or seed the wrong demo. Model releases share
  `Ledger::ReleaseModels` with `ledger:release_models`; the two scripts share
  `Demo::Script` (cast, checkpoints, result); the report takes its models from the
  golden fixture rather than from every released model.
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

### P0 Definition of Done (SPEC README) → where it is demonstrated

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

### Acceptance scenarios A–J (07) → covering test

A quote verification: `spec/services/tasks/tasks_spec.rb` #1 and `audits_spec.rb` #2 ·
B poisoned contribution: demo S2 → S3, `end_to_end_spec.rb`, `audits_spec.rb` #1 ·
C dependent evidence: `end_to_end_spec.rb` (C2 S1 → S4) · D omitted qualifier:
`end_to_end_spec.rb` (C2/C3 at S5) · E fabricated citation: `answers_spec.rb` (C4 card and
source card) · F coverage vs probability: `display_helper_spec.rb`, claim page system spec ·
G non-scoreable claim: `answers_spec.rb`, `scores_spec.rb` · H alternative model:
`compare_spec.rb`, `answers_spec.rb` (weaknesses), system spec (model selector) · I visible
moderation: `quarantine_spec.rb`, claim page system spec · J replay: `end_to_end_spec.rb`,
`replay_spec.rb`, demo replay check.

### Final versions

Ruby 4.0.7, Rails 8.1.3.1, PostgreSQL 16 (`postgres:16`), json 2.21.2 (pinned, see Stage
1), json-canonicalization 1.0.0, json_schemer 2.5.0, Solid Queue 1.7.0, RSpec via
rspec-rails, Node 24.21.0 (unused at runtime; importmap only), Docker Compose v5.5.1.

### Deviations from the spec, collected

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
