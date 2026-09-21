# Stage 39 — The read paths ask one row at a time

**Status:** planned · tag will be `stage-39-read-path-batching`

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

## The Constitutional Test

Not required — no Article is touched, nothing is scored, displayed differently, moderated or
attributed differently. Recorded as considered: the only invariant in reach is 4, and
acceptance 5 is its guard.
