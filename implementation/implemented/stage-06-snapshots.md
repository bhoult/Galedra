# Stage 6 — Snapshots, score cache, and score endpoints

**Status:** implemented · tag `stage-06-snapshots` · decisions recorded 2026-09-17

## Plan

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

## Decision Log (2026-09-17)

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
