# The write path slows as the corpus grows (bench:seed, 0 → 82,882 claims)

Not a profiling run in the usual sense: no `bench:cpu`, no `Bench::Isolation`. These are
throughput numbers recovered from the database *during* a long `bench:seed`, because the
run itself turned out to be the measurement. Recorded here rather than in
`docs/experiments/` because what it says is a timing at a stated corpus size.

## Conditions

- **Command:** `bin/rails 'bench:seed[100000]' RESET=1 BATCH=500`, started 2026-09-19
  20:28:41 UTC, still running when these numbers were taken at 2026-09-20 17:12 UTC
  (20h 44m elapsed).
- **Corpus at the time of reading:** 82,882 claims, 845,619 contributions (10.2 per
  claim), 419,362 audit schedules, 120,696 claim scores. `contributions` is 1,789 MB.
- **Environment:** development, in Docker — `galedra-seed` (app) against `galedra-db-1`
  (postgres:16). Commit `0bd329b`.
- **What was held still: nothing.** This is the opposite of how `docs/profiler/` entries
  are normally taken. There was no isolation, the reloader and verbose query logs were
  live, and the host also ran a desktop session. Treat the absolute rates as soft. The
  *shape* is what this entry is for.

## Numbers

Appends per hour, from `contributions.received_at`, whole run:

| Hour (UTC) | Appends | Appends/s | ms per append |
|---|---|---|---|
| 19 20:00 | 107,164 | 29.8 | 33.6 |
| 19 21:00 | 85,349 | 23.7 | 42.2 |
| 19 22:00 | 51,705 | 14.4 | 69.6 |
| 19 23:00 | 48,619 | 13.5 | 74.0 |
| 20 01:00 | 40,502 | 11.3 | 88.9 |
| 20 05:00 | 35,850 | 10.0 | 100.4 |
| 20 08:00 | 31,108 | 8.6 | 115.7 |
| 20 11:00 | 27,101 | 7.5 | 132.8 |
| 20 14:00 | 22,407 | 6.2 | 160.7 |
| 20 16:00 | 24,159 | 6.7 | 149.0 |

**4.6× slower at 83k claims than at zero**, decaying monotonically apart from noise in the
last two buckets. For comparison, `Seed#measure_unbatched` reported **52.2 appends/s
(19.2 ms each)** on an empty log at the start of this same run.

Cumulative scan counters at the time of reading (`pg_stat_user_tables`):

| Table | seq_scan | seq_tup_read | avg rows/scan | live rows |
|---|---|---|---|---|
| `source_locations` | 1,805,909 | 305,344,525 | 169 | 83,079 |
| `audits` | 624,779 | 59,132,758 | 94 | 6,920 |
| `custodied_keys` | 503,885 | 1,273,763 | 2 | small |
| `contributions` | 36 | 866,526 | 24,070 | 845,619 |

## Findings

- **The append path gets slower as the corpus grows. Status: OPEN.** The curve is the
  finding. A live node appends one contribution per transaction, so if this is corpus-size
  dependent rather than batch-dependent, it is a capacity fact and not a seeding
  inconvenience. Nothing in `implementation/planned/stage-26-capacity.md` predicts it.
- **The mechanism is NOT established. Status: OPEN.** Two hypotheses were tested against
  the code and **both failed**, which is why neither appears above as a cause:
  - *A missing index on `source_locations.excerpt_hash`* (the table has indexes on
    `contribution_id`, `source_id`, `created_seq`, `invalidated_seq`, but not
    `excerpt_hash`). Rejected: `Ledger::Appliers::CreateSourceLocation` never looks a row
    up by `excerpt_hash`; it only compares the payload hash to the excerpt it was handed.
  - *Per-append full scans of `source_locations`.* Rejected on arithmetic: a full scan per
    append against a table averaging ~41k rows over the run would read ~7×10^10 tuples;
    the counter says 3×10^8. At 169 rows per scan these are not full scans of the grown
    table.
  `contributions` is essentially never scanned (36 times), so the 1.8 GB table is not
  being walked. The cause is more likely index maintenance, WAL volume, or a per-append
  cost that grows with `claim_scores` / `audit_schedules`, but that is a guess and is
  labelled as one.
- **`pg_stat_statements` is not installed on `galedra-db-1`. Status: OPEN.** This is why
  the mechanism could not be pinned down from the server side. Installing it needs
  `shared_preload_libraries` and a **restart**, which must not happen while a 21-hour seed
  is running. Do it in the next maintenance window, before the next long seed.
- **The seed reports no progress anyone can see. Status: OPEN.** `Bench::Seed#report`
  writes a `\r`-framed line and only emits a newline at completion, so
  `docker logs galedra-seed` held **79 bytes after 21 hours** — the two opening lines and
  nothing else. Whether the frames land on a detached terminal could not be confirmed: the
  process runs as root and `/proc/<pid>/fd/1` was unreadable. Either way, "83% done" had to
  be reconstructed from row counts. A periodic newline-terminated line, or a
  `--no-tty`-aware branch, would make a long seed observable.

## What changed as a result

Nothing yet, by decision: the seed was allowed to run to completion rather than being
stopped at 83%, since restarting costs another ~21 hours under `RESET=1`. `bench:cpu`
against a still corpus — the task this entry interrupted — waits for it, and for the host
to be quiesced.

## What was wrong in the watching

- **The last bucket reads `523` and looks like a collapse.** It is not. It is a partial
  hour holding an uncommitted transaction that had been open 11m 41s. `docs/CONTEXT.md`
  records this exact misreading happening twice before; this would have been the third.
  The check that settled it was `now() - xact_start` from `pg_stat_activity`, one query.
- **A 20h 45m process at 79% CPU with a backend `idle in transaction` reads as hung.** It
  was not. Two `/proc/<pid>/stat` samples showed utime advancing ~10 CPU-seconds between
  them, and at the current rate one `BATCH=500` transaction covers ~10k appends ≈ 25
  minutes, so an 11-minute open transaction is mid-batch and normal.
- **Load average 18 was attributed to the seed on sight.** Wrong: an `ollama`
  `llama-server` at ~1027% CPU was most of it, started minutes before the reading. It is
  also why it cannot explain a 21-hour monotonic decay — worth stating, because a
  contention confound is the first thing this entry would otherwise be dismissed for.
