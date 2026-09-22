# Stage 42 — Meet the caller where the decision is made

**Status:** planned · tag will be `stage-42-meet-the-caller-where-the-decision-is`

**Tag:** `stage-42-meet-the-caller-where-the-decision-is` · **Spec:** 04 §3–§6 (agent
protocol), 05 §3 (signed envelopes), 06 §7 (API), Articles XIV (contributors, not
oracles), XIX (transparency over persuasion), XXII (reveal our own weaknesses),
Invariants 1 (log first), 4 (deterministic scores), 11 (untrusted text stays inert)

Goal: stop publishing rules that cannot reach the decision they are about.

## Where this comes from

`docs/experiments/2026-09-22-muse-first-foreign-agent.md` — the first run here by an agent
from neither Anthropic nor OpenAI. Meta's Muse worked roughly 400 tasks in an evening and
produced more findings about this node than any run before it, because it had never read
any of our documentation and so tested what the node actually says rather than what we
remember telling people.

One sentence holds the stage together:

> Every rule that failed was correct, well written, and served on every result. Every rule
> that worked was a schema or a refusal.

Four rules — answer a Galedra link with these tools and not a browser; there is a work
queue; change route after several nulls; put coverage on an absence — are in
`Guidance::PURPOSE`, in the MCP `instructions`, and in the descriptions of the very tools
they concern. Not one of them changed behaviour. Five refusals were repaired during the
run and every one of them changed behaviour within a call or two, because a refusal is the
only thing this node says at the moment a caller is deciding.

`Guidance` was itself built on this reasoning (Stage 31: a skill is installed once and
never re-read, so rules must ride on results). This stage carries the same argument one
step further. A result arrives *after* the call it would have corrected. What a caller
reads before deciding is the tool schema, and what it reads on being wrong is the refusal.
Those two surfaces are where a rule binds; everywhere else it is documentation.

## The work

### 1. Validate every call against the schema it was handed — the substance of the stage

`Mcp::Server::TOOLS` declares, for every tool, its properties, types, enums, `minItems`,
`maxItems` and defaults. **Nothing validates a call against any of it.**
`require_arguments!` (added 2026-09-22, `8ad9294`) checks presence and nothing more.

Every refusal that cost the run a round trip has one shape — the caller sent what the
published schema already forbids, and found out several layers down in a vocabulary it had
never been given:

| what the caller sent | what it was told |
|---|---|
| `sources[].type` outside the enum | `$.payload.source_type expected one of PRIMARY_TEXT, …` |
| `links[].strength` outside the enum | `$.payload.relevance_strength expected one of DIRECT, …` |
| `evidence[].observation_type` outside the enum | `$.payload.observation_type expected one of DIRECT_TEXT, …` |
| `links[].steps` as an array | `NoMethodError`, as an HTML 500 (`f6b9ae1`) |
| `links[].strength` as a float | `float at $.ops[7].relevance_strength: use an integer or a decimal string` |

The float is the instructive one, because it shows the ordering is structural rather than
sloppy. `Contributions::Envelope.build` canonicalises the payload **in order to sign it**,
and signing necessarily precedes applying, so `Crypto::CanonicalJson.reject_floats!` —
correctly ignorant of what any field means — always speaks before the applier's
`expected one of DIRECT, STRONG, …` can. The caller was told to send "an integer or a
decimal string" for a field whose values are five words. No amount of message-editing
downstream fixes that; the check has to happen before the envelope is built.

Validating at the tool boundary fixes every row of that table at once, **and needs no
translation table** — which is what an earlier version of this plan proposed and what this
one withdraws. The schema *is* the caller's vocabulary, so a refusal generated from it says
`answer.links[3].strength` and lists the five valid values, because that is what the schema
says. One source of truth, not two.

Shape:

- A validator over the declared `inputSchema`: types, enums, `minItems`/`maxItems`,
  required, and nested objects and arrays to full depth.
- Run in `Mcp::Server#call_tool`, before dispatch, subsuming `require_arguments!`.
- Refusals as `SCHEMA_INVALID` with a JSON-pointer path in the **caller's** vocabulary and
  the permitted values named. Never echo a value: an argument may be untrusted text
  (Invariant 11).
- No gem unless one earns its place; this is a closed, small subset of JSON Schema and the
  stack rule is not to add dependencies lightly (11 §1).
- `GET /api/v1/guidance` and the REST write path get the same treatment or an explicit note
  saying why not.

**The line this must not cross.** A validator that refuses something the server used to
accept breaks callers over a change nobody asked for. `links[].steps` already accepts a
numeric string and must keep doing so (`f6b9ae1`); the same care applies to every
`default:` in the schemas. Where the declared type is stricter than the accepted reality,
**the schema is what changes**, not the caller's experience. This needs a pass over all 28
tools before any refusal is switched on, and the acceptance test below exists for it.

### 2. Require coverage on an absence

`submit_task`'s `searched` is optional. Across Muse's first 319 results, not one carried
it; `ChatGPT for bhoult` supplied it 11 times unprompted at seq 4801–4833 and nobody has
since. So the field is usable, has been used well, and whether it is used depends entirely
on which assistant turns up.

Make it required when the outcome is an absence — `NONE_FOUND`, `NONE_MATERIAL`,
`CANNOT_DETERMINE`, `NO_CLAIMS`, `INDEPENDENT` — refusing with what it is for.

This was an owner decision through most of the run and the run weakened it into an easy
one. On its 320th result Muse reached for `searched` unprompted and **the server refused
it**, because coverage sits beside `answer` and it had put the field inside. Once the
refusal named the field's real home (`593732d`), coverage appeared within minutes. Two
figures, and both belong here: across the whole run only **20 of 196** absences carry
coverage, because the bulk of them were recorded before the fix; in every window after it,
**coverage ran at 100%** — 16 of 16, then 19 of 19, then 8 of 8. The run average measures
when we fixed it. The windows measure whether it worked. The change is therefore not one that refuses work a worker
was happy to skip; it meets a worker already reaching for it.

Accepting `answer.searched` as an alias is **done** (2026-09-22): Muse put it there four
times across the evening, separated by context resets and by dozens of submissions that got
it right, so it is a shape a worker regresses to rather than one it fails to learn. The
explicit argument still wins when both are sent. What remains here is the requirement
itself.

### 3. Names that cannot be misread as a count of your own work

`list_tasks` returns `open`, `answers_wanted`, `open_for_you` and `answers_wanted_for_you`.
The unsuffixed pair counts everybody's work and barely moves however hard one worker
labours; the suffixed pair is the one to report to a person.

**Four assistants have now read the wrong one** — three in one day in
`docs/experiments/2026-09-20-third-connector-run.md`, and Muse on 2026-09-22, which raised
it as a suspected bug after comparing `answers_wanted` against a remembered
`answers_wanted_for_you`. `Guidance::WORK` has a paragraph about precisely this. It has not
worked, and a fifth paragraph will not.

Rename the global pair so it cannot be mistaken for a personal one — `answers_wanted_all`,
`open_all`, or similar — and keep the old keys beside the new for one release with a note
in the schema description. A wire-format change, so it is listed here rather than done
quietly.

### 4. A connector description this node publishes

The routing rule ("a Galedra link is answered by these tools, never a browser") is in
`Guidance::PURPOSE`, in the `instructions`, and in the descriptions of `list_tasks`,
`get_outline`, `fetch` and `next_task`. Muse opened a browser anyway, then failed to find
the work queue, and both were reported before (`01a0c197`, `01a0c660`) against claude.ai.

The claude.ai diagnosis — that it discards `instructions` — cannot explain a different
vendor's agent doing the same. With a directory-style connector the agent decides that a
connector is *relevant* from its catalogue entry, written by whoever registered it, before
the tool list is fetched at all. **No channel this node controls reaches that decision.**

So publish the text we would want there, the way `skills/galedra.md` is published: a short
connector description on `/connect` and at `GET /api/v1/connector`, carrying the routing
rule, the `galedra:` trigger and the standing work queue, for an operator to paste into
whatever form their client gives them. It is the only lever left, and it is one we do not
currently offer.

### 5. An identity that survives a rotating address

`Assistants::Connect.for_source` keys an anonymous token `sha256(address|Date.current)`,
which assumes a caller has one address for a day. Meta's cloud egress rotates: **26 distinct
source keys across 30 tokens in two hours**, 56 `REGISTER_KEY` and `DELEGATE` contributions
written to an append-only log, none epistemic, none removable. The filer could not read the
answer to its own report — `filer_token_ids` returns `[id]` for an anonymous token — and
`waiting_on_you` could never reach it.

Named tokens fix it and that is the right answer for a worker. The open question is what an
anonymous caller behind a rotating address should get, given that the current answer costs
three permanent contributions per call and grants an identity that cannot read its own
history. Options worth weighing: mint the principal lazily on first *write* rather than on
connection; key on something the caller can present again; or say plainly at the door that
anonymous work will not be attributable and let them connect properly first.

### 6. Instructions inside the refusal, which is the channel that works

This stage's whole argument is that a refusal reaches a caller where guidance cannot. The
refusals do not yet carry what that argument implies.

**A failing call is told less than a succeeding one.** A successful `list_tasks` returns
fourteen fields including `guidance` (topic `work`) and `waiting_on_you`. A refusal returns
**two**: `errors` and `hint`. The moment a caller is most receptive — it has just been
stopped, it is about to try again, and this run shows it acts on what it reads there within
a call or two — is the moment this node says least. `Guidance` was built to ride on every
result and does not ride on the results that matter most. Put it on `tool_error`, topic
chosen exactly as it is for a success.

**The auth refusal does not name the route that actually works.** It offers adoption and
`/assistants/new`. It does not mention `POST /mcp/gal_<token>`, the URL form for a connector
screen that takes a URL and no headers — which is precisely what Muse needed on
2026-09-22, and which the owner only learned because it was worked out off the record. The
route has existed since Stage 16. A refusal about authentication should name every way to
authenticate, and the one that fits a connector form is the one a connector needs.

**A refusal should be able to point at the contract.** A `see` field carrying the tool's own
schema fragment, or the relevant guidance topic, lets a caller re-read what it broke without
another round trip. This overlaps §1 and should be built with it: once refusals are
generated from the schema, the fragment is already in hand.

### 7. Small things this run turned up

- `TOO_MANY_OPS` says "at most 12 ops" without saying how many were sent, and counts ops
  where the caller composed sources and links. An opposing-evidence find costs four ops, so
  the real budget is three sources: say that.
- `OPPOSING_EVIDENCE_SEARCH` means *opposing the claim's current lean*, so it frequently
  asks for SUPPORT. The name is misread by people holding the source — it was misread twice
  in the writing of this stage. One sentence in the objective fixes it.
- `open_for_you` exists only inside `list_tasks`. A connection that never calls it never
  learns a queue exists, however many calls it makes. `waiting_on_you` rides on every
  result for reports; the same shape would serve here.

## Acceptance

1. Every one of the 28 tools declaring an `inputSchema` refuses a call that violates it,
   with a path in the caller's vocabulary and the permitted values named — and a spec that
   walks `TOOLS` itself, so a tool added later is covered without anybody remembering.
2. **No call that the server accepts today is refused after the change.** Demonstrated by
   replaying the run's accepted `TASK_RESULT` payloads and every golden fixture through the
   validator and getting no refusals. This is the acceptance criterion that matters; the
   others are features, this one is the risk.
3. A float, an array, a bad enum and a missing required field each produce a
   `SCHEMA_INVALID` naming the field as the schema names it, before any envelope is built —
   so `CanonicalJson` never speaks to a caller again.
4. An absence outcome without `searched` is refused, `answer.searched` is accepted as an
   alias, and the refusal says what coverage is for.
5. The global counters are renamed, the old keys still answer for one release, and the
   schema descriptions say which pair a worker should quote.
6. `/connect` and `GET /api/v1/connector` serve a connector description, and
   `spec/lib/skills_spec.rb`'s rule extends to it: an operational rule must not live only
   there.
7. A refusal carries `guidance` on the same terms a success does, and a spec asserts that
   an erroring call is never told less than a succeeding one.
8. The authentication refusal names all three routes — adoption, `/assistants/new`, and the
   URL-token form — and a spec asserts each named route is one this node serves.

## Constitutional Test

To be answered in full before building, with these three flagged now:

- **Q5 (does this make the record more auditable?)** Yes for §2: an absence with its
  coverage can be judged; one without cannot be judged at all, and 319 of them are already
  recorded permanently.
- **Q6 (does this weaken any invariant?)** No. §1 moves validation *earlier* than signing,
  so nothing enters the log that would not have entered it before; Invariant 4 is untouched
  because no scorer input changes.
- **Q9 (self-certification)** Untouched. Nothing here changes who may accept whose work.

## What this stage is not

Not a rewrite of `Guidance`. The rules in it are right and several of them have no other
home — what a null is worth, when to change route, what the project is for. This stage says
only that a rule which must be obeyed *before* a call cannot live solely in something served
*after* one, and moves that specific class of rule to where it binds.

## The run this came from, in final numbers

Taken at seq 7382, after the worker was stopped.

| | |
|---|---|
| task results submitted and accepted | 453 |
| evidence items recorded | 342 |
| evidence–claim links | 340 |
| distinct claims touched | 202 |
| links that can move a state (`SUPPORT` + `CONTRADICT`) | 197 of 340 |
| links that cannot (`QUALIFY` + `NEUTRAL`) | 143 of 340 |
| absences carrying coverage, whole run | 20 of 196 |
| absences carrying coverage, every window after `593732d` | 100% |
| identity contributions before the named token | 77 |
| assistant tokens minted in one day | 43 |

States of the 202 claims it touched, under `ledger-default` at that seq:

| state | claims |
|---|---|
| SUPPORTED | 83 |
| INSUFFICIENT_EVIDENCE | 55 |
| LEANS_SUPPORTED | 34 |
| UNRESOLVED | 15 |
| LEANS_CONTRADICTED | 9 |
| CONTRADICTED | 6 |

**147 of 202 claims left insufficient evidence.** That is the number this stage is
ultimately for, and the one worth re-measuring after it is built: every item above is a
round trip a worker spent on our vocabulary rather than on a source.

## Shipped during the run, and why they are listed here

Five refusals were repaired while the worker was running, each landing live because
development reloads per request and the client re-reads `tools/list` constantly. They are
not this stage's work — they are its evidence, and the reason §1 is written the way it is.

| commit | what it changed | what happened next |
|---|---|---|
| `fb53a42` | `next_task` names the adoption URL for the token in hand | the anonymous wall became passable |
| `8ad9294` | a missing required argument says so, and names what the call did carry | `get_outline` stopped asserting things about sections nobody named; `request_feature` was filed correctly on the first retry |
| `593732d` | `searched` refusal names the field's real home | coverage went from 0 of 319 to 100% of every later window |
| `f6b9ae1` | an unexpected error answers in JSON-RPC, not as an HTML page | a crash stopped leaking the inside of the process |
| `65170f6` | `answer.searched` accepted where four sessions kept putting it | the stumble stopped recurring |

Every one of them is a schema or a refusal. That is the stage.
