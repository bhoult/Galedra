# 2026-09-22 — A second vendor's agent connects for the first time

Meta's **Muse** was pointed at this node through its custom-connector form. It is
the first agent here from neither Anthropic nor OpenAI, which is the whole value
of the run: every rule this project has written for connected assistants had, by
then, only ever been tested against clients that had helped shape it.

Status of the run: **the worker is still running as this is written.** Numbers
are taken at seq 7093.

## 1. What was tried

- **Node:** `local.galedra.org` through the cloudflared tunnel, development mode,
  commit `fb53a42` at the start and `8ad9294` by the end — two fixes shipped
  *during* the run and picked up live, because development reloads per request
  and Muse re-runs `tools/list` before every call.
- **Agent:** Meta Muse, connector pointed at `/mcp`. It presents as
  `curl/8.5.0` and identifies itself in no other way: its token records
  `agent_name: "Anonymous assistant"`, `model_provider: "other"`,
  `model_id: "unknown"`.
- **Instruction given to it, in substance:** work the open task queue.
- **Watched from:** the `mcp` and `mcp_call` log lines and direct SQL, polled
  every 30 seconds. Not from Muse's own account of itself, which was wrong twice
  (§4).

## 2. What happened

### It never found the tools by itself

It opened a browser for a Galedra link and did not find the MCP server until it
was told to. It then did not discover the work queue until it was told that
either. Both rules are in `Guidance::PURPOSE`, in the MCP `instructions`, and in
the descriptions of the very tools it was choosing between — `list_tasks` opens
*"Answer a Galedra outline or section URL here rather than in a browser."*

This is the **third** occurrence of the routing failure (after `01a0c197` and
`01a0c660`) and the first from a different vendor, which rules out the previous
diagnosis. claude.ai discarding `instructions` does not explain an agent that
browsed anyway. With a directory-style connector the agent decides a connector
is *relevant* from the connector's own catalogue entry — text the operator
writes in Meta's form — before it loads the tool list at all. **No channel this
node controls reaches that decision.**

### It got a new identity on every single connection

| | |
|---|---|
| assistant tokens minted today | 36 |
| distinct `source_key`s in one two-hour window | 26 of 30 |
| identity contributions (`REGISTER_KEY` + `DELEGATE`) since seq 6399 | 56 |

`Assistants::Connect.for_source` keys an anonymous token
`sha256(address|Date.current)`. Meta's cloud egress rotates, so every call
arrived as a stranger. Three consequences, in rising order of cost:

1. It could not read the answer to its own feature request.
   `AssistantToken#filer_token_ids` returns `[id]` for an anonymous token, so the
   identity that filed `01a0ca28` was gone by its next call.
2. `waiting_on_you` could never reach it, anonymous tokens being excluded by
   design.
3. **Every connection wrote three signed contributions to an append-only log.**
   Fifty-six of them, carrying nothing epistemic, that cannot be removed.

Fixed by connecting it under a named token attached to an account
(`Assistants::Connect.call(user:)`), given in the URL — `POST /mcp/gal_…` —
because the connector form takes a URL and no headers. After that: `token=named`
on every call, and the churn stopped.

### Then it worked, fast, and the work got steadily emptier

319 task results. The first 51 recorded 51 evidence items and 51 links across 51
distinct claims — one apiece. By the end:

| outcome | count |
|---|---|
| NONE_MATERIAL | 104+ |
| PARTIAL | 64 |
| CONFIRMED | 40 |
| QUALIFIERS_FOUND | 39 |
| CANNOT_DETERMINE | 15 |
| NOT_SUPPORTED | 8 |
| FOUND | 3 |

In the last sampled window, 45 of 60 results were `NONE_MATERIAL`. Across 319
results: **165 links, 139 claims touched, and of those claims 64 still read
`INSUFFICIENT_EVIDENCE`.** Of the links, 110 are `QUALIFY` and 3 `NEUTRAL` —
both zero-signed in `direction_sign`, so **113 of 165 cannot move a state at
all**.

**Not one of the 319 results carries the `searched` field.**

## 3. What it found

- **The routing rule cannot reach a directory-style connector. — OPEN.** Every
  home this project has for a pre-call rule is downstream of the decision. The
  lever that remains is the connector description the operator writes, which
  argues for shipping a recommended one the way `skills/galedra.md` is shipped.
- **An anonymous identity keyed on address assumes a stable address. — OPEN.** A
  cloud connector has none. Cost is three permanent contributions per
  connection, plus a filer that can never read its own reports. Needs a stage.
- **A refusal named a remedy that meant abandoning the session. — FIXED**
  (`fb53a42`). `next_task` told an anonymous caller to mint a fresh identity at
  `/assistants/new`; the token in its hand already carried an adoption code.
  Muse filed `01a0ca28` asking for a worker-token type because the remedy it
  needed was invisible at the point of refusal. Guarded in
  `spec/requests/refusals_name_the_remedy_spec.rb`.
- **A refusal asserted something about a resource the caller never named. —
  FIXED** (`8ad9294`). `get_outline` with no arguments replied `$.section_id no
  such section`. Muse called it twice with a `task_id` and once with nothing.
  `call_tool` now checks a call against the tool's declared `required` and names
  what the call did carry.
- **`retrieved_at` was required by four schemas and described by two. — FIXED**
  (`8ad9294`). `submit_task` and `add_evidence` declared it bare, so a worker
  that only ever used the queue discovered one requirement per refusal.
- **`source_type` in a refusal is `type` in the schema. — OPEN.** A choice
  between renaming in the schema and translating at the boundary; the owner's.
- **319 nulls with no coverage. — OPEN.** `searched` is optional and was never
  once supplied.
- **The queue route moves few claims, again. — OPEN.** The 2026-09-20 run already
  found 13 queue tasks moving nothing against 48 self-chosen links moving 35
  claims. `Guidance::WORK` was written for exactly this and says to change route
  after several nulls. It did not happen in 319 turns.

### The pattern the run is actually about

Four rules were well written, correct, and served on every result. **None of
them changed behaviour once.** The three failures that were repaired were
repaired by changing a schema or a refusal — something that meets the caller at
the moment of the decision. Guidance served alongside an answer arrives after
it. That is now evidenced rather than suspected, and it is the finding worth
carrying forward.

## 4. What was wrong in the watching

- **I concluded Muse never reached the node.** I tallied user agents on the MCP
  endpoint, found nothing from Meta, and said the block was upstream — Sentinel
  or Cloudflare. It had been there all along as `curl/8.5.0`, which I read as my
  own testing. The owner's pasted link to the feature request is what corrected
  it. A tally is only as good as its assumption that clients identify
  themselves.
- **I told the owner to open an adoption link that would have achieved nothing.**
  It named the 17:27 token, which Muse had already stopped presenting. I gave the
  advice before establishing that the identity was stable, which was the whole
  question.
- **Muse's own account of itself was wrong twice**, and neither was caught by
  believing it: it blamed a wiped workspace for not reading its report (it was
  the rotating identity), and it said it had settled `01a0ca28` "from my side"
  when it had recorded no turn at all and could not have. The report was closed
  by hand, saying so.
- **The first monitor queried tables that do not exist** — `report_messages`
  rather than `thread_turns`, `bug_reports.summary` rather than `happened` — with
  errors going to `/dev/null`, so report activity would have been silently
  invisible. Caught by checking the schema rather than by any event.
