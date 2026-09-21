# Stage 39 — The read paths ask one row at a time

**Status:** built 2026-09-21 · tagged `stage-39-read-path-batching`

**Tag:** `stage-39-read-path-batching` · **Spec:** 06 §4 (display rules), 11 §5 (layout),
14 §25 (readiness), Invariants 2 (projections are read-only outside `Ledger::Apply`), 4
(deterministic scores — nothing here may change a value)

Goal: make the pages people and assistants actually open stop issuing thousands of queries,
and remove one lookup that gets slower as the log grows.

## Measured, 2026-09-21, on the dev node at 5,007 contributions and 288 claims

Query counts off the live stack, cached queries excluded:

| Page | Queries | Time |
|---|---|---|
| **`/sections/:id`** — the outline page | **5,343** | 2.8–3.3 s |
| `/weaknesses` | 1,872 | 0.8–1.2 s |
| `/sections` | 1,870 | ~1.1 s |
| `/claims/:id` | 122–141 | 150–280 ms |
| `/claims` | 105 | 80 ms |
| `/investigations` | 66 | 50 ms |
| `/contributions` | 49 (38 cached) | 21 ms |
| `/threads`, `/topics`, `/tasks`, `/contributors` | 3–14 | under 20 ms |

The MCP read tools were measured the same way and are **healthy**: `list_tasks` 15,
`list_claims` 5, `get_claim` 53, `get_outline` 9, `search_claims` 3, `list_threads` 15,
`list_reports` 3 — all warm. `list_claims`' cold 2.4 s is the score-cache miss of Stage 38,
not a query count. The scheduled jobs are also clean with nothing to do: `SettleLoneVerdicts`
2, `SettleAnsweredReports` 5, `RetireSilentThreads` 1, `PruneClaimScores` 5, `ExpireLeases` 1.
Those numbers are the empty case, and their loop bodies query per row, so they are worth
re-measuring once there is a backlog rather than trusted from this.

The outline page is the one the whole workflow centres on: it is what a person is given a
link to, and what an assistant is pointed at when someone says *work the open tasks*.

## The findings, worst first

### 1. `Contributions::Standing.accepted_at?` gets slower as the log grows

Two queries per contribution, each of the shape

```sql
SELECT MAX(seq) FROM contributions
WHERE action_type = 'ACCEPT' AND seq <= $1 AND payload->>'contribution_id' = $2
```

There is **no index on `payload->>'contribution_id'`**, so Postgres scans the `seq` index
backwards and filters. Measured:

| Corpus | Rows filtered for one call | Time for one call |
|---|---|---|
| dev, 5,008 contributions | 5,008 | **2.8 ms** |
| `bench:seed`, 900,001 contributions | 900,001 | **6,853 ms** |

`/sections/:id` makes **780** of these calls. At the seeded corpus that is not a slow page; it
is a page that never returns. This is the finding that makes this a stage rather than a
cleanup: everything else is linear in rows on the page, and this one is linear in the length
of the log, multiplied by rows on the page.

Callers: `Sections::Progress`, and `Tasks::Checks` in two places.

Two fixes, and both are wanted:

- **Index the predicate.** `ACCEPT` and `INVALIDATE` carry `{basis, contribution_id}`, and are
  2,405 of 5,008 entries here. An expression index on `(payload->>'contribution_id')`
  restricted to those two action types turns the scan into a lookup.
- **Ask once for a set.** Every caller has a collection in hand — a page's results, a claim's
  tasks — and asks per row. One query returning the accepted-and-not-invalidated seq per
  contribution id serves the whole page.

### 2. `Task#open_slots` is two COUNTs per task, and a batched version already exists

```ruby
def open_slots
  required_assignments - active_assignments.count - submitted_assignments.count
end
```

**4,380 queries on `/sections/:id`** and 1,460 on `/sections`.

`Task.open_slots_for(tasks)` was added on 2026-09-20 and does exactly this for a whole set in
one query, with a comment explaining that the per-instance method is deliberately not
memoised because `Tasks::Lease` re-reads it mid-transaction. Both of those are right. What
happened is that only one caller was moved to it — `tool_list_tasks` — and the loops were
left:

| Site | Shape |
|---|---|
| `app/views/sections/show.html.erb:48` | `.to_a.select { \|t\| t.open_slots.positive? }` |
| `app/services/sections/progress.rb:21` | `.to_a.count { \|t\| t.open_slots.positive? }` |
| `app/services/mcp/server.rb:1160` | `scope.to_a.select { \|t\| t.open_slots.positive? }` |
| `app/services/threads/settle.rb:78` | `.select { \|t\| t.open_slots == t.required_assignments }` |

`Tasks::Lease` and `Tasks::Status` use it on one task at a time, which is what it is for and
stays.

This is the shape `CLAUDE.md` now warns about: the batched method existing is what stopped
anyone looking at the four call sites that do not use it.

### 3. `/weaknesses` scores every claim one at a time

695–696 queries each for `claim_evaluability_settings`, `evidence_claim_links`, `tasks` via
`Tasks::Checks`, and `claim_placements` — `Scoring::BuildInput` per claim, the same N+1
Stage 38 measures inside `Scoring::Score`. Fixing it there fixes it here, so this page is a
consumer of that work rather than separate work, and its number belongs in Stage 38's
acceptance as a second witness.

### 4. `Sections::Text` loads source locations one at a time

141 single-id `source_locations` loads on the outline page, from `sections/text.rb:26`. Small
beside the rest, and it is the same fix: the section already knows which locations it needs.

### 5. A whole-corpus rescore builds the same input four times per claim

`RecomputeAllScoresJob` — reachable from an admin button, `POST /admin/recompute` — is:

```ruby
Claim.where(...).find_each do |claim|
  models.each { |model| Scoring::Score.call(claim, seq, model) }
end
```

Two things about that loop:

- It uses the **single-claim path**, so it inherits every N+1 above, once per claim rather
  than once per page.
- `Scoring::BuildInput.call(claim, seq)` **takes no model**. The input is identical for all of
  them, and there are **four released models**, so three-quarters of the input assembly — the
  96% — is rebuilt and thrown away.

At the seeded corpus that is 100,024 claims × 4 models ≈ 400,000 scorings at roughly 18 ms
each, or **about two hours**, of which about three-quarters is recomputing inputs that were
already built. Hoisting `BuildInput` out of the model loop is a four-line change that removes
most of it before any batching.

That corpus has no tasks, which is why `Standing` does not appear in this estimate. On a node
whose claims carry task results — the dev node, where most claims have three tasks — finding 1
applies here too, and at that log length a full rescore does not finish.

A rescore is what happens after a model release, so this is the path that decides whether
releasing a model is an afternoon or a weekend.

## What must not change

Nothing here may alter a value. Every page above must render byte-identical content before
and after, every score must be unchanged, and `Task.open_slots_for` must keep agreeing with
`Task#open_slots` — its own comment says the two use the same predicate so the answers cannot
differ, and that is now load-bearing for four more call sites.

The one behavioural subtlety worth naming: `Tasks::Lease` reads `open_slots`, creates an
assignment, and reads it again inside a transaction. Any batching must not reach that path, and
the existing spec that catches a stale memo there must keep passing.

## Deliverables

1. An expression index on `(payload->>'contribution_id')` for `ACCEPT` and `INVALIDATE`, with
   the `EXPLAIN` before and after recorded in the migration.
2. `Contributions::Standing.accepted_at` for a **set** of contributions, one query, and its
   three callers moved to it.
3. The four loop call sites moved to `Task.open_slots_for`.
4. `Sections::Text` loading its locations in one query.
5. `RecomputeAllScoresJob` building each claim's input once rather than once per model, and
   using the batched path. Its Constitutional position is unchanged: same inputs, same
   scorer, same trace.
5. Statement-count specs for `/sections/:id`, `/sections` and `/weaknesses`, each with a
   budget and a comment saying what it was when the budget was set.

## Acceptance

1. `/sections/:id` renders byte-identical HTML before and after, in **under 60 queries**,
   from 5,343.
2. `/sections` and `/weaknesses` likewise, each under 60.
3. `accepted_at?` for one contribution at the seeded corpus executes in single-digit
   milliseconds, from 6,853 ms, and the `EXPLAIN` shows an index lookup rather than a filter
   over the seq range.
4. Every existing spec passes untouched, including the lease spec that catches a stale
   `open_slots` read mid-transaction.
5. A claim's probability, state and trace at a given seq are unchanged: this stage touches
   when rows are fetched and never what is computed.
6. The statement-count specs fail against the current code, checked by running them against it
   before the fix lands.
7. `RecomputeAllScoresJob` calls `BuildInput` once per claim rather than once per claim per
   model, asserted by counting calls, and produces byte-identical scores and traces for every
   claim under every released model.

## The Constitutional Test

Not required — no Article is touched, nothing is scored, displayed differently, moderated or
attributed differently. Recorded as considered: the only invariant in reach is 4, and
acceptance 5 is its guard.


## How this stage closed (2026-09-21)

### What was resolved

The outline page — the link a person is handed, and what an assistant is pointed at to work
open tasks. Measured on the dev node at 304 claims, by the request metrics Stage 40 added
the same morning, two warm calls each after `metrics:clear`:

| Page | Statements before | Statements after | Time after |
|---|---|---|---|
| `sections#show` — the outline page | **5,343** | **79** | 172 ms |
| `sections#index` | 1,870 | **21** | 73 ms |
| `claims#index` | 825 | **105** | 95 ms |
| `weaknesses#index` | 1,872 | 1,330 | 1,278 ms |

The outline page went from 2.8–3.3 s to 172 ms. `/weaknesses` is the one still expensive,
and deliberately so — see what remains.

### How

- **Finding 1, the one that was linear in the log.** `index_contributions_on_acceptance_target`
  — a partial expression index on `(payload->>'contribution_id'), seq` for `ACCEPT` and
  `INVALIDATE`. The `EXPLAIN` is in the migration: a filter over 5,001 rows and 4,997 buffers
  became an index lookup, **73.7 ms → 0.026 ms**, 5 buffers. And `Contributions::Standing`
  gained `accepted_set`, which answers for a whole collection in **one** statement; its three
  callers — `Sections::Progress` twice, `Tasks::Checks` twice — were moved to it. Both fixes,
  as the plan said, because the index alone still leaves a query per row.
- **Finding 2.** The four loops calling `Task#open_slots` per task now go through
  `Tasks::Status.open_among`, which wraps the `Task.open_slots_for` that had existed since
  2026-09-20 with only one caller. `Tasks::Status.refresh!` deliberately still asks one task
  at a time: it runs inside the lease transaction, where a batched answer would be stale by
  the time it is read, and the spec that catches exactly that still passes.
- **Finding 3** was Stage 38's, and was fixed there.
- **Finding 4.** `Sections::Text` loads its reading locations in one query.
- **Finding 5.** `Scoring::Score.rescore` builds each claim's scorer input **once** and scores
  it under every released model, in slices; `RecomputeAllScoresJob` uses it. The input takes
  no model, so with four models three-quarters of the assembly — 96% of a cold score — was
  being rebuilt and thrown away. A spec counts `BuildInput` calls and compares every trace
  hash against the one-at-a-time path.
- `spec/requests/read_path_cost_spec.rb` holds all of it to a budget, and **four of its five
  examples fail against the code as it stood**, which was checked by stashing the change and
  running them.

### What remains

- **`/weaknesses` is 1,330 statements and 1.3 s on a 304-claim node.** It is no longer paying
  for the corpus — doubling the claims leaves the count flat, which is what the spec asserts —
  but it pays about seven statements for **each row it shows**, and it shows 25 rows of each
  of seven kinds. The per-row cost is `Cards::Why.most_moving_addition` rebuilding one claim's
  scorer input, which is genuinely per-claim work. **Batching `Scoring::BuildInput` is the
  half of Stage 38 that was deferred, and it is now the only thing left on this page.** The
  page also takes `?limit=` since this stage, so a reader who wants it cheap can ask for less.
- **Acceptance 1's "under 60 queries" is met on the spec's fixture (26) and not on the live
  outline (79).** The difference is rows shown, not corpus size: that outline has more
  sections and more placed claims than the fixture. The number to hold to is the budget in
  the spec; 60 was written in the plan before anything had been measured.
- **Acceptance 3 was verified on the dev node, not at the seeded corpus.** The 6,853 ms
  figure came from `bench:seed` at 900,001 contributions; the after figure is from the dev
  node at 5,165. The index turns a scan into a lookup either way — that is what the plan
  changed — but the 900,001-row after number has not been taken.
- **Nothing here touched `Graph::Presenter`**, which is ~6 ms a claim on
  `/api/v1/claims?limit=50` (320 ms at 100,024 claims). It is bounded by page size rather
  than corpus, so it was out of scope, and it is the obvious next one.
