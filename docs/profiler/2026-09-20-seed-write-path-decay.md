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
- **The mechanism is established: an N+1 in `Reputation::Calculate`. Status: FIXED
  2026-09-20 (`6d2077d`).** See the correction at the end of this entry for the measurement,
  and the fix note below it. The two hypotheses below were tested first and **both failed**, and are kept
  because a rejected cause is worth as much as the accepted one:
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
- ~~**`pg_stat_statements` is not installed on `galedra-db-1`.**~~ **WRONG — see the
  correction below. Status: NO ACTION NEEDED.** It is preloaded and always was; Stage 26
  built it. It was merely absent from the `galedra_bench` database, and the counters are
  server-wide and were readable the whole time.
- **The seed reports no progress anyone can see. Status: OPEN.** `Bench::Seed#report`
  writes a `\r`-framed line and only emits a newline at completion, so
  `docker logs galedra-seed` held **79 bytes after 21 hours** — the two opening lines and
  nothing else. Whether the frames land on a detached terminal could not be confirmed: the
  process runs as root and `/proc/<pid>/fd/1` was unreadable. Either way, "83% done" had to
  be reconstructed from row counts. A periodic newline-terminated line, or a
  `--no-tty`-aware branch, would make a long seed observable.

## What changed as a result

The N+1 was fixed (`6d2077d`); see the fix note at the end of this entry. The decay curve
above was measured *before* that change and is kept as the before, since there is no after
yet: the running seed started under the old code, so a comparable number needs a fresh run.

The seed itself was allowed to run to completion rather than being stopped at 83%, since
restarting costs another ~21 hours under `RESET=1`. `bench:cpu` against a still corpus — the
task this entry interrupted — waits for it, and for the host to be quiesced. That run is
also Stage 26 acceptance criteria 1-2, not a side errand.

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


## Correction, same day · **APPLIED**

Two claims above were wrong, and correcting them produced the cause the entry said it did
not have.

**`pg_stat_statements` was never missing.** The check behind that claim was
`select count(*) from pg_extension` run **against `galedra_bench`**, and its answer — the
extension is not registered in this database — was generalised to "not installed on the
server", which does not follow. `show shared_preload_libraries` returns
`pg_stat_statements`; Stage 26 preloaded it in both compose files and added
`bin/rails db:top_queries` to read it. The extension is present in `galedra_development`.
Because the counters are shared across the whole server, the bench database's statements
were readable all along from any database that has the view, by filtering on `dbid` — no
DDL, no restart, and nothing that could disturb the running seed. The recommendation to
wait for a maintenance window was wasted advice built on a database-scoped check.

**The cause, now measured.** Statements for `galedra_bench`, worst by total time:

| Statement | Calls | Mean | Rows/call | Total |
|---|---|---|---|---|
| `SELECT "audits".* WHERE "audits"."id" = $1 LIMIT $2` | **366,107,078** | 0.00 ms | 1.0 | 1,123 s |
| `SELECT "contributions".* WHERE "idempotency_key" = $1` | 1,818,780 | 0.21 ms | 0.0 | 380 s |
| `INSERT INTO "contributions" …` | 876,084 | 0.39 ms | 1.0 | 339 s |
| `SELECT "reputation_events".* WHERE "created_seq" <= …` | 434,451 | 0.56 ms | **842.7** | 243 s |

366 million single-row `audits` lookups, on a table holding 6,920 rows. The call count
matches the reputation query's returned rows almost exactly (434,451 × 842.7 ≈ 366.1M),
which pairs them: one `audits` lookup per reputation event loaded.

The call site is `Reputation::Calculate.summarize`:

```ruby
counts: events.map { |e| e.audit.result }.tally
```

`events` is a relation with no `includes(:audit)`, so every event fetches its audit
individually. `summarize` runs per audit-eligibility check — 434k times across this run —
and the event set it walks **grows with the corpus**, so the per-call cost rises as the log
lengthens. That is the O(n²) shape the hourly curve shows, and it is a *write*-path N+1,
which is a different animal from the read-path N+1s in
`2026-09-19-weaknesses-at-3000-claims.md`.

**Fixed same day, in `6d2077d`.** The repair turned out to be smaller than the caution above
suggested, because the hot path does not want the tally at all: `Audits::Eligibility` and
`Audits::Sample` call `Calculate.call` on every append and read only `n` and `mean`. So the
tally is now opt-in and off by default there — the audits table is not touched on the append
path rather than touched more cheaply — while `buckets`, which the contributor page and API
display, preloads the association and pays one query instead of one per event. Neither
change can move a value, which is what let it happen without a new model version.

A spec counts the statements: 0 on the hot path, 1 on the display path, values unchanged. It
was checked against the old code and fails there with 3 where it expects 0, so it tests what
it claims to. What is still unfixed is the event rows themselves, ~843 per call: summing the
deltas in SQL would cut that too, but they are `BigDecimal` values feeding audit sampling, so
that one really does want goldens and a stage.

**What was wrong in the watching, second pass.** The first version of this entry said the
mechanism could not be established and named the tool that would establish it as missing.
Both halves came from one database-scoped query whose scope I did not state to myself. The
file's own standing lesson is that a filter narrow enough to look tidy discards what you
needed; a query scoped to one database out of three is that same mistake wearing different
clothes, and it cost the entry its cause.


## The batch rhythm, sampled at two minutes · 2026-09-20 18:14 UTC

The hourly buckets above come from `contributions.received_at` and cannot show commit
granularity. A watcher sampling row counts every two minutes can, and the shape it gives
explains why a long seed looks stalled when it is not.

Over 56 minutes at 85% corpus (82,882 → 84,855 claims, 845,660 → 865,878 contributions):

| | |
|---|---|
| Claims | 2,110 / hour |
| Appends | 21,617 / hour |
| **Commits observed** | **2** |
| **Appends per commit** | **10,064 and 10,154** |
| Implied batch duration | ~28 minutes |

`BATCH=500` is 500 *investigations*, and an investigation averages ~2 claims and ~10
contributions, so one transaction carries about 10,000 appends. At this corpus that is
nearly half an hour in which **both counters do not move at all**, because nothing has
committed yet.

**This is the number that should set a stall threshold.** A watcher that pages after 30
minutes of frozen counters would have fired twice in this window on a perfectly healthy run.
The one used here waits 90 minutes on *both* counters and keys its terminal signal off the
container exiting instead, which is unambiguous. The related trap is already recorded above:
a count taken inside one of these windows reads as a collapse, and `now() - xact_start` is
what tells the two apart.

**The decay continues.** 24,159 appends in the 16:00 hour, ~21,600/hour here. Remaining work
at this rate is about 7 hours, and the rate is still falling.

**None of the day's fixes are in this run.** The seed container started before them and has
not been restarted, so it is still executing the pre-fix code, `Reputation::Calculate`
included. That is why the curve above is a before with no after: measuring the fix needs a
fresh seed, which is another ~21 hours.
