# Stage 42 — Meet the caller where the decision is made

**Status:** built 2026-09-23 · tag `stage-42-meet-the-caller-where-the-decision-is` · §5a waits on the owner

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

### 2. Require coverage on an absence — done

`submit_task`'s `searched` is optional. Across Muse's first 319 results, not one carried
it; `ChatGPT for bhoult` supplied it 11 times unprompted at seq 4801–4833 and nobody has
since. So the field is usable, has been used well, and whether it is used depends entirely
on which assistant turns up.

**Done** (2026-09-22): required when the outcome is an absence — `NONE_FOUND`,
`NONE_MATERIAL`, `CANNOT_DETERMINE`, `NO_CLAIMS`, `INDEPENDENT` — refused with what it is
for. Checked in `Ledger::Appliers::TaskResult` rather than where the answer is composed, so
a caller holding no lease is told *that* first: the deeper refusal comes before the lesser
one. The example agent and the spec fixtures supply it by default, so a worker that has
just done the search writes a sentence rather than meeting a wall.

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

### 5. An identity that survives a rotating address — done, in the half that grants nothing

`Assistants::Connect.for_source` keys an anonymous token `sha256(address|Date.current)`,
which assumes a caller has one address for a day. Meta's cloud egress rotates: **26 distinct
source keys across 30 tokens in two hours**, 77 `REGISTER_KEY` and `DELEGATE` contributions
written to an append-only log, none epistemic, none removable. The filer could not read the
answer to its own report — `filer_token_ids` returns `[id]` for an anonymous token — and
`waiting_on_you` could never reach it.

**Done** (2026-09-22): `introduce_yourself` lets an assistant say what it is called, who
makes it and which model it is, and take a token of its own. The token is **anonymous-tier**,
exactly as a caller with no token is: `require_delegation!` still refuses the task queue, and
the reply carries the adoption link that is still the only way through. Nothing was granted
that a caller without a token did not already have; what changed is that the caller stopped
being keyed by an address it cannot keep. It is bounded at five mints per address per day —
a mint costs three signed entries in a log that cannot forget them — and the bound is keyed
on `mint_source_key`, deliberately not `source_key`, because writing a self-minted token
into the column `for_source` searches would hand the next anonymous caller from that address
somebody else's credential. `spec/requests/introduce_yourself_spec.rb` holds all of it,
including that the minted token remains `anonymous?` and is still refused at `next_task`.

**Owner decision, taken the same evening: a self-minted token may work the queue.** The rule
was never that a human must be in the loop for each answer — it was that an answer has to be
answerable to somebody, and an address-keyed token is not somebody: it is everyone behind
that address today, so a result recorded under it names nobody who could be asked about it. A
self-minted token is a stable identity that keeps its own history and can be adopted, queried
and revoked. Invariant 9 is untouched; a principal still cannot accept its own work.

Two things had to come with it.

**Where a token came from is now said outright, not inferred.** `self_minted?` first read
`mint_source_key`, which exists to bound how many tokens one address may take — deciding what
a token may do from a side effect of how we count them is how a privilege ends up somewhere
nobody intended. `origin` is its own column, set once at the mint: `ADDRESS` (everyone behind
one address that day), `CONNECTOR` (an OAuth grant or API mint with nobody signed in),
`AGENT` (took its own token), `USER` (a person's).

**Owner decision, same evening: a connector may work the queue so long as it can be
identified for scoring.** That condition is now a checkable property rather than a hope.
`kin_key` — renamed from `mint_source_key`, because a column named for its first use is one
the next reader misjudges — records where a token came from: the address digest for a
self-mint, `oauth:<client_id>` for a grant. A token with one can be told apart and grouped;
a token without one cannot, so it is refused rather than quietly counted. `ADDRESS` is
refused always: it is a bucket, not a somebody, and nothing recorded under it answers for
itself.

**Five tokens from one address were five principals.** A task wants three independent
answers from three principals, and `introduce_yourself` gives each token a fresh anonymous
principal — so one actor could have been a quorum for its own work, which Article XII exists
to prevent. `Tasks::Lease.kin_principal_ids` now counts every principal sharing a
`mint_source_key` as one, for leasing and for "has this principal already answered". Adopted
and account-held tokens carry no mint source and are unaffected.

### 5a. What remains of the identity question

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

### 7. Discovery — partly done

A probe of every path an agent might try unprompted found almost nothing. `/mcp` answers
405, which is a real signal to something already looking, and the OAuth documents name the
endpoint as "Galedra MCP" — but `/.well-known/oauth-protected-resource` is a path you check
*after* a 401 from a resource you have already found, so it confirms rather than discovers.
`/llms.txt`, an MCP manifest, an agent card, `/.well-known/ai-plugin.json`: all absent. And
the HTML root carried no machine-readable pointer at all — no `<link rel>` to the API, the
guidance or the tools — so an agent that fetched the page, which is exactly what Muse did,
found nothing in it suggesting there was anything else to call.

**Done** (2026-09-22): `/llms.txt` is served, generated from `Ledger::Node.url` and
`Guidance::VERSION` so it cannot name a stale address or version, and the layout carries
`<link rel>` pointers to `/llms.txt`, `/api/v1/openapi` and `/api/v1/guidance`.
`spec/requests/discovery_spec.rb` asserts every path it names is routed, that it answers
with this node's own address rather than one written down in the file, and — the guard that
matters — that it **points at the guidance instead of copying it**, failing if any topic's
text starts appearing there. A second copy of the rules is the one that goes stale, which is
why `Guidance` exists at all (Stage 31).

**Also done** (2026-09-22): the owner's three paths — a person in the browser, an agent
handed a URL, a connector in a chat client — were served by one page and two of them badly.
The landing page said "give your assistant one address" and **never named the address**, and
`/assistants/new` mints a token for somebody who already knows what to do with one. There is
now a visible card on the landing page telling an assistant it is reading a rendering,
naming the endpoint and pointing at `/llms.txt`; and `/connect`, which tells a person how to
connect theirs, covering all three credential forms and carrying the paste-ready connector
description §4 asked for.

The notice is a collapsed `<details>` at the top of the landing page, and the Help menu now
carries three entries where it carried one: how to connect an assistant, mint a token, and
"What Galedra is" — because signed in the home page is the dashboard, so the introduction
and the agent notice were unreachable without signing out.

**Collapsed, never hidden.** A `display:none` block would reach agents just as well, and was
considered and rejected: it is cloaking, a page saying different things to different readers,
which is the thing this project exists to argue against (Article XIX); and it is
structurally a prompt injection, which Invariant 11 takes seriously enough that we should
not be teaching agents such blocks are legitimate. Content inside `<details>` is in the
document and converts to text whole, so a person sees one line and an agent sees all of it.
`spec/requests/discovery_spec.rb` fails if the rule ever becomes `display: none` or
`visibility: hidden`.

**It has to be visible text, and that is measured rather than assumed.** This page was
fetched the way an agent fetches it, before the change: *"I did not receive actual HTML
markup or `<link rel>` tags… No HTML comments were visible."* A markdown conversion drops
`<head>` and comments mechanically. Fetched again afterwards, the card came back verbatim
with its URLs intact. One caveat worth carrying: a general question about the page produced a
summary that omitted the card, and a pointed one reproduced it exactly — **delivery is
reliable, salience is not**, which is why `/llms.txt` is the real target and the card only
has to be a signpost to it. The spec asserts the notice survives tag stripping
and sits in the first 8% of the page's text — it is at 3.8%, immediately after the nav — on
the reasoning that what reaches an agent is whatever survives somebody else's summary.

**Remaining:** `/.well-known/mcp.json` or whatever shape the MCP discovery manifest settles
into. No ratified spec yet, so serving one now is a guess — but a cheap one, next to the
OAuth documents that already work, and worth revisiting when the shape is fixed.

### 8. Small things this run turned up

- `TOO_MANY_OPS` says "at most 12 ops" without saying how many were sent, and counts ops
  where the caller composed sources and links. An opposing-evidence find costs four ops, so
  the real budget is three sources: say that.
- `OPPOSING_EVIDENCE_SEARCH` means *opposing the claim's current lean*, so it frequently
  asks for SUPPORT. The name is misread by people holding the source — it was misread twice
  in the writing of this stage. One sentence in the objective fixes it.
- **`search_claims` needs every word of the query** (`plainto_tsquery` ANDs them), so one
  word the claim does not use empties the full-text match and leaves only the trigram
  fallback. Measured 2026-09-22 on bug report `91bee9ac`'s own query, *"Trump ban CNN Politico
  MS NOW White House press"*: 1 of the 5 claims about that event, because none says "ban" or
  "press"; *"CNN Politico White House"* finds 3. The empty-result note used to steer the caller
  *away* from retrying ("more likely unrecorded than mis-searched") and now says a match needs
  every word; the search itself is unchanged. Ranking by how many terms match
  (`ts_rank` over an OR query, with a floor) is the likely fix, and wants a spec with a
  query that shares most but not all of its words with a claim.
- `open_for_you` exists only inside `list_tasks`. A connection that never calls it never
  learns a queue exists, however many calls it makes. `waiting_on_you` rides on every
  result for reports; the same shape would serve here.

### 9. The loop itself: three parties and no shared workspace

Muse reviewed this node's own instructions on 2026-09-22 and made four proposals about the
loop it sits in — agent, node, maintainer. Two are already this project's rules and were not
being applied everywhere; two are gaps.

**Results are read by a skimmer.** Every miscommunication in that run was the agent not
seeing what the server meant. `record_investigation` returned the investigation URL eighth,
nested inside `share`, behind an array of cards; the agent truncated the result, never
reached it, and reported that it had not been given one. **Fixed** (2026-09-22): `url` and
`share_line` lead the result, `RECORD_OUTPUT_SCHEMA` declares every key it returns — five
were undeclared, including those two — and `spec/requests/result_leads_with_the_link_spec.rb`
fails if the link drifts past the first 200 characters of the text block a model actually
reads. The general rule is §1 and the refusals family: the thing the call was for goes
first, and a rejection names the corrective action. Extend the audit to every applier.

**A fix should be checkable without a checkout. — OPEN, and the sharpest of the four.** When
a report is answered "fixed", the filer had to clone the repository to confirm it. An answer
should carry the commit or tag and a repro — the exact call that failed — so the agent that
filed it can re-run the thing and watch it pass. `01a0cab9` was answered in prose with
neither. Give `Triageable#answer!` a `fixed_in` and a `repro`, surface both through
`get_report`, and the filer confirms its own bug.

**Agent confusion is a defect class. — OPEN.** Token churn, investigation-versus-claim,
contradictory answers about what shipped: none were code bugs, all were communication
failures, and they cost more of the agent's time than the real bugs did. They already arrive
through `report_bug` — what is missing is that they are triaged as documentation and
tool-description defects with the same lifecycle, and that `Guidance::VERSION` is the
delivery vehicle, so a fix reaches a live session on its next call.

**The report id is the join key. — PARTLY DONE.** It already appears in code comments and
commit messages here. What would close the loop is the report thread carrying the commit
too, so any of the three parties can trace the arc without the maintainer routing it. This
is the same change as the second point and should be built with it.

The through-line, in the reviewer's words and worth keeping: *stop relying on the agent
reading carefully, and stop relying on the owner remembering context — put the context in
the protocol.*

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

The ten questions of `12-constitution.md`, answered 2026-09-23 before the stage closed. The
stage touches identity only through §5, which was built earlier and is recorded there.

1. **Evidence more traceable or less?** More. §9 puts the commit and the re-runnable call on
   the answer itself, so a filer can trace a fix without the maintainer routing it.
2. **Disagreement more inspectable?** Yes. A refusal now names the field and the contract it
   broke; a caller that disagrees with a refusal can see exactly what it disagrees with.
3. **Hidden authority?** No. The validator applies the schema every caller is handed and
   nothing else; it adds no rule that is not published in `tools/list`.
4. **Reputation substituting for evidence?** No. Nothing here reads who is calling to decide
   what is accepted.
5. **Preserves uncertainty?** Yes. No scorer input changes; §8's search change widens what is
   *found*, never what is concluded.
6. **Reproducible?** Yes. Validation is a pure function of the arguments and the schema.
   Invariant 4 is untouched.
7. **Can an opposing investigator challenge it with the same system?** Yes, more easily:
   the search no longer needs every word, and an absence without coverage is refused.
8. **Can the history be reconstructed?** Yes. Validation happens *before* signing, so
   nothing enters the log that would not have entered it before, and nothing already in it
   changes.
9. **Shared evidence versus personal belief?** Untouched.
10. **Would we want it in the hands of people we disagree with?** Yes. A schema that
    refuses the same malformed call from anyone, and says why, is the neutral case.

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


## How it closed (2026-09-23)

### What was resolved

§1, §3, §4, §6, most of §8 and the open parts of §9 were built today. §2, §5 and most of §7
were already done. §5a is an owner decision; §7's manifest has no settled format; and one
item each in §8 and §9 is deliberately left.

### How

- **§1, the validator.** `Mcp::Arguments` checks every call against its `inputSchema`
  (`type`, `enum`, `properties`, `required`, `items`, `minItems`, `maxItems`, `minimum`,
  `maximum`) in `Mcp::Server#call_tool`, before anything is built or signed, with no gem. It
  follows the tools where they were looser than the schema. Integers may be whole-number
  strings or whole floats; plain strings may be numbers; booleans may be `"true"`/`"false"`;
  null is absence; undeclared keys are left alone. Each leniency is named in the module.
  Refusals say `answer.links[0].strength must be one of DIRECT, …` in the caller's
  vocabulary, never echo a value, and carry `see`: the schema fragment that was broken (§6).
- **§3.** `list_tasks` returns `open_all` and `answers_wanted_all`, and keeps `open` and
  `answers_wanted` as deprecated aliases. The caller's own pair comes first.
- **§4.** `Guidance::CONNECTOR` is shown on `/connect` and served at `GET /api/v1/connector`
  (in `Api::Openapi`), and now carries the `galedra:` trigger.
- **§6.** A refusal carries `guidance` and `waiting_on_you` on the same terms as a success.
  `Mcp::Server.ways_in` names all three ways to authenticate. It is used by the server's
  `TOKEN_INVALID` and by `McpController`'s 401. The 401 is the refusal a caller with a stale
  token actually meets, and it had named only OAuth.
- **§8.** `TOO_MANY_OPS` says how many ops were sent and how many sources the budget buys.
  `OPPOSING_EVIDENCE_SEARCH`'s objective says the direction is often SUPPORT.
  `Claims::Search.most_terms` gives `search_claims` a second pass that ranks by terms held,
  and keeps only claims holding at least half: the query from `91bee9ac` went from 1 claim
  to 7.
- **§9.** `thread_turns.fixed_in` and `repro`, for a maintainer's turn only. `answer!` and the
  reply box take them, `get_report` returns them as fields, the report page shows them, and
  `/check-galedra` says to use them and to push before naming a commit.

| Acceptance | Status | Guard |
|---|---|---|
| 1 | Met: all 36 tools that take arguments; three take none | `spec/requests/mcp_schema_refusals_spec.rb` walks `TOOLS` |
| 2 | **Met as far as the evidence allows** — see below | the whole suite (626 examples), and the leniency spec |
| 3 | Met: float, list, bad enum and missing nested field, and nothing written | same file |
| 4 | Met earlier (§2) | `spec/requests/mcp_tasks_spec.rb` |
| 5 | Met | `mcp_tasks_spec.rb`, beside the counter spec |
| 6 | Met | `spec/lib/skills_spec.rb`, `spec/requests/api/v1/guidance_spec.rb` |
| 7 | Met | `mcp_schema_refusals_spec.rb` |
| 8 | Met, for both refusals | same file; each named route is checked as routed |

**Acceptance 2 could not be run as written.** It asks for the run's accepted `TASK_RESULT`
payloads to be replayed through the validator. Those payloads are the *translated ops*; the
tool arguments that produced them were never stored, so there is no record of what callers
actually sent. What was done instead: the full suite, whose every MCP call now passes through
the validator, ran green, and the one spec the validator changed was one it should change (an
array in `links[].steps` is now refused by the schema, earlier and in the caller's terms). The
shipped example bundle `examples/agent/investigation.json` lacks `retrieved_at`, which the
server already refused (`Investigations::Record`); the page that loads it fills it in. The
risk that remains is a real caller sending a shape no spec sends. The live node logs every
refusal as `mcp_call … outcome=refused codes=SCHEMA_INVALID`, and **the first real run after
this stage should be read for new `SCHEMA_INVALID` refusals before anything else.**

### What remains

- **§5a: an owner decision.** What an anonymous caller behind a rotating address should get.
- **§7: the MCP discovery manifest.** There is no ratified format yet, so serving one would be
  a guess.
- **§8: `open_for_you` on every result.** Left deliberately. It costs a task-queue computation
  on every call, on a codebase whose recurring defect is per-call queries. `waiting_on_you`
  already rides on every result; the queue count wants a cached form first.
- **§9: agent confusion as a defect class.** A triage practice rather than code. The fields
  built here are its delivery vehicle; the practice is not written down anywhere yet.
- **Acceptance 2** as above, until a real run is read.
