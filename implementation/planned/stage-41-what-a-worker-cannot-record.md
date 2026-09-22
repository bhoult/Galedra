# Stage 41 — What a worker finds and cannot record

**Status:** planned · tag will be `stage-41-what-a-worker-cannot-record`

**Tag:** `stage-41-what-a-worker-cannot-record` · **Spec:** 03 §4 (counted links), 04 §3–§6
(agent protocol, task packets), 06 §2 (reads), 02 §3.2 (sources and versions), Invariants 4
(deterministic, versioned scores), 7 (AI is never evidence by itself), 9 (no
self-certification), 11 (untrusted text stays inert), Article XXII (the system reveals its
own weaknesses)

Goal: when a check finds something, let it be recorded — and when it cannot be, say what to
do instead at the moment of the refusal.

## The run this comes from

2026-09-22, 00:00–00:19 UTC. A ChatGPT session working open tasks on the Moonshots outline
(`1623097f`), watched from the server side throughout.

| | |
|---|---|
| Entries appended | 402 (head 5182 → 5584) |
| Claims recorded | 8 new; 21 moved out of insufficient evidence (130 → 109) |
| Tasks answered | 4, with 730 open tasks and 1,990 answers still wanted at the end |
| Reports filed | 1 bug, 2 feature requests; 1 earlier bug **closed by its filer** |
| Pages opened in a browser | **none** |

Corrections it recorded along the way: 26,000 registered *builders* rather than teams in the
Build with Gemini XPRIZE; over 2,500 Future Vision submissions with 65 semifinalists and five
finalists; Fedorov's proposed *physical* resurrection rather than digital ancestor
simulation; more precise wording for Smart's transcension hypothesis and the Champion equity
proposal; and Nvidia's $99bn of equity investments plus a separate $25bn of commitments as of
2026-07-26, from the Form 10-Q.

**Three things that were fixed hours earlier held**, and are recorded here so they are not
re-litigated: the routing rule reached it before its first call (report `01a0c660`, closed by
the filer at 00:07 with *"the pre-call tool descriptions were visible"*); `waiting_on_you`
carried its own unfinished business across a session boundary; and no read cost it more than
a few hundred milliseconds, where the previous run paid 2.3 s after every write.

## The findings

### 1. The worklist offers work that the write path refuses

`list_claims` returns every claim placed in the section. It filters on assessment state and
checkability and **never consults `Claim#status`**, so a claim that has been merged or
superseded is offered like any other. Taking one and writing to it fails:

```
CLAIM_NOT_CURRENT: claim is merged into a12ea91c-a14d-89c2-ae9a-6c8a4b8e21de
```

Measured on that outline: **8 of 254 placed claims are not current** — 4 MERGED, 4
SUPERSEDED — so roughly one pick in thirty is a wasted round trip. Reported as `6cc5282e`.
The work is not lost: it belongs to the claim the old one merged into, which appears in the
list on its own account if it still needs evidence.

### 2. A check that finds an omission cannot quote the source that shows it

`QUALIFIER_CHECK` allows `CREATE_EVIDENCE, LINK_EVIDENCE, CREATE_CLAIM, CREATE_CLAIM_EDGE,
SUPERSEDE_LINK` — and not `CREATE_SOURCE` or `CREATE_SOURCE_LOCATION`. So a worker that finds
a material qualifier in a document nobody has quoted yet cannot record it:

```
OP_NOT_ALLOWED at $.payload.ops[0].op: CREATE_SOURCE is not in allowed_ops …
```

**The sibling task type already allows it.** `OPPOSING_EVIDENCE_SEARCH` permits
`CREATE_SOURCE` and `CREATE_SOURCE_LOCATION`, for the same reason: evidence of an absence is
rarely already on the node. A qualifier is the same shape — if the omitted baseline were
already quoted, it would not be an omission. Reported as `131d8cda`; it gave the lease back
rather than submit something wrong, which is the right instinct.

### 3. The tool it needed already exists, and nothing said so

It found what it judged to be two wrongly-counted links, tried to supersede them inside the
task, and was refused:

```
TARGET_MISMATCH: only the packet's counted links can be superseded
```

It asked for "a standalone supersede_link tool that accepts the link IDs" (`62372ecd`).
**`revise_link` is that tool** — it takes a `link_id` from `get_claim`'s evidence, revises
direction, strength or steps, records a reason, and makes someone else's link a *proposal*
rather than a change. `NEUTRAL` is a direction, so a link that should not be counted at all
can be neutralised. None of that was reachable from where it was standing, because the
refusal names the rule and not the remedy.

This is the third time in one night that **the node knew the answer and did not say it at the
moment of the decision** — the other two being the browser-routing bug and the reports it did
not know were waiting. The packet boundary itself is right and should stay: it is what stops
a worker rewriting parts of the graph nobody asked it to look at.

### 4. A worker that disagrees with a determination does not reach for a thread

Stage 37 built exactly the mechanism for this — a disagreement about *how* something was
recorded, settled by three principals, opening work without touching a score. It was never
used. `threads_open` sat at 3 for the whole run while the assistant filed a feature request
about a tool refusal instead. The thread route is in `Guidance::THREADS`, which arrives on
every result; it is not in the refusal, which is where the decision is made.

### 5. A revised web page is counted as evidence against what it used to say

The concrete case behind finding 3, and the sharpest thing in the run. Claim `0491ac36` —
*"OpenAI's Navier-Stokes announcement carried a disclaimer that the team cannot rule out that
other teams' work was incorporated into the training…"* — reads **CONTRADICTED at 0.1419**:

| Direction | Source | Read |
|---|---|---|
| SUPPORT STRONG | `simonwillison.net/2026/Sep/8/on-navier-stokes/` | contemporaneous |
| SUPPORT MODERATE, WEAK | the recorded video | — |
| **CONTRADICT DIRECT** | `openai.com/index/navier-stokes-solution/` | **2026-09-20** |
| **CONTRADICT STRONG** | `openai.com/index/navier-stokes-solution/` | **2026-09-20** |

OpenAI published on 8 September and revised the page on 10 September. Both contradictions
are readings of the **revised** page, taken on the 20th, counted against a claim about what
the announcement said on the 8th. The contemporaneous source supports the claim. The scorer
did exactly what the links told it; the fault is in the determination.

**The record already holds what is needed to see this.** `source_locations` carry the source,
`sources` carry `retrieved_at` — 2026-09-20 19:05 for both contradicting readings — and the
table already has **`previous_version_id` and `lineage_key`** columns for exactly this
relationship. Nothing uses any of it. A claim about a document at a point in time is a
common shape, not an exotic one: every "X said Y" claim about a living web page has it.

### 6. The node cannot say which tool is expensive

Stage 40's metrics recorded the run, and the first thing they show is a limit of their own:

| action | calls | mean | max | statements/call | over threshold |
|---|---|---|---|---|---|
| `mcp#create` | 102 | 223 ms | 2,170 ms | **259** | 36 |
| `bug_reports#index` | 16 | 14 ms | 17 ms | 12 | 0 |

**259 statements a call on average, and every MCP tool is the same action**, so
`list_claims` and `record_investigation` are averaged together and neither can be blamed.
The samples say the shape: ~475 statements with only ~65 ms of database time, so it is Ruby
issuing round trips, not Postgres struggling — the same signature as everything Stage 39
fixed on the read paths, now visible on the write path. Nobody would notice it from wall
time, and nobody would have thought to profile it.

## What must not change

- **The packet boundary.** A task answer may touch what the packet names. Widening that
  silently would let a worker rewrite graph nobody asked it to look at, and would weaken the
  blind-check design.
- **Invariant 9.** Nothing here lets a principal certify its own work.
- **Invariant 4.** Finding 5's remedy must not change a score except through signed
  contributions that are visible as such; a scorer that started weighing `retrieved_at`
  would be a new model version, not a patch.

## Deliverables

1. `list_claims` returns current claims only, and says so in its description. A claim that
   has moved is not silently dropped: the response names the current id when the caller asked
   for a specific one.
2. `CREATE_SOURCE` and `CREATE_SOURCE_LOCATION` added to `QUALIFIER_CHECK`'s allowed ops, with
   the reasoning recorded against `Tasks::Types`: evidence of an omission is rarely already on
   the node, which is why `OPPOSING_EVIDENCE_SEARCH` already permits both.
3. **Refusals name the remedy.** `TARGET_MISMATCH` points at `revise_link` and at
   `open_thread`; `OP_NOT_ALLOWED` names the ops that *are* allowed and the tool that does the
   rest; `CLAIM_NOT_CURRENT` names the current claim. A rule about what to do next belongs
   where the refusal happens, not only in guidance that arrived before the question existed.
4. A decision, and then work, on **claims about a document at a point in time**. Options, in
   increasing cost: record the reading date beside a counted link so a reader sees a
   contradiction dated after the claim's own date; use `previous_version_id` and `lineage_key`
   to make a revision a distinct source; or let a claim name the version it is about. The
   first is display, the second is projection, the third is schema — and only the third is a
   scoring change. **This is an owner decision.**
5. Per-tool request metrics: record `mcp#<tool>` rather than `mcp#create`, so a heavy tool
   can be named. `Mcp::Server` already knows the name at the point `log_call` runs.
6. The Navier–Stokes determination gets a thread, whatever is decided about 4, so the caveat
   lives on the claim rather than in a chat transcript.

## Acceptance

1. `list_claims` never returns a claim whose status is not ACTIVE, asserted against a fixture
   holding one merged and one superseded claim; and taking any id it returns and writing to it
   does not raise `CLAIM_NOT_CURRENT`.
2. A `QUALIFIER_CHECK` answer that creates a source, quotes a passage, and links it as a
   qualifier is accepted; the same answer is still refused the ops that remain disallowed.
3. Every refusal named in deliverable 3 carries a `remedy` naming a tool that exists, asserted
   by a spec that fails if the tool named is not in the registry.
4. A worker that disagrees with a counted link can reach `open_thread` from the refusal, and
   a spec asserts the thread's subject may be an `EvidenceClaimLink`.
5. `request_tallies` distinguishes tools: after a run of mixed calls, the table holds a row
   per tool and no row named `mcp#create`.
6. Scores are unchanged by 1, 2, 3 and 5 — these touch what may be recorded and what is said
   when it may not, never what is computed. Deliverable 4, if it changes scoring, arrives as a
   new model version with its own goldens.

## The Constitutional Test

Answered because deliverable 4 reaches scoring and deliverable 2 widens what a worker may
write.

1. **Does it preserve the reasons?** Yes, and deliverable 4 adds one: when a reading post-dates
   the claim it bears on, a reader can see that.
2. **Could it manufacture agreement?** No. Widening `QUALIFIER_CHECK`'s ops lets a worker add a
   source and a qualifier link; both are signed, both are audit-visible, and neither escapes
   independence grouping.
3. **Does it let identity substitute for evidence?** No.
4. **Does it hide anything?** No. Deliverable 3 makes the node say *more* at the moment it
   refuses, which is the opposite.
5. **Is it deterministic and versioned?** Yes for 1, 2, 3, 5 — none of them touches the
   scorer. Deliverable 4 is the exception and is gated: a scoring change means a new model
   version and regenerated goldens, never a patch to an existing one.
6. **Does it double-count?** No. Two readings of the same page at different dates are already
   one source lineage; if deliverable 4 splits them, independence grouping must keep them in
   one group, and that is part of its acceptance.
7. **Is AI being treated as evidence?** No.
8. **Does reputation leak in?** No.
9. **Can it be audited and reversed?** Yes. Every remedy named in deliverable 3 produces a
   signed contribution; `revise_link` on someone else's link is a proposal, not a change.
10. **Is anything invented?** No. Finding 5 is a mis-weighting of real readings of a real
    page, and the fix is to record what the node already knows about when they were read.
