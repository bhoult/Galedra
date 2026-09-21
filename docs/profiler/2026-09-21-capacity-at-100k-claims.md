# Capacity at 100,024 claims: the acceptance run (Stages 26 and 38)

The run `implementation/planned/stage-26-capacity.md` has been waiting for since
2026-09-19. Every earlier number in that file was taken at 27, 2,025 or 3,026 claims,
which is small enough that an O(n) page looks instant.

## Conditions

- **Corpus:** `galedra_bench` — **100,024 claims, 1,019,834 contributions**, 10.2
  contributions per claim, built through the real write path (`Ledger::Append`, not
  fixtures) by the long `bench:seed` run recorded in
  [2026-09-20-seed-write-path-decay.md](2026-09-20-seed-write-path-decay.md). Schema
  brought up to date on 2026-09-21: fifteen migrations in 3.3 s, of which Stage 38's
  watermark backfill over 100,024 claims was 2.4 s.
- **Machine:** 24-cpu development workstation, Docker Compose, postgres:16, development
  environment pointed at the bench database. `contributions` is 2.7 GB.
- **Held still:** `Bench::Isolation` — the reloader, verbose query logs and log writes —
  and the page cache swapped for a null store, so a report is measured doing the work
  rather than reading its own answer.
- **Not held still: the host.** `ollama` was serving the owner's own work throughout at
  ~95% GPU, load average around 20. **Every wall time here is an upper bound.** A figure
  that passes despite that contention passes honestly; one that fails is not conclusive on
  its own, and is marked as such. No `bench:cpu` was taken for the same reason.
- **Released models in this corpus: two** (`ledger-default@0.1.0`, `ledger-strict@0.1.0`).
  The 0.2.0 pair postdates it, so a whole-graph report scores each claim twice, not four
  times.
- **Commit:** `4322699`.

## Numbers

### The whole-graph report

| | Wall | `claim_scores` written |
|---|---|---|
| `Weaknesses::Report`, cold — cache emptied first | **663,824 ms** (11 m 4 s) | 200,023 |
| The same report after an unrelated append, under Stage 38's keying | **25,755 ms** | 0 |
| And again | 24,345 ms | 0 |
| The same report with every claim's watermark forced to the head, which is what the old key meant on every append | **663,568 ms** (11 m 4 s) | 200,024 |

The second row is the stage, and the fourth is the control: the same corpus, the same
process, the same report, with the only difference being whether the claims' watermarks say
anything. An append moves the head; under the old key that made every one of the 200,023
cached scores unaskable-for, so the next reader paid the first row again — 663,568 ms,
within 0.04% of the cold run, which is what "the cache is useless after any write" looks
like when you measure it. Under the watermark the append bore on no claim, every score was
still current, and **the report wrote nothing at all**.

### One claim

| | |
|---|---|
| Scored from cache | **0.6 ms** |
| Scored cold, cache emptied for that claim | 13.0 ms |

### The pages, from `bin/rails bench:report`

Corpus as the report prints it: contributions 1,019,835 · claims 100,024 · evidence 76,609
· links 145,663 · sources 50,034 · **tasks 0** · audits 8,350. Three runs each, median and
slowest.

| Operation | Median | Slowest |
|---|---|---|
| `GET /` | 38.4 ms | 109.6 ms |
| `GET /claims` | **48.5 ms** | 69.6 ms |
| `GET /claims?sort=references` | 3.8 ms | 4.8 ms |
| `GET /claims/:id` | **161.8 ms** | 212.9 ms |
| `GET /claims/:id?calculation=1` | 163.9 ms | 176.9 ms |
| `GET /weaknesses` | 25.7 ms | **26,300.8 ms** |
| `GET /api/v1/weaknesses` | 4.1 ms | 13.2 ms |
| `GET /contributors` | 208.1 ms | 226.2 ms |
| `GET /contributions` | 10.3 ms | 21.8 ms |
| `GET /tasks` | 2.7 ms | 8.2 ms |
| `GET /api/v1/claims?limit=50` | 320.0 ms | 360.9 ms |
| `Scoring::Score` cached / cold | 0.3 ms / 4.4 ms | |
| `Cards::ClaimCard` | 1.7 ms | 2.4 ms |
| `Contributors::Tally.top` | 193.1 ms | 194.5 ms |
| `claim_scores` | 400,043 rows, 722 MB | `contributions` 2,117 MB |

`/weaknesses` is the only row where the median and the slowest are different questions: the
first run computed and the other two read the report cache. **25.7 ms is a cached page and
26.3 s is the page.**

### Writing, and retention

| | |
|---|---|
| `record_investigation`, 10 claims, 11 contributions | **3,491.7 ms** |
| `scores:prune` | 8,329.9 ms, deleted 200,021, kept 200,032 |
| Every pruned claim rescored byte-identically afterwards | yes |

## Where the 25 seconds goes

Taken afterwards on the same corpus, with every score already cached, by timing each phase
of `compute_lists` and counting every statement by shape. **The first reading of this
number — "Ruby walking 100,024 claims to build the lists" — was wrong**, and it was wrong in
the way this codebase's performance guesses usually are: the walk is not the cost.

| Phase | Wall |
|---|---|
| Load the claim set (100,034 rows) | 270 ms |
| `Scoring::Score.call_many`, every claim a cache hit | 4,159 ms |
| `Facts` — three set queries | 1,427 ms |
| **The seven filters, over 100,034 claims each** | **247 ms, all seven together** |
| `models_disagree` — the whole corpus again under the strict model | 9,205 ms |
| **Building the entries: 2,500 rows of `Cards::Why.most_moving_addition`** | **11,986 ms** |
| Wall | **27,293 ms** |
| of which SQL | 7,683 ms (28%) |
| of which Ruby | 19,610 ms (72%) |
| Statements | 26,474 |

The statements, by total time:

| Calls | Total | Mean | Shape |
|---|---|---|---|
| 301 | 5,006 ms | 16.6 ms | `SELECT claim_scores.* … JOIN claims …` |
| 2,252 | 273 ms | 0.12 ms | `claim_evaluability_settings` by claim |
| 3,546 | 257 ms | 0.07 ms | `audits` by target contribution |
| 2,348 | 176 ms | 0.08 ms | `independence_group_assignments` by evidence item |
| 2,252 | 159 ms | 0.07 ms | `claim_placements` by claim |
| 1,700 | 110 ms | 0.07 ms | `quarantines` existence by source |
| 290 | 24 ms | 0.08 ms | `contributions` where `action_type = 'REVOKE_KEY'` |

### The three defects, all of them present

1. **Work for rows nobody asked for — 12 of the 27 seconds.** Each kind builds
   `MAX_ENTRIES` (500) entries at compute time, and every entry calls
   `Cards::Why.most_moving_addition`, ~4.8 ms each. Seven kinds is up to 3,500 of them. The
   page then **slices 25 or 50 rows off the front and throws the rest away.** The cap was
   added so a reader could not ask the node to build ten thousand rows; it did not stop the
   node building five hundred per kind unasked. Every one of the small per-row statements in
   the table above is inside those calls — that is the N+1, and it is one row at a time in
   the classic shape.
2. **Over-fetch, the same pattern Stage 38's own planning named.** `SELECT claim_scores.*`
   carries `trace`, a ~2 KB JSON document, for 200,000 rows — 5.0 s of SQL in one shape at
   16.6 ms a call, plus the Ruby to parse each one and build a `Calculate::Result` from it.
   The lists read `assessment_state`, `review_coverage`, `support_groups`,
   `contradict_groups`, `contested` and `provisional`, and **every one of those is already
   its own column on `claim_scores`**. Only `independence_unreviewed` is trace-only, and it
   is computed at score time like the rest, so it could be a column too.
3. **The corpus walk, which is what I blamed first, is 1%.** Filtering 100,034 claims seven
   times costs 247 ms in total. Loading them costs 270 ms. There is nothing to fix there.

### After the fixes

Same corpus, same conditions, `Weaknesses::Report.call(seq, limit: 50)` end to end with the
page cache off:

| | Before | After |
|---|---|---|
| Wall | 27,293 ms | **7,068 ms** |
| SQL | 7,683 ms | 3,283 ms |
| Ruby | 19,610 ms | 3,784 ms |
| Statements | 26,474 | **2,912** |
| Rows returned, and their content | 250 | 250, identical |

Four changes, all of them the same kind of thing: stop doing work nobody asked for.

- **"What would most change this" is built for the page, not for the report.** `page` fills
  it in for the rows it returns; `entry` no longer does it for 500 rows of every kind.
- **The lists read columns, not traces.** `Scoring::Score.summaries` selects the nine fields
  the lists use, so `trace` is never in the select list and Postgres never detoasts it.
  `independence_unreviewed` and `review_checks_done` became columns on `claim_scores` to
  make that possible — a cache table outside the digest, so this costs nothing epistemic.
- **`models_disagree` stopped re-reading the default model's scores**, which it already had
  in hand. That was a third of every row this report reads.
- **Summaries are built positionally**, not from a keyword hash per row. 300,000 hashes
  nobody keeps.

What is left is a floor: reading a summary for every claim under every model (~200,000 rows,
3.3 s), `Facts`, and the filters. **This is the number the owner decision should be taken
against**, and it is the kind of thing a pinned snapshot or a schedule genuinely does fix,
because it is work that has to happen and only needs to happen once per snapshot.

**This changes what the owner decision is about.** Roughly 12 s is entries nobody asked for
and roughly 10 s is reading traces nobody reads; neither needs a decision about snapshots or
schedules to remove, and both are ordinary work. What would be left is `Facts`, the claim
load and the filters — on the order of 2 s at a hundred thousand claims. Whether *that*
needs a pinned snapshot is a much smaller question, and it should be asked after the work,
not before it.

## Findings

- **`/weaknesses` does not meet Stage 26 acceptance 2 (under 500 ms at 100,000 claims).
  Status: OPEN, and most of it is ordinary work rather than an owner decision.** Cold it is
  eleven minutes; with every score already cached it is still 25 seconds. But the phase
  timing above says **~12 s of that is entries the page throws away and ~10 s is traces
  nobody reads**, and neither needs a decision about pinned snapshots or schedules. Build
  the "what would most change this" for the rows actually returned rather than for 500 per
  kind, and read the columns `claim_scores` already has instead of rehydrating a trace per
  claim, and what remains is on the order of 2 s. The owner decision — pinned snapshot, or
  a schedule — should be taken against that number, not this one.
- **The report held 4.9 GB resident. Status: PARTLY FIXED (`4322699`) — 4.9 GB → 2.7 GB.**
  `Scoring::Score.call_many` was handed all 100,024 claims at once, and `Scoring::Pass`
  then loaded every counted link of that set *with its contribution* — the widest table in
  the schema — into one object graph, while nothing at all reached `claim_scores` until
  the last claim had been scored. Watched over the eleven minutes: 1.8 GB, 2.3 GB, 4.9 GB
  and climbing. It now scores in slices of 500, each with its own pass, writing as it goes,
  so an interrupted run keeps what it computed; `spec/services/capacity_spec.rb` holds it
  to one write per slice. The same run then peaked at **2.7 GB**, which is better and still
  more than the droplet has. **What is left is the caller**: `Weaknesses::Report` holds all
  100,024 claims *and* a `Calculate::Result` for each, every one carrying its full trace —
  about 1.9 KB of JSON the report never looks at. It needs states and counts, which are
  columns on `claim_scores` in their own right. Reading those columns instead of
  rehydrating traces is the next thing to do here, and it belongs with Stage 39.
- **This contradicts `docs/HOSTING.md` §3's "memory is not the ceiling". Status: FIXED in
  that document.** The claim was measured on a steady request mix, where it is true — a
  Puma worker settles at 162 MB and stays there. It was not true of the one page that
  walks the whole graph, and 4.9 GB on a 2 GB droplet is not a slow page, it is a dead
  node. The section now says which of the two it is talking about.
- **The score cache is 2 KB a row. Status: NO ACTION NEEDED.** 100,024 scores under one
  model is 202 MB; under both models, 200,023 rows. Against a 2.7 GB log that is the ratio
  Stage 26 predicted, and `scores:prune` now keeps every claim's current score rather than
  the head seq's (Stage 38), which is a smaller and more useful set.
- **A cached score is 0.3–0.6 ms and a cold one is 4.4–13 ms at this corpus**, against
  0.2 ms and 5.1 ms at 3,026 claims. Reading a score barely moved as the corpus grew 33×,
  which is the shape you want; building its input did not, and that is Stage 39's half of
  the work. (The spread is which claim: the report's random claim has more links than the
  oldest one.)
- **The claim page is 161.8 ms and the claims index 48.5 ms. Status: MEETS ACCEPTANCE 2**,
  which asks for under 200 ms — but the claim page's slowest run was 212.9 ms, so it sits
  on the line on a workstation, which means it is over it on the droplet. Stage 39's
  finding 1 (`Contributions::Standing.accepted_at?` getting slower as the log grows) is on
  this path.
- **`GET /contributors` is 208 ms and `Contributors::Tally.top` is 193 ms of it. Status:
  OPEN.** Not named in acceptance 2, but it is the slowest ordinary page here, and it is
  one query doing the work, so it is an index or a materialised tally rather than an N+1.
- **A recorded investigation of ten claims is 3.5 s. Status: MEETS ACCEPTANCE 2** (under
  5 s), with eleven appends against a million-contribution log. The advisory lock and the
  per-append work are the cost, as Stage 26 predicted; it is the acceptance figure with the
  least margin left, and the write path is known to decay with corpus size
  ([the decay entry](2026-09-20-seed-write-path-decay.md)).
- **`scores:prune` removed 200,021 rows of 400,053 in 8.3 s, and every pruned claim
  rescored byte-identically. Status: MEETS ACCEPTANCE 3.** What it kept is each claim's
  current score under each model — the rows reads actually ask for — rather than the head
  seq's, which is the Stage 38 change.
- **The corpus has no tasks at all (`tasks 0`). Status: OPEN, and it limits this run.**
  `Bench::Seed` opens no verification tasks, so nothing here exercises the task queue, the
  lease path, `Tasks::Checks` inside scoring, or `/tasks` under load — `GET /tasks` at
  2.7 ms is an empty page, not a fast one. Any capacity claim about the work queue is
  still unmeasured.

## What changed as a result

- `Scoring::Score` scores a large set in slices (`4322699`).
- `docs/HOSTING.md` §3 carries the 100,024-claim figures and the memory correction.
- Stage 26's acceptance is recorded as **met except for `/weaknesses` and the droplet load
  test**, in `implementation/`, rather than left open with no numbers attached.
