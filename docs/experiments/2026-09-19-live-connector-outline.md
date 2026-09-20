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

### 2. Pages issue thousands of queries at 255 claims — **OPEN, characterised**

First seen as a single `record_investigation` at `11197ms / 21,543 queries`, with no sibling
samples before the log rotated. Re-arming the watch with a slow-request filter
(`Completed 2xx … in [0-9]{4,}ms`) turned one anecdote into a stable measurement, and the
culprits are **page renders, not MCP calls**:

| Path | Wall | Queries |
|---|---|---|
| `/weaknesses` | **13.5s** | — |
| `/sections/<root>` (the outline) | 3.5s | ~4,633 |
| `/claims/<id>` | 0.11s | fine |
| `/tasks` | 0.02s | fine |

Repeated samples cluster tightly — 1.8s to 5.3s, 3,071 or 4,633 queries — so this is a
structural N+1, not a cold cache. Both slow paths are **public, unauthenticated pages**, and
`/weaknesses` at 13.5 seconds is the worst thing here: it is the page Article XXII exists to
serve, and it is effectively unusable on a corpus one person made in an evening.

Note the outline page is still 4,633 queries **after** the `call_many` batching in finding 6,
so that fix helped and did not solve this. Next step is a `bench:cpu` run against this
corpus and a write-up in `docs/profiler/`, which now has more than one observation to stand
on.

**Lesson about the watching, not the code:** the first filter matched only failures and slow
*MCP* calls. It could not see a slow page, so for most of the run the worst performance
problem on the node was invisible while I reported that everything was clean. A filter that
only watches the thing you are thinking about will tell you the thing you are thinking about
is fine.

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

**Resolved by building Stage 34**, once the owner pointed out the product consequence: a
person who pays to outline a two-hour source cannot finish checking it and must wait for a
stranger who may never arrive. That is not a defensible place to leave someone.

`Tasks::Lease` applied its self-authorship guard to *every* task type, while `04 §3.1`
forbids exactly two things — auditing your own contribution, and accepting your own proposed
claim — neither of which is a task type. **The implementation was stricter than the spec it
implements**, so no amendment was needed; the code now matches the rule.

What shipped: a principal may lease and answer its own `EVIDENCE_VERIFICATION`,
`OPPOSING_EVIDENCE_SEARCH` and `QUALIFIER_CHECK`; independence grouping and inference review
stay closed, as do audits. Each assignment records `self_performed` at lease time rather than
deriving it later, because principals merge and a fact about what happened must not be
recomputed. `Tasks::Checks.for` filters self-performed results **before the scorer sees
them**, so they cannot touch `review_coverage` and the trace shape is unchanged — no new
model version for a feature that must not move the number. The share line now reads
`N claims · N self-checked · N independently checked`, and the claim page says in words that
a check by the author does not raise coverage.

A second guard had to be split to make this work. Stage 19's "whoever asks for a blind check
does not perform it" was keying on `created_by`, which is set both when someone deliberately
calls `open_task` and when verification opens routinely alongside a recording. Those are
different things and `created_by` cannot tell them apart, so tasks now carry
`blind_requested`, true only for the deliberate case.

### 8. Shipping a behaviour change without its instructions — **FIXED, third occurrence**

Stage 34 changed what `next_task` does. Two places still told assistants the opposite:

- the `next_task` tool description — *"never one on a claim your own principal recorded"*
- `Guidance::OUTLINE` — *"never leases a check on its own claim"*

Caught only because the owner asked whether a fresh session would now work the tasks, which
prompted a check of what the assistant would actually be told. Nothing in the suite failed:
377 examples passed against instructions that contradicted the code they described.

**This is the third occurrence of one pattern in this project**, and it is worth naming as a
class rather than three incidents:

1. Stage 30 added a `reading` field; the `create_outline` tool schema never gained it, so the
   feature was unreachable through a connector.
2. The size rule was corrected in the skill; `record_investigation`'s description carried no
   ceiling at all, so a connector reading schemas never saw it.
3. Stage 34 opened self-checking; `next_task` and the guidance still forbade it.

Each time the code was right and the thing an assistant reads was wrong, and each time the
tests passed, because **nothing tests that an instruction matches the behaviour it
describes**. `spec/lib/skills_spec.rb` pins the size rule across surfaces, which is the
shape of the answer, but it only covers the one rule that has already bitten. The general
version — a check that every behavioural claim in a tool description is exercised by a spec
— does not exist and is not obviously cheap to build.

The mitigation that has actually worked is Stage 31: guidance riding on every tool result
reaches a connected assistant on its next call, so a correction lands without a reinstall.
That shortens the window; it does not close it. **Any stage that changes what an assistant
may do should treat the tool description and the guidance as part of the change, not as
documentation of it.**

Verified afterwards by simulating the lease against the live corpus, inside a transaction
rolled back so the node was not disturbed: `LEASED: EVIDENCE_VERIFICATION
self_performed=true`, against 742 open checks.

## Phase two: the self-check pass (Stage 34 in the wild)

With Stage 34 built, a fresh session was told *"work the open tasks in Galedra on \<outline
URL\>"* — the instruction Galedra prints on the outline itself. Baseline: 254 claims, 762
open checks, 0 self-checked, 0 independently checked, seq 3685.

**Stage 34 works.** The same principal that recorded the claims was handed
`EVIDENCE_VERIFICATION` on its own claim, marked `self_performed=true`, where the previous
session was refused. The corrected instructions reached it, so finding 8 did not recur.

### 9. The self-check counter could not see the most common check — **FIXED**

The first submitted self-check was recorded correctly and **counted as nothing**:
`self_for` returned `{}` and the share line still read `0 self-checked`.

`Tasks::Checks::CHECK_FOR` maps task types to *checklist item names*, and
`EVIDENCE_VERIFICATION` is not a checklist item — it contributes evidence links rather than
a checklist flag. Both `self_for` and the share-line split counted through that map, so the
most numerous check type, 254 of the 762, was invisible to the figures built to report it.
Now keyed on assignments and every task type.

Written, tested and committed hours earlier; the specs passed because they exercised
`OPPOSING_EVIDENCE_SEARCH`, which *is* in the map. **A spec that only tests the case you
were thinking about confirms the case you were thinking about.** The live run found it in
one submission.

### 10. The queue spends its effort on claims evidence cannot settle — **OPEN**

Every one of the first 17 self-checks landed on a `NOT_APPLICABLE` claim — a forecast, a
value judgement, a prophecy. Measured against the queue:

| | Share |
|---|---|
| `NOT_APPLICABLE` claims in the corpus | 49 of 254 (19%) |
| Open tasks targeting them | 147 of 762 (19%) |
| **Top 40 tasks by priority targeting them** | **38 of 40 (95%)** |

The top 40 all carry identical priority (1.5), so the tie breaks on `created_at` and the
ordering is effectively arbitrary — it just happens to surface unresolvable claims first.

This is not free. Each check costs an assistant a real reading and the person real money,
and a qualifier check on a `FORECAST` cannot change its state: `NOT_APPLICABLE` carries no
probability by Invariant 5. Nineteen per cent of the queue is work whose outcome is fixed
before it starts.

Not worthless — a check might find a claim was mistyped, that something recorded as
normative is empirical after all — but it should be the last of the queue, not the front of
it. Two candidate fixes, neither taken here: weight `Tasks::Priority` down for claims
already scored `NOT_APPLICABLE`, or do not open `QUALIFIER_CHECK` and
`OPPOSING_EVIDENCE_SEARCH` on them at all. The second is tempting and probably wrong,
because the type is a judgement that can be revised, and closing the route to revising it
makes the mistake permanent.

**Verified once the pass reached checkable claims.** The first seventeen self-checks all
landed on `NOT_APPLICABLE` claims, which carry no `review_coverage` to move, so they proved
nothing. At 59 self-checks the pass reached claims that do:

```
checkable claims carrying a self-check: 12
any self-check leaking into the scorer:  0
distinct coverages among them:  {"0.00" => 12}
```

This is a real test rather than a vacuous one. Coverage is satisfied checklist items over
declared ones, so one self-answered `QUALIFIER_CHECK` reaching `task_checks` would have
pushed those claims to 0.25 or above. Twelve claims, twelve self-checks, coverage still
zero: **the filter holds where it could have failed.**

### 11. The write path degrades under the pass — **OPEN, and it is two problems**

Requests climbed through the pass and plateaued around **15.5–16s**, twice in succession at
~7,500 queries, against the 3.5s outline page measured a few hours earlier on the same
corpus. Nothing failed — every one returned 200 — but a 15-second write is past where a
connector waits patiently, on a node with one user and one outline.

Watching the shapes separates them into two problems that would need different fixes:

| Shape | Example | Where the time goes |
|---|---|---|
| **Query-count N+1** | 5.4s, **8,866 queries**, views 666ms | database |
| **View rendering** | 9.1s, 4,360 queries, **views 5,667ms** | templates |

Batching queries will not touch a slow template, and caching a template will not touch an
N+1. Recording them as one entry — "pages are slow" — would have pointed the profiling work
in one direction and missed half of it.

Counts cluster in bands (~3,100, ~4,200, ~7,500, ~8,900) rather than scattering, which
suggests two or three call sites each scaling with a different collection, not one runaway
loop. `bench:cpu` against a **still** corpus will separate them; log lines will not.

Deliberately not chased during the run: profiling a moving corpus describes neither the
before nor the after, and `bench:seed` truncates the log in development, which would destroy
the very run being measured.

### 12. A refusal was logged without saying what was refused — **FIXED**

The first rejection of the self-check pass appeared as:

```
mcp_call tool=submit_task outcome=refused codes=SCHEMA_INVALID ms=10 …
```

A code and nothing else. `log_call` has a `detail` field; the `Ledger::Rejected` rescue
mapped the codes and dropped the `path` and `detail` the error already carried. So the
assistant was told exactly which field was wrong and **the operator watching the log was
not** — a client failing repeatedly would be undiagnosable from the server side.

Both are safe to record: the path is a JSON pointer and the detail a server-authored
message, neither carrying claim text, and `log_call` truncates anyway. The next refusal,
minutes later, read:

```
detail="$.payload.retrieved_at expected RFC 3339"
```

Which led straight to finding 13. **An observability fix that pays for itself on its first
occurrence is the cheapest kind there is**, and this one had been missing since Stage 14.

### 13. The timestamp format was not where an assistant reads it — **FIXED**

Two refusals, both a malformed `retrieved_at` while creating a source during an
opposing-evidence search. The format was stated — as a bare `"RFC 3339"` in the tool
schema, with no example — and `Guidance` did not mention it once.

That is the wrong place twice over. "RFC 3339" without an example invites a wrong guess
(offset or `Z`? space or `T`?), and an assistant working tasks receives the `work` topic,
which never touched formats at all. The rule now sits in `STANDING`, which every topic
carries, with a concrete example.

Same shape as findings 8 and 9: the code was right, the thing an assistant reads was
incomplete, and nothing failed a test.

### The flake, finally named

The intermittent suite failure was recorded at session start as
`spec/requests/api/v1/investigations_spec.rb:67`. Through this session it also hit
`sections_spec`, `share_card_spec`, `claim_pages_spec` and `investigations_spec:127`, and at
the end surfaced again at **:67** — the original. Still unattributed, still passing in
isolation and on every re-run, never seed-reproducible.

Twice I lost its name to my own filters, grepping only for the count line. **A filter narrow
enough to look tidy is narrow enough to discard the thing you needed** — the same mistake as
the monitor that could not see slow pages (finding 2) and the log line that dropped its
detail (finding 12). Three instances, one habit.

## Phase three: a resumed session reports three faults

The assistant filed two bugs and two papercuts. All four were real; only two were bugs.

### 14. A merged claim's checks were leased forever — **FIXED**

`next_task` kept handing out checks on claims that had been merged away. The appliers refuse
those with `CLAIM_NOT_CURRENT`, there is no way to submit against the survivor, and releasing
one returns it to the head of the queue — so the same unworkable task arrived three times and
**blocked every filter that reached it**. A livelock, worked around only by filtering to a
different domain.

Confirmed in the live data: 12 open tasks across 4 merged claims, three types each, with 5
`RELEASED` assignments recording the loop. `Claim#current_at?` already existed and checks
exactly this — counted, not superseded, not merged — and the lease simply never consulted it.

Such a task is now cancelled where it is found, with `TARGET_NOT_CURRENT`. Cancelled rather
than reassigned to the surviving claim, because `MERGE_CLAIMS` is reversible: if the merge is
invalidated the claim is current again and fresh tasks open, whereas moving a task would have
to be moved back. Cancelled *lazily*, as candidates are considered, rather than swept — the
sweep would load every open task on every lease, and this corpus already has 839.

### 15. The expired lease was not a bug; the message was — **FIXED (the message)**

Reported as a lease refused using a timestamp four hours in the future. The data says
otherwise:

```
expired assignments: 1
  leased 02:27:13Z   expiry 06:27:13Z   held 4.0h
LEASED assignments with a past expiry: 0
```

Exactly one expired assignment on the node, leased at **02:27:13Z** — the moment this log
already records the previous run stopping with one lease open. It sat through the pause, aged
out on schedule, and the resumed session submitted against it. Correct behaviour throughout.

The assistant's "~02:35Z" was its own clock, stale from before the pause. **An assistant has
no reliable sense of wall time**, so `expired at 06:27:13Z` reads as a future instant and
becomes a bug report. The message now carries how long ago it lapsed, the server's own clock,
and what to do about it. Same shape as finding 12: the fact existed and was not written where
the reader was.

**A wrong turn worth recording.** Seeing a container report 02:54 and a host report 13:55, I
proposed clock skew between them. Measuring all four clocks — host, container, Rails,
Postgres — showed them identical to the second. The two readings were eleven hours apart in
wall time and I had read elapsed time as skew. The hypothesis was confident, cheap to test,
and wrong; testing it cost one command and would have cost a day of chasing if left.

### 16. `excerpt: "packet"` resolved to nothing — **FIXED**

`submit_task`'s schema promised `excerpt: "packet"` for the task's passage. `QUALIFIER_CHECK`
carries no passage, so `location` was nil, `"packet"` mapped to nil, and validation failed
downstream with *expected a UUID* — sending the caller hunting for a malformed id it had
never sent. It now says plainly that this task type has no passage and what to cite instead,
and the tool description no longer promises what only one task type can deliver.

### Not filed, still worth fixing

`OPPOSING_EVIDENCE_SEARCH` caps at **12 ops in total** — sources plus excerpts plus evidence
plus links — not 12 of each, so a four-source answer is refused. The cap is real and sensible;
it is simply nowhere an assistant reads before hitting it. **OPEN.**

### What worked

The law domain answered *"the only open tasks are on claims your own principal recorded"*.
Conflict of interest held exactly where Stage 34 left it: routine checks opened to their
author, the rest closed.

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
failure appeared twice on different examples. By the end of the session it had also hit
`claim_pages_spec`, making five. I stashed Stage 32, got four clean runs, and said
Stage 32 was implicated. Four clean runs against a roughly one-in-six event is nearly
worthless evidence, and eight later clean runs *with* Stage 32 contradicted it. The flake
remains real and unattributed.

**Guessing schema names three times** — `created_at` on `sections`, `claim_id` on `tasks`,
an `Evidence` model that is called `EvidenceItem`. Each cost a failed query and a
correction. Read the column list first; it takes one call.

**Reporting the data instead of the product**, which is how finding 6 went unseen through a
whole run while an assistant hit it immediately. See that finding.

**Mangling a spec file with a bad heredoc escape.** A Python replacement searched for
`"\\nend"` — a literal backslash — found nothing, and silently truncated the last character
of the file, turning the closing `end` into `en`. Ruby's `-c` reported *Syntax OK* because
the result still parsed. Two further edits were needed to work out what had happened. An
assertion on the search succeeding would have caught it at once, which is what the other
replacements in this session had and this one did not.

**Repeating a mistake I had already written down.** The heredoc escaping error above —
`"\\nend"` searching for a literal backslash and truncating a spec file — happened a second
time, hours after I recorded it here along with the note that an assertion on the search
would have caught it. I had not added the assertion. Writing a lesson down is not the same as
acting on it, and the file this time was the very spec proving the livelock fix.

**A migration applied before its code.** Renaming the cap columns while the old code was
still running broke the live investigation for about a minute until the code and a restart
caught up. On a node with an assistant actively writing, the code goes first.
