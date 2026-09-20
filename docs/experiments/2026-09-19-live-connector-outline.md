# A connected assistant outlines a two-hour transcript

**Date:** 2026-09-19 · **Node:** local development · **Commits:** `a294d98` (Stage 31),
`c76c25b` (Stage 32), plus the hourly-cap change made mid-run

## What was tried

The owner pasted a full podcast transcript (14 chapters, roughly two and a half hours,
well over 3,000 words) into a Claude chat session with the Galedra skill freshly installed
and the connector attached over OAuth. The same input had been given once before and had
produced 13 claims and no outline.

The question: with the size rule corrected and the rules moved onto the wire, does the
assistant take the outline path, and does what it records actually hold the source?

Watched from the server side throughout via `docker compose logs` filtered to MCP tool
calls and write failures. Every number below is from the database, not from the
assistant's account of itself.

## What happened

It took the outline path. `create_outline` was called fourteen times, once per chapter,
each adding a subtree under the root.

| | Previous run | This run |
|---|---|---|
| Path taken | `record_investigation` | `create_outline` ×14 |
| Sections | 0 | 62 |
| Leaves | 0 | 47 |
| Leaves with an anchor | 0 | 47 |
| Leaves with a reading | 0 | 47 |
| Readable text | 0 | 141,937 characters |
| Extraction tasks opened | 0 | 47 |

First pass, complete: **46 of 47 leaves** worked, 247 new claims, 255 placements, 762 open
checks, 311 evidence items, 345 links, 4 merges, 1,679 signed writes by the agent key, seq
798 → 3,685. One leaf was left unworked with its extraction task still open, which is the
honest way to stop: the gap is visible on the task board rather than silently skipped.

State distribution after the first pass:

> 255 claims · 206 checkable · 2 supported · 17 leans supported · 182 unresolved ·
> 1 leans contradicted · 1 contradicted · 3 insufficient evidence · 49 not applicable

`UNRESOLVED` dominating is the expected shape of one reader's pass: most claims carry a
single supporting passage, which is not enough for a directional state. The 49
`NOT_APPLICABLE` are forecasts and value judgements, correctly typed as things evidence
cannot settle. **Two claims came back contradicted by the sources**, which is the run's most
useful output and the thing a summary would never have produced.

**Stage 30 verified end to end for the first time.** `Sections::Text` at the root composes
all 47 parts into 141,937 characters, matching the stored sum exactly, in correct
depth-first document order (checked against a tree walk, not assumed). No empty readings;
leaves ran 1,018 to 4,654 characters against a 60,000 per-leaf cap.

**The three-checks-per-claim promise holds**, with caveats: attaching to an existing claim
opens no new checks and merging removes a claim without removing checks already opened
against it, so the ratio is an observation about a run, not an invariant.

## Findings

### 1. `ledger:replay` had been broken since Stage 25 — **FIXED**

`Tasks::Status` was defined inside `app/services/tasks/lease.rb`. Zeitwerk resolves a
constant from a file of the same name, so `Tasks::Status` only existed once something had
referenced `Tasks::Lease` for an unrelated reason. A web request always had. A rake task
had not, so `bin/rails ledger:replay` died on the first `TASK_RESULT` it applied.

This is the worst finding here, and nothing about the experiment caused it. **Invariant 2 —
truncate, replay, every row identical — had not been checkable for several stages**, and it
went unnoticed because the command is only run deliberately. Moved to
`app/services/tasks/status.rb`; the constant now resolves cold.

Replay itself is **still unverified**: it truncates projections before rebuilding, and the
live investigation was mid-write. Run it once the node is idle.

### 2. One `record_investigation` took 11.2s and issued 21,543 queries — **OPEN**

`Completed 200 OK in 11197ms (ActiveRecord: 2527.0ms (21543 queries, 1528 cached) | GC:
1206.5ms)`. It succeeded, so nothing is broken, but 21.5k queries for one call at ~110
claims is an N+1 of some size, most likely in scoring or placement fan-out. Only one sample
survived before the log rotated, so no frequency is claimed. Belongs in `docs/profiler/`
once there is more than one observation, per the convention that a timing without its
corpus is not evidence.

### 3. The write cap could not carry one investigation — **FIXED**

A first pass measured **34 signed writes per leaf**: about 1,600 for 47 leaves plus the
outline. The named cap was 1,000 a day, so an investigation stopped around leaf 29 and
could not resume until the next calendar day. Changed to a rolling hourly cap, named 5,000
and anonymous 500 (REVIEW-NOTES M, `ChangeAgentCapsToHourly`). Rolling rather than calendar,
because a fixed boundary lets an agent spend two caps a minute apart.

The field is written into signed `DELEGATE` payloads, so it was renamed in the log's
vocabulary too; `Ledger::Appliers::Delegate` reads either key so replay reproduces
historical rows, and rejects a payload carrying both.

### 4. `server/discover` is re-probed every turn — **OPEN**

Stage 32 set `ttlMs: 0` on the discover result for consistency with `tools/list`. The two
are not alike: tool descriptions change when edited, but supported versions, capabilities
and identity cannot change without a restart. The client therefore re-probes at every turn
boundary. Harmless at 4ms, but needless. An hour's TTL on discover, keeping zero on
`tools/list`, is the honest pairing.

Two things Stage 31 and 32 did get confirmed against a real client: `server/discover`
answered 200, and `tools/list` was re-fetched mid-session rather than cached, which is
exactly what `ttlMs: 0` is for.

### 5. No rule covers copyrighted material embedded in a source — **OPEN**

The episode contains a clip of someone else's script. `Guidance::OUTLINE` says to clean a
reading only by fixing transcription errors and paragraphing, and explicitly not to
summarise. The assistant recorded a bracketed note of what plays instead of transcribing
it — the right call, which the rules do not sanction. It reasoned past a written
instruction to a better answer, which is luck, not design: a different assistant follows
the rule and transcribes the lot.

A drafted rule exists and is not yet written: a reading may replace a passage with a
bracketed note when the passage is someone else's copyrighted work quoted inside the
source, saying what plays and how long, never what it says. Pairs with the `license` field
on this source, currently `nil`, and with the owner's open copyright decision — this run
recorded ~142,000 characters of a third-party transcript.

### 6. `Sections::Tree` counted only what it rendered — **FIXED**

**Found by the assistant, not by me.** Working the outline it called `report_bug`
(`01a0bc5f`): `get_outline` on the root reported 0 claims for the root and all 14 chapters,
while asking for a chapter directly reported its real counts.

The cause: `depth` truncated what was *counted*, not just what was *rendered*. Claims live
on leaves, branches hold none of their own, so a branch whose leaves were not loaded
reported zero — and so did the root.

```
depth=0: root=0     depth=1: root=0, all 14 chapters 0
depth=2: root=255   depth=3: root=255
```

Worse than the report suggested: this outline is two deep, so the tool's default `depth: 2`
happened to be correct. **Any outline three levels deep would under-count silently at the
default**, with nothing to indicate it. Fixed so `depth` prunes only the rendered
`children`; counts always aggregate the full subtree. Pinned by a spec verified to fail
against the unfixed code (`root reported 0 claims at depth 0`).

The same walk scored each claim individually inside the recursion — an N+1 on every page
view, growing with the outline. Now one `Scoring::Score.call_many` pass for the whole
subtree. This is the same shape as finding 2 and may be part of it.

**What this says about the watching:** I had been reporting counts straight from
`ClaimPlacement`, never through the view a person sees, so I could not have found this. An
assistant using the thing for its own purposes did, in one call. Monitoring the data is not
monitoring the product.

### 7. Self-certification is narrower than it reads — **NO ACTION NEEDED**

Asked to work verification tasks on its own outline, the assistant correctly refused: every
task belonged to claims its own principal recorded. It then described the rule as closing
off all further work under that principal, which is not so.

Self-certification blocks **task leasing** (`Tasks::Lease`) and **audits**
(`Audits::Eligibility`). It does not touch scoring: `Scoring::Calculate` never references a
principal, and evidence is weighted by `independence_group_id` — whether two pieces trace to
one origin — not by who recorded them. So `add_evidence` on one's own claims counts fully,
and the two mechanisms do different jobs: evidence moves a claim's state, verification tasks
raise review coverage.

Confirmed empirically once the evidence pass began: one claim moved from `UNRESOLVED` to
`LEANS_SUPPORTED` on same-principal evidence.

Nothing to fix in the code. The guidance could say this, since an assistant reading the
rules concluded it was more blocked than it was and offered to stop.

## What was wrong in the watching

Three misreads, all mine, recorded because an observer who gets it wrong is part of what
the run revealed.

**Sampling mid-write, twice.** I queried the database during an 11-second request and
again during a background cancellation job, and read both frozen snapshots as stalls —
once announcing a possible stale-task leak that did not exist. This system commits in large
atomic chunks; a point-in-time count taken during a write says nothing. Sample on a tool
call's completion, not its start.

**Calling a flake attributable on four data points.** It has now appeared on four different
specs (`sections_spec`, `share_card_spec`, `investigations_spec` twice at different
examples), always passing in isolation and never seed-reproducible. An intermittent suite
failure appeared twice on different examples. I stashed Stage 32, got four clean runs, and said
Stage 32 was implicated. Four clean runs against a roughly one-in-six event is nearly
worthless evidence, and eight later clean runs *with* Stage 32 contradicted it. The flake
remains real and unattributed.

**Guessing schema names three times** — `created_at` on `sections`, `claim_id` on `tasks`,
an `Evidence` model that is called `EvidenceItem`. Each cost a failed query and a
correction. Read the column list first; it takes one call.

**Reporting the data instead of the product**, which is how finding 6 went unseen through a
whole run while an assistant hit it immediately. See that finding.

**A migration applied before its code.** Renaming the cap columns while the old code was
still running broke the live investigation for about a minute until the code and a restart
caught up. On a node with an assistant actively writing, the code goes first.
