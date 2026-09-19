# Stage 7 — Audits and reputation

**Status:** implemented · tag `stage-07-audits` · decisions recorded 2026-09-17

## Plan

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

## Decision Log (2026-09-17)

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
