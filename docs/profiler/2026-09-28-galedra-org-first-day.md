# 2026-09-28 — galedra.org's first day, read from pg_stat_statements

The first measurement taken on the production node rather than a workstation. Request
metrics (Stage 40) were off there until 21:54 UTC, so the only record of the first day is
Postgres's own: `pg_stat_statements`, collecting since the database started.

## Conditions

- **Machine:** DigitalOcean `s-1vcpu-2gb`, one vCPU, 2 GB, shared with a second app.
- **Corpus:** 10,619 contributions, 448 claims, 129 MB database, entirely in memory (table
  cache hit 99.99%, index 99.97%).
- **Load:** mostly one xAI worker with two parallel sessions, 2026-09-28 18:35–21:45 UTC,
  about 130 requests a minute at its peak; that minute cost 14% of the one core, summed
  from the request durations in the app log.
- **Window:** 2026-09-27 17:53 UTC to 2026-09-28 21:50 UTC, reset after this entry.

## What it said

1,788,220 statements, 305 s of execution in total, 0.17 ms each on average.

| Share | Statement | Calls | Mean | Max |
|---|---|---|---|---|
| **38%** | a task's `TASK_RESULT`s by `task_id` (`Tasks::Checks.accepted_results`) | 21,201 | 5.50 ms | 188 ms |
| 7% | score cache read for a set of claims | 23,184 | 0.87 ms | 31 ms |
| 5% | `pg_advisory_xact_lock` (the append lock) | 2,995 | 4.92 ms | **3,993 ms** |
| 4% | "was this result self-performed?", one result at a time | 39,459 | 0.31 ms | 35 ms |
| 1% | a claim's independence assignment, one evidence item at a time | 85,316 | 0.05 ms | 8 ms |

**The 38% was a missing index.** `contributions` had none on `task_id`, so each lookup read
every task result and filtered: 839 buffers and 1,564 rows removed to return one. Indexed on
`(task_id, seq)` in `821e3ce`, the same statement reads 5 buffers in 0.02 ms. It ran once per
cold score of one claim, and its cost grew with every result recorded.

**The self-performed question is now one per claim** (`Tasks::Checks.for`, same commit;
`spec/services/tasks/checks_spec.rb` holds the count flat as results grow).

**Left as found:**
- The single-claim scoring path still asks each evidence item's independence group one at a
  time (`Scoring::BuildInput.links_for`). Cheap per call, and the batch path already has the
  set form; making the single path use it has to keep the trace byte-identical (Invariant 4).
- The append lock serialises writes by design; one waiter waited four seconds while two
  workers wrote at once. It is the likeliest cause of the slowest `add_evidence` and
  `submit_task` calls (p99 5.6 s and 1.3 s in the app log), which the request metrics can now
  confirm or refute.

## Server-side tool latency over the run (from the app log, not the database)

| Tool | Calls | p50 | p95 | Max |
|---|---|---|---|---|
| `next_task` | 662 | 47 ms | 165 ms | 0.9 s |
| `submit_task` | 693 | 239 ms | 805 ms | 4.4 s |
| `add_evidence` | 111 | 589 ms | 4.4 s | 7.3 s |
| `list_claims` | 45 | 104 ms | 1.07 s | 1.4 s |
