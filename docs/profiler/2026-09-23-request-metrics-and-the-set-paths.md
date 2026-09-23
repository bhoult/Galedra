# What the request metrics named, and the set paths that answer it

**Date:** 2026-09-23 · **Status:** current · **Commits:** `88131b3`, `149a376`, `65e070c`

## Conditions

- **Where the targets came from:** `bin/rails metrics:report` on the development node
  (Stage 40), seven days of real traffic, most of it connected assistants working the queue.
  Ranked by total time: `mcp#submit_task` 67.5 s over 474 calls at 190 statements each;
  `mcp#record_investigation` 36.6 s over 7 calls at 6,965 statements, worst 19.1 s and
  27,032; `/weaknesses` 35.5 s over 30; `/snapshots/:seq` 487 statements a view.
- **Corpora:** the development node (386 counted claims, 7,531 contributions) for statement
  counts and equivalence, and `galedra_bench` — **100,034 claims, 1,019,861 contributions** —
  for the timings. The bench database was brought up to date first; one of the seven
  migrations it lacked was `IndexAcceptanceTargets` (Stage 39), so the 2026-09-21 figures
  were taken without that index.
- **Machine:** the 24-cpu development workstation, Docker Compose, postgres:16.
- **Held still: the host.** `ollama` had nothing loaded, GPU at 4%, load average 0.3 — the
  first quiet run in this folder. The wall times are therefore comparable with each other and
  are not upper bounds.
- **Before and after on the same corpus:** the code at `eaccf8a` ran from a worktree against
  the same database, same process settings, same script (`LEDGER_REQUEST_METRICS=off`).
  Medians of three runs after one warm-up.

## Numbers

### At 100,034 claims

| Workload | Before | After | Statements |
|---|---|---|---|
| `GET /snapshots/:head` | **49,252 ms** | **1,041 ms** | 100,141 → 19 |
| `GET /weaknesses`, page cache off | 4,857 ms | **2,123 ms** | 727 → 49 |
| `GET /api/v1/claims` | 593 ms | 343 ms | 1,074 → 734 |
| `GET /claims` | 58.6 ms | 10.4 ms | 106 → 7 |
| `GET /claims/:id` | 35.2 ms | 37.9 ms | 59 → 59 |
| `record_investigation`, 10 claims | 4,995 ms | 4,220 ms | 4,667 → 2,569 |

### On the development node (statements)

| Path | Before | After |
|---|---|---|
| `/weaknesses`, default page | 929 | 57 |
| `record_investigation`, 25 claims | 11,574 | 6,310 |
| `submit_task`, a null result | 142–148 | 90–96 |
| `/snapshots/:head` | 485 | 9 |
| `/claims` | 106 | 7 |
| outline page | 81 | 34 |
| claims API, 200 claims presented | 4,707 | 3,283 |

## What it found

1. **The per-claim scorer input was the N+1 under everything.** `Scoring::BuildInput` asked
   per claim for its links, each item's independence group, its placements, its evaluability
   and the creating contribution's whole row, its check tasks, their results and their
   standing. `BuildInput.call_many` answers a set of (claim, seq) pairs from one load per
   table, with every window applied in Ruby by the scope's own predicate, and falls back to
   the original query wherever SQL could break a tie differently. Byte-identical to
   one-at-a-time on all 386 claims at their watermarks, at the head and at an older seq, and on
   the demo at every checkpoint (`spec/services/scoring/build_input_batch_spec.rb`).
2. **Every append asked sixteen tables which rows it had written.** `projection_rows` now asks
   the tables its action type can write (`Contribution::PROJECTIONS_BY_ACTION`), a task result
   the tables of its ops, and anything unknown every table. A spec compares it with a search of
   every table for every contribution the demos write, and fails if an action type is
   undeclared or an applier creates outside its entry.
3. **The whole-graph pages read what they did not use.** The snapshot digest loaded and parsed
   every 2 KB trace to hash-compare one field; it now reads `trace_hash`. The score cache was
   asked with `IN` lists quoted element by element in Ruby; one array parameter halves the
   query (1,599 → 756 ms for the corpus, identical rows). `/weaknesses` built 100,034 model
   objects to read three fields, passed a hundred thousand ids to three queries, and read a
   ten-column summary under each model to compare one. Its output is byte-identical to the
   code before today on both corpora.

## What did not work

**A trigram index for the near-duplicate check made it three times slower here.** The check
is 2.9 of the 4.4 s a ten-claim investigation takes at this corpus: `similarity(...) >= 0.3`
over every claim, 143 ms a call. A GIN `gin_trgm_ops` index with the `%` operator returned the
same rows and took 14.4 s for 30 checks against 4.5 s without. The bench corpus is about 42
sentence skeletons repeated (`CLAUDE.md` says so), so nearly every claim shares trigrams with
every other and the index narrows nothing. It was reverted. **Whether it helps on varied text
is unknown and needs a varied corpus to measure** — the local-model corpus `CLAUDE.md`
suggests is exactly that.

## What remains

- `/weaknesses` computed from nothing is 2.1 s at 100,034 claims: reading 200,000 score
  summaries is most of it, and it is real work. Served from the page cache it is milliseconds
  until the next append. Whether to pin it to a snapshot or recompute on a schedule is the
  owner decision Stage 26 already names.
- `record_investigation` at this corpus is dominated by the duplicate check above.
- The claims API still presents each claim's card on its own (links, quarantine, topics,
  supersession): 734 statements for fifty. Called 19 times in a week.
- Grafana over these tables: `bin/grafana` (not a Compose service).
