# Stage 38 — A score that has not changed should not be recomputed

**Status:** planned · tag will be `stage-38-score-cache-keying`

**Tag:** `stage-38-score-cache-keying` · **Spec:** 03 §1–§7 (scoring), 02 §3 (projections),
11 §5 (layout), Invariants 2 (projections are written only by `Ledger::Apply`), 4
(deterministic, versioned scores), 17 (determinism is not objectivity)

Goal: stop the recommended way of working here from paying a full rescore on every read.

## What happens today

`Scoring::Score.call` caches in `claim_scores`, keyed on `(claim_id, snapshot_seq,
scoring_model_id)` — the **exact** seq. The head seq moves with every append, so any write
invalidates every cached score on the node, whether or not it bears on the claim being read.

`Scoring::Score.call_many` already carries the comment that says it: *"the cache is keyed on
the exact seq and the head seq moves with every append, so the report paid a round trip to
learn nothing and then computed anyway."* Stage 26 batched the queries. It did not change
what the key means.

**Measured on the dev node, 2026-09-21**, during a connected assistant's run over a 288-claim
outline:

| `list_claims` call | Wall time |
|---|---|
| warm, no writes between | 11–22 ms |
| after a `record_investigation` | 2,308 / 2,387 / 2,418 / 2,625 ms |

Five cold reads over 2.3 seconds, and the pattern is exact: the assistant writes evidence,
then reads the worklist, and **invalidates its own next read every cycle**.

## Why this got worse on purpose

Until 2026-09-21 the usual route was the task queue: `next_task` → `submit_task`, which does
not page the claim worklist. `Guidance::WORK` was then rewritten to lead with the goal —
*move checkable claims out of insufficient evidence* — and to name
`list_claims(state: "INSUFFICIENT_EVIDENCE", checkable: true)` followed by
`record_investigation` as the route that usually moves more. It does: the same assistant went
from five claims moved in eighteen leases to twelve in twenty-five minutes.

That route is **write, then read, then write**. So a keying decision that was a background
curiosity is now the standing cost of the thing every assistant is told to do. Two
independent parties raised it within an hour of the change, one of them the assistant paying
it, which is the reason this stage exists rather than a note in `docs/profiler/`.

## What this is not

**Not a correctness problem.** Every score served is right, every trace is right, and the
same `(seq, model)` still produces a byte-identical trace. Nothing here is wrong; something
here is wasteful, and those want different words.

**Not in the replay digest.** `ClaimScore` is absent from `Ledger::TableDigest::MODELS` and
is deleted wholesale by `Ledger::Replay` before it re-applies. The cache is outside the
digest, so its keying cannot move a row or snapshot hash — which is what makes this a cache
stage rather than a scoring stage.

## The decision this stage has to make

A score at seq N is a function of a bounded set of inputs. If none of them moved between N
and a later seq M, the score at M **equals** the score at N — that much is arithmetic. The
decision is what to do with the *trace*, which records `snapshot_seq` inside itself.

Three options, and the stage takes the third:

1. **Restamp** the cached trace with M. Rejected: it asserts a computation that never
   happened, at a seq nobody scored. That is the kind of small lie this project exists to not
   tell.
2. **Recompute whenever asked at a new seq**, which is today.
3. **Serve the trace with its own `snapshot_seq`, and say it is still current.** The result
   carries `snapshot_seq: N` and `unchanged_since: N` alongside the M that was asked for. A
   reader learns something true and *more* useful than a fresh number: this claim has not
   moved in the last k entries.

Option 3 turns the cache from a performance trick into a statement about stability, which is
a thing this record should be able to make anyway.

## What a claim's score actually depends on

The enumerable part, read out of `Scoring::BuildInput` rather than guessed:

- the claim's **evaluability settings** (`evaluability_at`);
- its **placements**, and the **sources of the sections** it is placed in — these decide
  `own_origins`, which is what makes provenance not corroboration (Stage 35);
- its **evidence links**, effective at the seq;
- for each link: the **evidence item**, its **source location**, and that location's
  **source** — each one's active window;
- **quarantines** on those sources;
- **audit status** of each link's contribution (`Audits::Status.challenged?` and
  `confirmed?`);
- the **independence group** assigned to each evidence item;
- **task results** on the claim (`Tasks::Checks.for`);
- and the **model** itself.

Anything outside that set cannot change a claim's score, which is the whole basis of the
stage. A missed member is the one dangerous failure: a stale score served as current, silently
and indefinitely. So the set above is not a comment — it is a spec, and acceptance 2 enforces
it by mutating each member in turn and requiring the watermark to move.

## The shape

A **watermark** on each claim: the highest seq of any contribution that could have changed its
score, maintained where projections are already refreshed rather than computed on read.

- `claims.scored_inputs_seq`, written by `Projections::Refresh` and the appliers that already
  touch these rows. Writes pay a little; reads pay nothing.
- The cache key becomes `(claim_id, scored_inputs_seq, scoring_model_id)`.
- A read at seq M looks up the watermark as of M and takes the cached row if it exists. The
  seq asked for stops being part of the key and becomes something the answer reports on.
- Prune keeps one row per `(claim, watermark, model)` instead of one per seq, so
  `PruneClaimScoresJob` gets simpler and `claim_scores` stops growing per-append. Measured on
  2026-09-20: 413 distinct snapshot seqs against 258 rows useful at head.

**The alternative, named and rejected:** leave the keying alone and make a miss cheaper. It
does not help. The miss is not slow because of query overhead — Stage 26 already batched that
— it is slow because it rescores every claim in the page from its links. Making a rescore
faster is worth doing on its own merits and does not remove the rescore.

## Deliverables

1. `claims.scored_inputs_seq`, defaulting to `created_seq`, with a backfill that sets it from
   the existing rows rather than by rescoring.
2. Maintenance of the watermark in `Projections::Refresh` and in the appliers that write the
   dependency set above; each one names which member it is maintaining.
3. `Scoring::Score.call` and `call_many` key on the watermark; the seq asked for is validated
   as before (`claim did not exist at seq`) and otherwise only reported.
4. Results carry `unchanged_since`, and `snapshot_seq` keeps the seq the trace was computed
   at. The claim page and `get_claim` say it in words: *last changed at entry N; nothing since
   has borne on it*.
5. `PruneClaimScoresJob` keyed on the watermark.
6. A `docs/profiler/` entry with before and after on a **still** corpus — the finished
   `bench:seed` corpus at 100,024 claims, with ollama quiesced and said so either way.

## Acceptance

1. A claim's probability, state and trace for a given `(watermark, model)` are byte-identical
   to what the same inputs produce today. The existing goldens and `bin/demo` are untouched,
   and the reference scorer prints `ALL PASS`.
2. **The dependency set is complete.** For each member listed above, a spec mutates exactly
   that thing, and the claim's watermark moves. A member that can change a score without
   moving the watermark fails here, because that is the failure that serves a stale score as
   current.
3. Appending a contribution that bears on **another** claim does not move this claim's
   watermark, and a read of this claim after it is a cache hit.
4. `list_claims` over a page of claims after an unrelated write performs no rescoring: the
   statement count is the same as the warm case, asserted rather than timed.
5. `bin/rails ledger:replay` produces identical row and snapshot digests before and after the
   stage. `ClaimScore` is outside the digest and stays outside it.
6. A result served from cache reports `unchanged_since` and a `snapshot_seq` no greater than
   the seq asked for, and never a `snapshot_seq` that was never scored.
7. `claim_scores` row count after a thousand unrelated appends is unchanged, where today it
   grows with every distinct seq read.

## The Constitutional Test

Answered because this touches scoring, even though it changes no value.

1. **Does it preserve the reasons?** Yes, and it adds one: a reader learns when the claim last
   moved, which is currently invisible.
2. **Could it manufacture agreement?** No. No weight, group or direction changes.
3. **Does it let identity substitute for evidence?** No.
4. **Does it hide anything?** No. The opposite: option 1 above would have hidden a recomputation
   that never happened, and is rejected for that reason.
5. **Is it deterministic and versioned?** Yes, and unchanged: same `(inputs, model)` gives the
   same trace. No new model version, because no scorer code changes — acceptance 1 is the
   guard. What changes is *when the database is asked*, never what is computed, which is the
   same line Stage 26 drew for batching.
6. **Does it double-count?** No.
7. **Is AI being treated as evidence?** No.
8. **Does reputation leak in?** No.
9. **Can it be audited and reversed?** Yes: the cache is derived, deletable, and rebuilt by
   replay. A wrong watermark is repaired by clearing `claim_scores`, which is already what
   replay does.
10. **Is anything invented?** No. A served score is one that was computed, at a seq that is
    reported honestly.
