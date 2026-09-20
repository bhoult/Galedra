# A connected assistant works an outline for the second time

**Date:** 2026-09-20 · **Node:** local development (`local.galedra.org`) ·
**Commit:** `e378fcd` · **Guidance:** `2026-09-20.3`

## What was tried

The owner gave a Claude chat session, connected over OAuth with a named token, one
instruction:

```
work open tasks in Galedra on https://local.galedra.org/sections/1623097f-53f3-8a4f-bafb-6d522b75735b
```

That outline is the Moonshots episode from the
[2026-09-19 run](2026-09-19-live-connector-outline.md): 254 placed claims, 740 open tasks.
Watched from the server side for ~40 minutes on `docker logs -f galedra-app-1`, filtered to
MCP calls, **every** request's timing and query count, page paths, refusals and errors, and
tee'd to a file. Every number below is from the database.

**Conditions worth stating, because they bound what the timings mean.** The node was not
still: `bench:seed[100000]` held the same Postgres at 85% throughout, committing ~10k
appends every ~28 minutes. Treat wall times as soft; query counts are unaffected. Everything
committed earlier that day was live under the development reloader, so this run is also the
first real exercise of the `constraints` field, `Scoring::Pass`, the `Reputation::Calculate`
fix, and the card/presenter query work.

## What happened

| | Before | After |
|---|---|---|
| Contributions | 4,003 | **4,461** (+458) |
| Claims | 288 | 292 |
| Evidence links | 508 | **581** (+73) |
| Sources | 59 | **111** (+52) |
| Bug reports | 5 (0 open) | **8 (3 open)** |
| Feature requests | 1 (0 open) | **2 (1 open)** |

Assessment states across the outline's 254 claims:

| State | Before | After |
|---|---|---|
| SUPPORTED | 4 | **13** |
| LEANS_SUPPORTED | 1 | **16** |
| LEANS_CONTRADICTED | 1 | **8** |
| CONTRADICTED | 1 | **2** |
| INSUFFICIENT_EVIDENCE | 196 | 163 |
| NOT_APPLICABLE | — | 49 |

**The assistant's own account of this matched the database on every state count.** Its
narrative numbers drifted ("10 tasks done" in one update, "six tasks" in the summary; the
server says 13), but every figure it reported about *the record* was exact. Worth knowing:
the thing it is least reliable about is itself.

### The yield comparison

The run has a clean break at **18:30:48**, when the assistant stopped taking the queue's
targets and started choosing its own.

| Route | Work | Claims moved |
|---|---|---|
| Queue-directed tasks | 13 leased, 13 submitted | **0** |
| Self-directed links, before the break | 25 links | **0** |
| Self-directed links, after the break | 48 links | **35** |

Both zeroes are measured, not inferred: no target of any of the 13 queue tasks changed
state. Of the 25 links before the break, every one landed on a `NOT_APPLICABLE` claim; of
the 48 after, **none did**.

The tool was identical throughout. The difference was target selection, which the product
never helped with and actively misdirected.

## What it found

### 1. Every refusal to a modern client is schema-invalid · **FIXED 2026-09-20** (`6ea6a04`)

Reported by the assistant, which saw what the server cannot:

> `MCP server "galedra" returned a malformed result that failed schema validation: Invalid
> result for tools/call: missing required resultType`

`Mcp::Server` decorates the success path and not the failure paths:

```ruby
[ 200, { jsonrpc: "2.0", id: id, result: decorate(result, era) } ]   # decorated
rescue Ledger::Rejected      => [ 200, tool_error(id, e.errors) ]    # NOT decorated
rescue Assistants::CapReached => [ 200, tool_error(id, [...]) ]      # NOT decorated
```

`decorate` is the only thing that adds `resultType` and `_meta` for the 2026-07-28 era, and
`tool_error` builds its own `result` hash without them. So every `Ledger::Rejected`
refusal — `CLAIM_NOT_CURRENT`, `TOO_MANY_OPS`, `OP_NOT_ALLOWED`, `NOT_FOUND` — and every
`DAILY_CAP` reaches a modern client as a protocol error. The JSON-RPC `error(...)` path is
unaffected, because it returns `error:` rather than `result:`.

**Why no test caught it.** `spec/requests/mcp_modern_spec.rb:65-66` is the only place
`resultType` is asserted, and the next line asserts `isError` is **falsey**. It tests the
success path and documents in the same breath that the error path was out of scope. Several
specs read `result.isError`; none check `resultType` beside it.

**The cost, measured.** The assistant mistyped one hex digit of a claim id
(`…b512-5a5303…` for `…b512-3a5303…`). Every call with it returned `NOT_FOUND` — and the
malformed frame swallowed the message. Seeing identical breakage across `get_claim` and
`add_evidence`, it reasoned carefully to the wrong conclusion, filed **two** bug reports
theorising about serialization, large numerics and non-UTF8 fields, and recorded that it
held "verified evidence I cannot file" for a claim that was never broken. Four words —
*"NOT_FOUND: no such claim"* — would have ended it. Its own analysis names the sharper risk:
a caller that simply retried on error **could have double-recorded** on an append-only
ledger.

**Fix:** route `tool_error` through `decorate`; add a spec asserting `resultType` on an
`isError` result.

### 2. The queue hands out work whose outcome is fixed, with no lever to refuse it · **FIXED 2026-09-20** (`6ea6a04`)

Of the first eight tasks leased, six targeted `NOT_APPLICABLE` claims, and the last six ran
consecutively. `next_task` filters on `types` and `domains` — task type and domain. Neither
can express "a claim whose state can change". The assistant identified the problem, filed a
feature request naming the cost ("I spent a real web search"), and **was handed two more**,
because asking was the only lever it had.

This is [finding 10 of the previous run](2026-09-19-live-connector-outline.md) in its
strongest form: not inferred from board priorities but a measured yield comparison inside
one session.

`Tasks::Create::NOT_APPLICABLE_FACTOR` (added earlier the same day, `44fbb4d`) stamps
priority at creation, so the 740 existing tasks are undamped and will keep doing this until
someone backfills the stored priorities. That is a board heuristic, not log data, so a
backfill is safe.

**The assistant's proposal is better than either candidate the original finding named:**
split a claim that bundles a checkable assertion with a normative one. Its example —
*"Recent Star Trek films … have abandoned the original series' morality-play format in
favour of action, **and should return to it**"* — is typed `NORMATIVE` whole, so evidence for
the descriptive half hangs off a claim that can never move. The original finding's second
candidate was to suppress such tasks, which it called "tempting and probably wrong". This
sidesteps that: don't suppress the work, fix the claim that should never have been one claim.

### 3. The outline hands out merged claims · **FIXED 2026-09-20** (`6ea6a04`)

```ruby
# Current (windowed) claims can receive links and edges.
def current_at?(seq) = counted_at?(seq) && superseded_by_at(seq).nil? && merge_at(seq).nil?
```

`Sections::Tree` filters on `counted_at?` only — its three `merge` hits are `Hash#merge` for
counts arithmetic. So a merged-away claim keeps its place in the outline, with an id and a
URL, and `add_evidence` then refuses it with `CLAIM_NOT_CURRENT`, using the very predicate
the outline declined to apply. All 4 merged claims on this node are still placed in this
outline.

Same defect class as the already-fixed bug where `next_task` leased a task whose target had
been merged. That fix closed the queue path; the outline path was never touched. **Third
instance this session of a fix that closed one route while the same fault stayed open on
another** — the `open`/`answers_wanted` reporting is the same shape.

### 4. `list_tasks` costs 3,714 queries · **FIXED 2026-09-20** (`6ea6a04`)

2,606 ms, 3,714 queries (693 cached) to return five tasks and some counts.
`Task#open_slots` is `required_assignments - active_assignments.count - submitted_assignments.count`
— two queries per task, un-memoised — and it is walked **twice** over ~844 tasks
(`select { open_slots.positive? }`, then `open.sum(&:open_slots)`), plus a
`Section.find_by` per task in `by_outline`. Three passes over the same set.

### 5. `get_outline` recomputes the whole outline · **OPEN**

2,269 ms, 3,895 queries ≈ **15.3 per claim** over 254 claims. Not an N+1: `Sections::Tree`
bulk-loads sections, placements and claims and scores through `call_many`. It is a total
score-cache miss — the cache is keyed on the exact seq, the head moves with every append,
and a writing assistant invalidates its own reads several times a session. 413 distinct
`snapshot_seq` values were cached against 258 rows useful at head.

**A number worth keeping:** the profiler's follow-up measured ~24 queries per claim cold
before that day's batching work. 15.3 is ~36% fewer, on a real corpus under a real client —
independent confirmation of `Scoring::Pass`, which the spec-level test could only show
didn't move traces.

### 6. Score-cache retention is built but never runs · **FIXED 2026-09-20** (`6ea6a04`)

`PruneClaimScoresJob` exists at `app/jobs/prune_claim_scores_job.rb` and is referenced
**nowhere else**. `config/recurring.yml` schedules `settle_lone_verdicts` and
`clear_solid_queue_finished_jobs` in production and `settle_lone_verdicts` in development;
the prune is in neither. Reachable only by running `bin/rails scores:prune` by hand. Stage
26's Decision Log is accurate about what exists and simply never says it is unscheduled, so
nobody would notice. Fix: one entry in `recurring.yml`.

### 7. The quote verifier reports false negatives · **OPEN**

Reported by the assistant, which **re-fetched the page itself** to check. Its excerpt is an
exact contiguous substring of the article's sentence; the card said "A quoted passage was
not found on the page when Galedra fetched it". Verified server-side: the retrieval is clean
(`FETCHED`, 331,009 bytes, `text/html`, no redirect) and the `NOT_FOUND` is stored in
`source_retrievals.excerpts`.

Its hypothesis (b), apostrophe normalisation, is **wrong** — `Sources::Retrieve.normalize`
already does NFKC, downcase, `tr("‘’‚‛′", "'")`, dash folding and
whitespace collapse. Its hypothesis (a) stands: the extracted body lacked the sentence.

**Supporting inference from local data:** across the node the verifier recorded
`VERBATIM=39, NOT_FOUND=14, NORMALIZED=3, UNSUPPORTED=2`. `NORMALIZED` firing 3 times in 58
checks is the tell. On real web pages the normaliser should rescue matches routinely — curly
quotes, non-breaking spaces, collapsed whitespace are everywhere. A nearly empty `NORMALIZED`
bucket means failures are not "the text differs slightly" but "the text is absent" — the
signature of JS-rendered or gated bodies. So the matcher is probably fine and the fetcher is
getting shells. That flips the fix: render the page, or make the label honest when the body
looks like a shell instead of asserting the quote was not found.

Outstanding: one outbound GET to qz.com would settle it. Not done — the owner was asked
first and the run was still live.

### 8. Smaller · **ALL FIXED 2026-09-20** (`6ea6a04`, `c366e16`)

- **`list_tasks` is not personalised.** It filters on `open_slots.positive?` and never
  applies the `taken` exclusion `Tasks::Lease.candidates` uses, so a returning assistant is
  shown work it has already submitted and tasks it will never be handed.
- **No per-result signal that a check was self-performed.** All 13 assignments were
  `self_performed`, review coverage stayed `0.00`, and `submit_task` replied "Counted now,
  and open to audit." every time. `brief()` carries no coverage either. `next_task`'s
  description does say self-performed checks never raise coverage — so the rule is stated
  once, in a channel `CLAUDE.md` itself calls cached and unreliable, and never reinforced
  while the behaviour plays out.
- **`CLAIM_NOT_CURRENT` doesn't say where the claim went.** `appliers.rb:140` renders
  `"claim is #{claim.status.downcase}"`; `Claim#merge_at(seq)&.into_claim_id` is available
  and `Graph::Presenter` already exposes it as `merged_into_id`. Secondary to finding 1 —
  the message never arrives — but worth fixing with it.
- **The refusal log records argument names, not values.** `args=claim_id,direction,…` made
  the one-character typo above undiagnosable from the server side. `CONTEXT.md` credits this
  logging with diagnosing two client-side faults; logging the offending value for a
  `NOT_FOUND` on an id field would have closed this one in seconds. Ids are not sensitive.

### 9. `server/discover`'s TTL is ignored by this client · **NO ACTION NEEDED**

Three probes in one session despite `ttlMs: 3_600_000`, set that afternoon (`1102d0d`). The
change remains correct for the payload — the old `0` was wrong — but the observable benefit
is **zero** with this client. Recorded as a measured negative rather than left implying a win.

### What worked

- The `constraints` field shipped that afternoon was read and used: *"that task was
  SUPPORT-direction only and capped at 12 operations."*
- Zero `TOO_MANY_OPS` and zero `OP_NOT_ALLOWED` across the run.
- `Guidance::WORK`'s instruction to switch when a task type stops being useful was followed
  literally, including the `add_evidence` escape route it names.
- `Reputation::Calculate` and `Scoring::Pass` carried the whole run without incident;
  `submit_task` held 153–256 queries while the corpus grew.
- Stage 17 retrieval fired (`RETRIEVE_SOURCE`), Stage 34's self-check filter held — 13
  self-performed checks, coverage unmoved at `0.00`.

## What was wrong in the watching

Six, all mine, recorded because an observer who gets it wrong is part of what the run
revealed.

- **I diagnosed the wrong layer on the refusals, at length.** The log showed
  `outcome=refused codes=CLAIM_NOT_CURRENT ms=95` — a clean refusal — so I spent two messages
  on "the message doesn't permit recovery". The message never arrived. Server-side logging
  cannot see a malformed frame, and that is exactly the gap this loop exists to cover.
- **I warned the queue would hand out unsettleable work, then wrongly retracted it.** I saw
  the first two assignments land on `UNRESOLVED` claims and concluded the leaser skips them.
  It does not. Generalised from a sample of two; the original warning was right.
- **"It guessed an id" was wrong.** It was a one-character transcription slip, which I only
  found because the assistant's second report gave me the id to test.
- **A narrow grep threw away a failure diff again** — the third occurrence of that exact
  mistake in one day. `tee` the run and grep the file.
- **I started building a trend from seven points.** The `submit_task` query series looked
  monotonic until the ninth sample came back down. It is a noisy band, not a climb.
- **I estimated the phase split by eye before measuring it**, and the measurement was
  cleaner than the estimate: the break at 18:30:48 is total, not a drift.

## The thing to take from this

Watching produced the two query counts, the unscheduled prune, and the merged-claim leak. It
could not produce finding 1, and finding 1 is the one to fix first. The server logged a
healthy refusal while the client received a protocol error, and no amount of counting rows
would have revealed the difference.

The previous run's lesson was that monitoring never asks whether a state is *deserved*. This
one adds a second: **monitoring sees what the server sent, never what the client received.**
Both gaps are closed by the same thing — an assistant doing real work and saying what
happened to it.


## What was fixed, 2026-09-20

All but two, in `6ea6a04` and `c366e16`. 397 examples green, reference scorer ALL PASS.

- **Refusals carry `resultType`.** `tool_error` takes the era and goes through `decorate`; a
  spec asserts `resultType`, `_meta` and the error text on an `isError` result, and it fails
  against the old code on exactly that assertion.
- **`CLAIM_NOT_CURRENT` names the target**, and the refusal log carries id-shaped argument
  values. The first version of that filter matched `*_id` and missed `fetch`'s bare `id` —
  caught by live traffic ten minutes after shipping, fixed in `c366e16`.
- **`next_task` gains `settleable`**, and `Guidance::WORK` (2026-09-20.4) says when to use it.
- **`bin/rails tasks:reprioritise`** backfills the damping to tasks already on the board,
  scoped to targets no model scores. **The scoping is the substance:** a full recompute also
  re-stamps every other task under today's default model, which moved 181 priorities by two
  thirds purely because the default went 0.1.0 → 0.2.0. That is a decision, not a side effect
  of a rake task. Applied here: this outline's top forty went from **39 of 40** unsettleable
  to **0 of 40**, and a second run changes nothing.
- **`list_tasks`** answers open slots for the whole set in one query, and its `next`
  suggestions leave out what this caller already holds. Deliberately *not* memoised on the
  instance — `Tasks::Lease` reads `open_slots`, creates an assignment, then reads it again,
  and a memo made the second read stale. The suite caught that, which is why the batching
  lives in a class method.
- **`get_outline` marks merged claims** with `merged_into` rather than listing them as
  ordinary open work.
- **`submit_task` reports `self_performed` and `review_coverage`**, so "did that help?" is
  answerable from the reply.
- **`PruneClaimScoresJob` is scheduled** in `config/recurring.yml`.

### Found by reviewing the older bug reports · **FIXED 2026-09-20**

Reading the 2026-09-20 02:18 report in full, rather than as a summary, was worth it twice.

It confirmed finding 3: its resolution says a task whose target is merged is cancelled on
sight because "`Claim#current_at?` already answered the question and the lease never asked
it" — and `Sections::Tree` still asks `counted_at?`. It also supplies precedent for the
`CLAIM_NOT_CURRENT` fix above, which is not a new idea here: the LEASE_EXPIRED report at
13:52 was resolved *"Not a bug, and the message was"*, and its refusal now reports how long
ago the lease lapsed and what the server clock reads.

And it surfaced a residue. That fix cancels lazily and says why — a sweep on every lease
would load every open task, which is right for the hot path. It leaves the dead ones counted
until something considers them: **10 tasks were still OPEN against merged claims**, all in
this outline, inflating the `open` and `answers_wanted` totals an assistant reads to decide
what is left. `bin/rails tasks:sweep_stale_targets` does the batch work in a batch. Applied:
10 cancelled, 0 remain, and a second run cancels nothing.

### Still open

- **Finding 5, `get_outline`'s cold recompute.** The score cache is keyed on the exact seq
  and the head moves with every append, so a writing assistant invalidates its own reads.
  Fixing it means changing what the cache is keyed on, which is a design decision about when
  a score may be reused, not a query to batch. It wants a stage.
- **Finding 7, the quote verifier.** Needs one outbound fetch to confirm the body is a shell,
  which was not taken while the run was live.

### Filed during the fixing, not yet addressed

The assistant filed five more feature requests at 19:00. One is the same class this project
keeps hitting and is worth stating here: **`Guidance` promises something the API cannot
express.** `Tasks::Types` says "a documented null search is information" and `Guidance::WORK`
sends off-queue work to `add_evidence`, which requires `%w[claim_id source excerpt statement
direction]`. A null result — "I looked and found nothing" — has a home inside a task
(`NONE_FOUND`) and no home outside one. The other four: no way to enumerate checkable claims
still at `INSUFFICIENT_EVIDENCE` (which is what drove the expensive `get_outline` calls),
`add_evidence` taking exactly one excerpt per call, and two points of unclarity about what
happens to sources added metadata-only.
