# The weaknesses page at 3,000 claims

**Date:** 2026-09-19 · **Stage:** 26 · **First run with a profiler rather than a stopwatch**

## Conditions

| | |
|---|---|
| Corpus | 3,026 claims · 30,779 contributions · 2,318 evidence items · 4,357 links · 1,528 sources · 237 audits |
| How it was built | `bin/rails 'bench:seed[3000]' RESET=1 BATCH=250`, every row through `Ledger::Append` |
| Environment | test, in the app container |
| Machine | Linux, 24 cpu, development workstation. **Not** the target droplet |
| Held still | reloader, verbose query logs, log writes; page cache swapped for a null store |
| Ruby | 4.0.7 |

The machine matters more than usual here. A 24-core workstation flatters every number
below, and the recommended droplet has a small fraction of that. Read these as the shape
of the problem, not as the capacity answer. The capacity answer needs the load test on a
real droplet, which is still outstanding.

## Timings

| Operation | Median | Slowest |
|---|---|---|
| `GET /` | 4.8 ms | 105.9 ms |
| `GET /claims` | 19.7 ms | 536.3 ms |
| `GET /claims?sort=references` | 2.4 ms | 2.9 ms |
| `GET /claims/:id` | 38.1 ms | 65.4 ms |
| `GET /claims/:id?calculation=1` | 32.3 ms | 48.5 ms |
| `GET /contributors` | 22.2 ms | 30.9 ms |
| `GET /contributions` | 12.9 ms | 13.1 ms |
| `GET /api/v1/claims?limit=50` | 296.2 ms | 310.6 ms |
| `GET /weaknesses` | 3,103 ms | 29,726 ms |
| `Weaknesses::Report` | 2,797 ms | 3,110 ms |
| `Scoring::Score`, cold | 5.1 ms | 6.2 ms |
| `Scoring::Score`, cached | 0.2 ms | 0.4 ms |
| `Cards::ClaimCard` | 3.1 ms | 3.9 ms |
| `Contributors::Tally.top` | 17.2 ms | 17.8 ms |
| Append, unbatched | 31.6/s | 31.6 ms each |
| Append, batched | 85.7/s | |

Storage: `claim_scores` 10,384 rows for 3,026 claims, 18 MB. `contributions` 70 MB.

## Memory

| | |
|---|---|
| Resident set after boot, having served nothing | 126 MB |
| After one warm claim-page request | 152 MB |
| Settled after 300 requests | 162 MB |
| Steady-state slope | flat, 3 KB a run |

One Puma worker settles around 160 MB and stops. The slope is taken over the second half
of the run: a Ruby process grows while its heap settles and never hands the pages back, so
growth measured from the first request always looks like a leak and never is.

Allocation is a different story. One `Weaknesses::Report` call allocates **276 MB across
3.0 million objects** and retains none of it.

| Allocated by | |
|---|---|
| `bigdecimal` | 64.8 MB |
| `json` | 55.0 MB |
| Active Record result casting | 25.5 MB |
| `json-canonicalization` | 18.1 MB |
| `app/services/scoring/score.rb` | 7.1 MB |
| `app/services/weaknesses/report.rb` | 4.1 MB |

## Findings

**1. The score cache is an N+1, and it is 70% of the report.** · **FIXED** (`Scoring::Score.call_many`)

The wall profile is
unambiguous. `PG::Connection#exec_prepared` is 48.5% of samples on its own, and chasing the
dump to its callers lands on one line:

```
ActiveRecord::Core::ClassMethods#find_by
  samples:    62 self (0.6%)  /  6814 total (70.1%)
  callers:
    6814  (100.0%)  Scoring::Score.call
```

`Scoring::Score.call` opens with `ClaimScore.find_by(claim_id:, snapshot_seq:,
scoring_model_id:)`. The report scores every counted claim under every released model, so
that is about 6,000 round trips, and nearly all of them miss, because the cache is keyed on
the exact seq and the head seq moves with every append. The report pays a query to learn
nothing, then computes anyway.

**2. The box is not the ceiling, and that was worth knowing.** · **NO ACTION NEEDED**, recorded in `docs/HOSTING.md` §3

The question that started
this stage was whether the node fits the recommended droplet. On steady-state memory the
answer is comfortably yes: 162 MB a worker, flat. Nothing accumulates across 300 requests.
What costs is garbage collection from the churn in finding 1, not residency.

**3. BigDecimal and canonical JSON are the churn, and they are not a bug.** · **WON'T FIX**, by the reasoning below

Half the
allocation is decimals and the canonical-JSON trace that every score builds and the report
throws away. That is Invariant 4 being paid for: the trace is what makes a score
reproducible by hand. It is worth reducing by scoring fewer claims, not by making scoring
cheaper and less honest.

**4. Ruled out: a leak.** · **NO ACTION NEEDED**

300 consecutive claim-page requests grow the process by nothing
once the heap settles. This was the first thing checked and it is worth recording as a
negative, so nobody spends a day on it.

**5. Not the headline, but real:** · **OPEN**, see the follow-up at the end of this entry

`GET /api/v1/claims?limit=50` costs 296 ms, about 6 ms a
claim in `Graph::Presenter.claim`, which since Stages 20–25 calls `Inferences::View.for_claim`,
`Sections::Tree.placements_for` and `ClaimReference.totals` once per claim. It is bounded by
`limit`, so it degrades with page size rather than corpus size.

**6. A method note, learned the hard way.** · **FIXED** in the harness, and corrected further below

The first profile of this page was nearly
worthless twice over. Development's reloader, verbose query logs and log writes were a
fifth of the samples, and the warm-up run populated the page's own cache so the profile
measured cache hits. Both are now handled by `Bench::Isolation`, but the lesson generalises:
a profile of a cached page that does not defeat the cache is measuring the cache.

## What changes as a result

- **Done:** batching the score-cache lookup, as `Scoring::Score.call_many`. One query for
  the set and one chunked insert for what the cache did not hold, instead of two per claim
  per model. It changes how `Scoring::Score` is called, not what it computes; the spec
  asserts the traces and their hashes are byte-identical to scoring one claim at a time,
  so Invariant 4 is checked rather than assumed.
- **Still open, unchanged by this run:** whether `/weaknesses` should answer for the latest
  pinned snapshot rather than the head seq. That is the structural fix, and batching the
  lookup does not remove the need for it. A pinned snapshot does not move, so both the
  report cache and the materialised scores become reusable.
- **Not doing:** making scoring allocate less. The decimals and the canonical trace are the
  reproducibility guarantee.


---

## Correction, same day, after acting on finding 1 · **APPLIED**

Finding 1 says the cache lookups "nearly all miss, because the head seq moves with every
append". That is wrong about the run that produced the 70% figure. The profile ran the
report three times at one seq: the first populated the score cache and the other two read
it, so two thirds of the samples were the **warm** path, where the report does nothing but
look scores up.

The 70% is a real cost and batching removes it, but it describes repeated views at one
snapshot, not the first view after an append. The cold path is dominated by something else
entirely, measured below. Both are true at different moments, and the original entry
conflated them.

The method note in finding 6 was right about the page cache and wrong to stop there: the
score cache is a table, not `Rails.cache`, so running an operation more than once warms it
even with the page cache disabled. A cold measurement has to clear both.

## Follow-up: what the cold path actually costs · **FIXED 2026-09-20**

Statements rather than samples, on the development corpus of 27 claims. Small, but the
ratio per claim is what matters and it does not improve with size.

| | Queries |
|---|---|
| Scoring 27 claims, cold, before any of this | 805 |
| After memoising audit state within one pass | 675 |
| After preloading link and audit contributions | **644** |
| One cold `Weaknesses::Report` over the same 27 claims | 2,005 |

About 24 queries a claim, flat as the corpus grows: at 3,000 claims a cold report is on the
order of 220,000 statements. Where they go:

| Source | Count over 27 claims |
|---|---|
| `Contribution Load` | 185 |
| `IndependenceGroupAssignment Load` | 60 |
| `Quarantine Exists?` | 55 |
| `Audit Load` | 55 |
| `Audit Exists?` | 50 |

**The shape of it.** `Scoring::BuildInput` asks, for every counted link on every claim: is
this source quarantined, is this link challenged, is it audit-confirmed, and what
independence group is its evidence in. Each is its own statement, and `challenged?` costs
two on its own, because it looks for a key-compromise window and then for the latest live
audit. Multiply by links, then claims, then released models.

**What was done, and why only this much.** Two changes that carry no risk to the answer:
audit results are memoised for the length of one scoring pass, keyed by seq so nothing
outlives the snapshot it was true for, and the contributions those checks read are
preloaded rather than fetched one at a time. Together, 20% fewer statements with no logic
changed, and the goldens confirm the traces are identical.

The structural fix is to batch those four per-link lookups across the whole claim set, the
way the score cache now is: one query for compromise windows, one for audits by target, one
for quarantines, one for independence assignments. That is a refactor of the path the whole
project's correctness rests on, guarded only by the golden tests. It is recorded here as
the next piece of work rather than attempted at the end of a session.

**Done 2026-09-20, three of the four.** `Scoring::Pass` bulk-loads quarantines, audits by
target and key-compromise windows for a whole set, in the same block-scoped thread-local
shape as `Audits::Status.memoized` and for the same reason: the answers are a function of
the log up to a seq, and the log does not move while a pass runs. Outside a pass every
lookup falls back to the query it replaces, so the single-claim path is unchanged.

**The fourth was left alone on purpose.** An evidence item's independence group reads
`order(accepted_seq: :desc).first`, and two assignments accepted at one seq would be a tie
that SQL breaks arbitrarily — so grouping one sorted query could pick a different row and
move a trace. Audits cannot tie (one audit per contribution, one contribution per seq, so
`created_seq` is unique) and neither can revocations, ordered by `seq`. That distinction is
the whole reason three were safe and one was not, and it is why this was not "batch the four
lookups".

**What guards it.** A spec builds a graph where all three fire — an audited link, a
quarantined source, several claims — scores it one at a time and again batched, and compares
`trace` and `trace_hash` byte for byte, because Invariant 4 is the property at risk. It also
counts statements, and was checked against the unbatched code, where it fails with 5
quarantine queries where it expects at most 1. Full suite 392 green; the reference scorer
prints ALL PASS.

## Finding 5, quantified · **PARTLY FIXED 2026-09-20**

`Graph::Presenter.claim` issues **37 queries per claim**. Quarantine, reference totals,
evaluability, section placements, inferences, topics, supersession, merges and two evidence
counts are each asked separately, so a fifty-claim page is on the order of 1,850 statements.
It is bounded by page size rather than by corpus size, which is why it has waited. It is the
same shape of problem and wants the same fix.


## Finding 5, what is actually left · **OPEN**

The six separate counts in `Graph::Presenter.claim` — four directions, the total, and the
pending count, all against the same relation — are now one grouped count plus the pending
one. Measured on a fixture claim with four links: **43 statements before, 39 after.** A spec
holds the 39 as a ratchet and prints the breakdown when it is exceeded.

**Do not read this as fixed.** 39 is still far too many for something a page renders fifty
of. The measured breakdown, which is new here and was the point of taking it:

| Source | Statements |
|---|---|
| `ClaimEdge Load` | 6 |
| `EvidenceClaimLink Load` | 5 |
| `SourceRetrieval Load` | 4 |
| `EvidenceItem Load` | 3 |
| `Inference Load` | 2 |
| `ClaimMerge Load` | 2 |
| `Claim Load` | 2 |
| `EvidenceClaimLink Count` | 2 |
| `ClaimScore Load` | 2 |

Two of these are per-link N+1s with a named home. `SourceRetrieval Load` is 4 on a claim with
exactly 4 links: `Cards::ClaimCard` asks `SourceRetrieval.latest_for(location.source_id, seq)`
once per counted link. `ClaimEdge Load` is 6 on a claim that has **no edges at all**, so
something is asking repeatedly for nothing — most likely the card's downstream counting.

Each wants its own change and its own before-and-after, the way the scoring pass got one.
What this entry now has that it did not is the list, measured rather than guessed, so the
next session starts from where the statements actually go instead of from "the presenter is
slow".