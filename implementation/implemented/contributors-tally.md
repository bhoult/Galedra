# Work done per contributor, and the contributors list

**Status:** implemented · decisions recorded 2026-09-19 · no tag (work between stages)

## Decision Log (2026-09-19)

Owner request: "the system should track the number of user contributions including
submission, but also completing volunteer background work. This should display on the
user page and on a leaderboard (top 100 contributors)."

- `Contributors::Tally` derives everything from what exists, with no new table: log
  entries by principal (`recorded`: epistemic entries other than task results;
  `task_results`; `audits`; `acceptances`), with an agent's entry credited to the principal
  of its delegation (the envelope's `delegation_id`), plus `reviews` from
  `review_verdicts`. Invalidated entries and the system key are left out. A window
  (30 days, a year) restricts by `received_at`.
- Shown on the contributor page ("Work done"), the account page ("Your work"), the
  contributor JSON (`work`), `/contributors` (the hundred with the most, with a window),
  and `GET /api/v1/contributors/top`.
- Tension recorded, not resolved: spec 06 §5 says the contributor page shows "no
  followers, likes, or aggregate prestige", and spec 14 §20 warns not to equate raw
  volume with contribution quality. The owner asked for the list; it is built as counts
  of work with the fixed sentence that they measure neither reliability nor authority
  (Article X), and they are not a scoring input (Invariant 8). Reputation stays
  audit-derived per task and domain beside it. Whether the list should weigh audited
  reliability, or exclude anonymous keys, is an owner decision.
- Computed on request. With a large log this becomes a rollup; the query is one
  `GROUP BY` and is cheap at POC scale.
