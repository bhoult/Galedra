# Stage 26 — Capacity: seeding, profiling, and the pages that scan

**Status:** in progress · tag will be `stage-26-capacity`

Built so far: `bench:seed`, `bench:report`, the first pass at `/weaknesses`, and the
profiling harness (`bench:cpu`, `bench:memory`, `bench:rss`, `bench:boot`).
Still to do: the score-cache N+1 the profile found, `claim_scores` retention, the tally
index, the load test, and the decision below about what snapshot the report answers for.

## Plan

**Tag:** `stage-26-capacity` · **Spec:** 03 §14 (scoring cost), 06 §5 (Weaknesses page),
11 §2 (two services), 14 §25 (federation readiness: replayable projections), Article XXII
(the system reveals its own weaknesses), Invariant 2 (projections are derived), Invariant 4
(deterministic, versioned scores)

Goal: know what this node can carry before it is public, and fix the three things that
fail first. Nothing here changes what the ledger records or how a claim is scored; it
changes how much of the graph a request touches, how long the score cache is kept, and
what the project can measure.

Why now: the POC has never been run against a realistic corpus. Every timing below was
taken on a development machine against 27 claims and 534 contributions, which is small
enough that an O(n) page looks instant. The numbers say the failure is not storage or
signatures but the pages that walk every row, and a cache that grows faster than the log.

### Measured baseline (2026-09-19, development machine, 27 claims / 534 contributions)

| Operation | Cost |
|---|---|
| Append one contribution (`CREATE_CLAIM`) | 32 ms, ~31/s single-threaded |
| Score one claim, warm process, no cache | 2.7 ms |
| Score one claim, cached | 0.23 ms |
| `GET /`, `/claims`, `/tasks`, `/contributors` | 10–50 ms |
| `GET /weaknesses` | **980 ms** |
| `claim_scores` rows | 829 for 27 claims (~30×), 1.7 MB, the largest table |
| Contribution row | ~3 KB |

### The three ceilings, in the order they bite

1. **`/weaknesses` walks the whole graph.** `Weaknesses::Report.call` loads every counted
   claim, scores each under the default model, and `models_disagree` scores each again
   under every other released model; `high_impact_insufficient` counts edges per claim and
   `disputed_audits` queries audits per claim. Stage 22 added `Sections::Progress.unfinished`
   and Stage 25 `Inferences::View.strained` on top. That is 36 ms per claim against 2.7 ms
   to score one: ~36 s at 1,000 claims, unusable at 10,000. The page is linked from the
   header and from Article XXII's promise, so it has to stay fast.
2. **`claim_scores` is never pruned.** It is keyed `(claim_id, snapshot_seq,
   scoring_model_id)`, so every claim scored at every distinct seq under every released
   model leaves a row carrying its full trace. Only `Ledger::Replay` and
   `RecomputeAllScoresJob` clear it, both wholesale. The cache already outweighs the log.
3. **Writes serialise.** `Ledger::Append` takes `pg_advisory_xact_lock`, which is what makes
   the sequence gap-free and the chain unbroken (02 §1.2). It is correct and stays. The
   consequence is a global write ceiling — ~31/s here, less on 1 vCPU — and a recorded
   investigation is 10–20 appends, so under one investigation per second on the
   recommended droplet whatever the thread count.

Deliverables:

- **`bin/rails bench:seed[claims]`**: generates a corpus through the real write path
  (`Ledger::Append`, not fixtures), with a realistic shape: sources held by reference,
  2–6 excerpts each, claims of mixed type, evidence links in both directions, some
  independence groups, topics, a proportion of claims in outlines, and audits on a sample.
  Refuses to run outside development and test, and refuses a log that already holds
  contributions unless `--reset` is given, as `bin/demo` does. Prints the append rate.
- **`bin/rails bench:report`**: times the pages and services that matter at the current
  corpus size (claim page, claims index, weaknesses, contributors, outline page, a
  recorded investigation, `next_task`/`submit_task`) and prints a table in the shape
  above, so a change can be compared against a recorded baseline rather than a memory.
- **Profiling, development only and off by default**: `rack-mini-profiler` with
  `stackprof` for per-request flamegraphs, `memory_profiler` and `derailed_benchmarks` for
  the 2 GB question, behind a `LEDGER_PROFILE` env flag so production never loads them.
  `pg_stat_statements` enabled on the managed database and its top queries recorded in the
  decision log.
- **`/weaknesses` bounded**: each list paginated with a hard cap, the per-claim queries
  replaced by set queries, the second model's states read from `claim_scores` rather than
  recomputed, and the whole report cached per `(snapshot_seq, model)` in Solid Cache with
  the log head as the key, so it is computed once per append rather than once per view.
  The JSON report keeps its shape and its kinds; only the number of rows changes.
- **`claim_scores` retention**: a `bin/rails scores:prune` task and an idempotent job that
  keeps the rows for the head seq, for every pinned `graph_snapshot`, and for anything
  scored in the last N days, and deletes the rest. Nothing epistemic is lost: a pruned row
  is recomputed deterministically from the log (Invariant 4), which is the property that
  makes the cache safe to discard.
- **Indexes for the queries that scan**: `Contributors::Tally` joins `contributions` to
  `agent_delegations` through `envelope->>'delegation_id'`, which no index covers; either
  index that expression or denormalise the principal onto the contribution row at append.
  `pg_stat_statements` names the rest.
- **A load test** (`k6` or `oha`, checked in under `script/`) with a realistic mix:
  mostly claim-page reads, a trickle of `record_investigation`, and a connector working
  tasks. Run against the seeded corpus on a droplet of the recommended size, not locally.
- **Findings recorded**: the capacity numbers go in `docs/HOSTING.md` §3, replacing the
  current guess that "jobs are light", with the corpus size they were measured at.

Acceptance:

1. `bench:seed[100000]` completes, and `bench:report` prints append rate and page timings;
   both are recorded in the decision log with the machine they were run on.
2. At 100,000 claims: `/weaknesses` responds in under 500 ms, the claim page and claims
   index in under 200 ms, and a recorded investigation of ten claims in under 5 s.
3. `scores:prune` reduces `claim_scores` to the retained set; every pruned claim still
   scores byte-identically on the next read, and the demo goldens and `ledger:replay` are
   unchanged.
4. The load test sustains its read mix for ten minutes on the recommended droplet without
   the queue backing up or memory exceeding the box; the numbers are in `HOSTING.md`.
5. Profiling is absent from the production image: `LEDGER_PROFILE` unset loads none of the
   gems, and `bundle list --without development` does not name them.

## Progress (2026-09-19)

`bin/rails 'bench:seed[n]'` builds a corpus through `Ledger::Append` (sources held by
reference, quoted passages, mixed claim types, links in both directions, topics, audits
on a sample) and `bin/rails bench:report` times the pages and services against it. Both
run in development and test only; the seeder warns that a corpus left in the test
database will fail the suite, which it does, because the specs expect a clean log.

Measured at 2,025 claims / 20,549 contributions (24-cpu development machine, test env,
so `Rails.cache` is the null store and every report call recomputes):

| Operation | 27 claims | 2,025 claims | after batching |
|---|---|---|---|
| `Weaknesses::Report` | 1,188 ms | 3,709 ms | **1,616 ms** |
| `GET /weaknesses` | 1,331 ms | 4,135 ms (worst 24.9 s) | 2,945 ms (worst 35 s cold) |
| `GET /claims/:id` | 91 ms | 42 ms | 76 ms |
| `GET /api/v1/claims?limit=50` | 838 ms | 468 ms | 471 ms |
| `Scoring::Score`, cold / cached | — | 6.0 / 0.2 ms | 5.1 / 0.2 ms |
| Append, unbatched | — | 48/s (21 ms) | — |
| Append, batched transactions | — | 91–101/s | — |

What the first pass changed: the three per-claim query loops in the report became set
queries (`Weaknesses::Report::Facts`), `models_disagree` now skips claims with no counted
evidence because no two models can disagree about an `INSUFFICIENT_EVIDENCE` claim
(Invariant 5), and the whole report is cached per `(seq, model, kinds, limit)`, which is
sound because a snapshot's answer never changes.

What it did not fix, and why. The remaining cost is scoring every claim under every
released model, about 4,000 cold scores at this corpus. `RecomputeAffectedScoresJob`
materialises `claim_scores` only for the claims a contribution *affected*, at that seq, and
the cache is keyed on the exact seq. Since the head seq moves with every append, a
whole-graph report at the head finds almost nothing cached, however good the query plan is.
That is not a bug in the report; it is the shape of the cache meeting the shape of the
page, and fixing it is the decision below.

Also found, not yet addressed: `GET /api/v1/claims?limit=50` spends ~9 ms a claim in
`Graph::Presenter.claim`, which since Stages 20–25 calls `Inferences::View.for_claim`,
`Sections::Tree.placements_for` and `ClaimReference.totals` once per claim. It is bounded
by `limit`, so it degrades with page size rather than corpus size, but 50 claims should
not cost half a second.

Owner decisions to record: whether `/weaknesses` should answer for the latest pinned
`graph_snapshot` rather than the head seq — snapshots are stable, so the cache and the
materialised scores would both be reusable, the page would become citable, and Article
XXII's report would stop being recomputed on every append (the alternative is a
schedule, or a score cache keyed by a validity range rather than an exact seq); the
retention window for `claim_scores` (a head-plus-snapshots
rule versus N days); whether `/weaknesses` should be computed on a schedule rather than on
demand, given it is a whole-graph report; whether to denormalise the principal onto
`contributions` at append, which adds a column to the log's own table and so wants care;
the droplet size to test against, since the answer to "how many claims" is a function of it.


## Profiling, and what it found (2026-09-20)

`stackprof`, `memory_profiler` and `rack-mini-profiler` are in the development bundle
group only, so `BUNDLE_WITHOUT=development` keeps them out of the production image, and
nothing requires them at boot: each task requires its gem when it runs, and the
middleware only appears when `LEDGER_PROFILE` is set.

- `bin/rails 'bench:cpu[weaknesses]'` — sampling profile, wall by default because much of
  the time is spent waiting on Postgres and `MODE=cpu` cannot see that. Writes a dump the
  `stackprof` CLI reads, so a frame can be chased to its callers.
- `bin/rails 'bench:memory[...]'` — what one run allocates and what it retains, by file.
- `bin/rails 'bench:rss[...]'` — resident set across N runs, with the slope taken over the
  second half, because a Ruby process grows while its heap settles and never returns the
  pages; measured from the first run, everything looks like a leak.
- `bin/rails bench:boot` — what the process holds having served nothing.

All of them, and `bench:report`, now run inside `Bench::Isolation`, which holds the
reloader, verbose query logs and log writes still for the length of a measurement. In the
first profile those three were a fifth of the samples, and none of them exists in
production. Profiling also runs with the page cache swapped for a null store, so a page
that caches its own answer is measured doing the work rather than reading yesterday's.

### Measured at 3,026 claims / 30,779 contributions (24-cpu development machine, test env)

| Operation | Median | Slowest |
|---|---|---|
| `GET /` | 4.8 ms | 105.9 ms |
| `GET /claims` | 19.7 ms | 536.3 ms |
| `GET /claims/:id` | 38.1 ms | 65.4 ms |
| `GET /api/v1/claims?limit=50` | 296.2 ms | 310.6 ms |
| `GET /contributors` | 22.2 ms | 30.9 ms |
| `GET /weaknesses` | **3,103 ms** | 29,726 ms cold |
| `Weaknesses::Report` | 2,797 ms | 3,110 ms |
| `Scoring::Score` cold / cached | 5.1 ms / 0.2 ms | |
| Append, unbatched / batched | 31.6/s / 85.7/s | |
| `claim_scores` | 10,384 rows, 18 MB | `contributions` 70 MB |

### Memory: the box is not the problem

| | |
|---|---|
| Resident set after boot, having served nothing | 126 MB |
| Settled after 300 claim-page requests | 162 MB |
| Steady-state slope | flat, 3 KB a run |

One Puma worker settles around 160 MB and does not grow, so the recommended droplet holds
several workers with room to spare. Steady-state memory is not the ceiling.

Allocation churn is. One `Weaknesses::Report` call at this corpus allocates **276 MB in
3.0 million objects** and retains none of it:

| Allocated by | |
|---|---|
| `bigdecimal` | 64.8 MB |
| `json` | 55.0 MB |
| Active Record result casting | 25.5 MB |
| `json-canonicalization` | 18.1 MB |
| `app/services/scoring/score.rb` | 7.1 MB |

That is the scoring path: every claim is scored under every released model, each score
building decimals and a canonical-JSON trace that is thrown away. The cost is garbage
collection, not residency.

### The score cache is an N+1, and it is 70% of the report

The wall profile is unambiguous. `PG::Connection#exec_prepared` is 48.5% of samples on
its own, and 70.1% of total time sits under one call site:

    ActiveRecord::Core::ClassMethods#find_by
      samples: 62 self (0.6%) / 6814 total (70.1%)
      callers: 6814 (100.0%) Scoring::Score.call

`Scoring::Score.call` opens with `ClaimScore.find_by(claim_id:, snapshot_seq:,
scoring_model_id:)`, one round trip per claim per model. A whole-graph report at the head
seq makes about 6,000 of them, and nearly all of them miss, because the head seq moves
with every append. The report pays a query to learn nothing, then computes anyway.

The fix is to look the cache up for the whole claim set in one query before scoring, and
hand the hits to the scorer, rather than asking per claim. That is a change to how
`Scoring::Score` is called, not to what it computes: the trace and the number are
untouched, so Invariant 4 holds. It is the first thing to do in the remaining work, ahead
of pagination, because it is the largest single cost and the cheapest to remove.

Not addressed: `GET /api/v1/claims?limit=50` is still ~6 ms a claim in
`Graph::Presenter.claim`. Bounded by `limit`, so it degrades with page size rather than
corpus size.
