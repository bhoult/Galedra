# Stage 31 — The rules on the wire, not in the skill

**Status:** implemented

**Spec:** 04 §3 (agent protocol), 06 §2 (API), 14 §Stage 14 (MCP and the skill), Articles
XIX (transparency over persuasion), XXIII (re-examination), Invariants 7 (AI is never
evidence by itself), 11 (untrusted text stays inert), 18 (the ledger runs no model)

Goal (owner request, 2026-09-19): *"Instead of the connector reading the rules and storing
them, can it read a url to the rules and re-read them each time? Having to reinstall the
connector after each change is kind of a pain and it will not be realistic to expect users
to do this once it is in production."*

## What went wrong first

A two-hour, fourteen-chapter podcast transcript was handed to a connected assistant. It
recorded thirteen claims through `record_investigation` and never called `create_outline`.

The size rule said: record it now when the input is *"roughly under 3,000 words of input,
**or** under about 25 claims."* Two limbs joined by **or**, and the second limb is the
assistant's own output. Deciding to record thirteen claims was therefore what made
recording thirteen claims permitted. The rule could not fire on a long source, because any
assistant that skimmed one into a handful of headline claims had already satisfied the limb
that licensed the skim.

That was fixed by stating the rule on the input alone. But the deeper fault was **where the
rule lived**:

| Surface | Re-read? | Held the size rule? |
|---|---|---|
| `skills/galedra.md` | never, until a user reinstalls | yes |
| `initialize` instructions | per connection, and [reportedly discarded by claude.ai](https://github.com/anthropics/claude-ai-mcp/issues/93) | no |
| tool descriptions | cached from the last connection | only `create_outline`'s |
| **tool results** | **never cached** | **no** |

The one channel that is always current carried none of it. This is the same defect as the
missing `reading` field in Stage 30: an instruction that lives only in the skill does not
reach a connector, which reads tool schemas and results.

## What the protocol says

MCP has no "fetch the rules from a URL" mechanism, because the server is already that URL:
nothing is stored at install time at the protocol level. Three channels exist, and they are
not equal.

- **Results are never cached.** Guidance attached to a tool result is read fresh on every
  call. This is the only channel with no staleness at all.
- **`tools/list` is cached, but the cache is controllable.** The
  [2026-07-28 spec](https://modelcontextprotocol.io/specification/2026-07-28/server/utilities/caching)
  added `ttlMs` and `cacheScope`, where `ttlMs: 0` means re-fetch whenever needed, and
  `listChanged: true` plus `notifications/tools/list_changed` invalidates a cache
  immediately. Host support is uneven.
- **`instructions` from `initialize`** is the spec's intended home for server-level rules
  and is the wrong place to put anything load-bearing while a major host drops it.

## What this stage does

**One source, two live channels, and a skill that carries none of it.**

1. **`app/services/guidance.rb`** holds every operational rule as named constants —
   `PURPOSE`, `START`, `SIZE`, `CHECK`, `OUTLINE`, `INFERENCE`, `WORK`, `CORRECT`,
   `STANDING`, `ASK` — with a `VERSION` that changes when the words do. `Guidance.for(topic)`
   composes the five topics; `Guidance.all` returns them.
2. **`Mcp::Server#guidance`** serves from it, and the buckets got finer. `create_outline`
   and `get_outline` now carry `:outline` (the anchor/reading split, the cleaning rule, the
   first pass) instead of the generic `:check` text, and `record_inference` carries
   `:inference`. Every result names its `topic` and `version`.
3. **`GET /api/v1/guidance`** serves the same text to hosts that speak REST rather than
   MCP, whole or by `?topic=`. This is literally the URL the owner asked for, and it is the
   only channel those hosts have.
4. **`skills/galedra.md` went from about 12 KB to 3.2 KB.** It keeps what cannot arrive in
   a result — what Galedra is, the `galedra:` trigger, search first — and says in as many
   words that it deliberately carries no working rules, that the guidance on each result is
   more recent, and that where they differ the guidance wins.

### Why two rules stayed in the skill

`STANDING`'s two hardest rules are repeated in the thin skill: your own reasoning is never
evidence, and never record claims about identifiable private individuals. Both are repeated
because breaking either damages the record rather than merely producing a worse answer, and
an assistant can break both *before* its first tool call, which is before any guidance has
reached it. Everything reversible is on the wire only.

## Decision Log

**Results over descriptions.** Tool descriptions are the obvious place to put rules and the
wrong one: they are cached, they are reportedly truncated near 500 characters on at least
one host, and `create_outline`'s is 1,203. The size rule sits at the front of both tool
descriptions so it survives truncation, but the descriptions are not what the code relies
on.

**The skill points rather than repeats.** A generated skill that renders the same constants
would not drift, but it would still be a snapshot: correcting a rule would still mean
asking every user to reinstall, which is the thing the owner said is unrealistic in
production. So the skill points at the live channels instead, and a spec fails if an
operational marker migrates back into it.

**`VERSION` is advisory.** It tells a host showing guidance to a person whether their copy
is current. Nothing enforces it, and no tool refuses a call because an assistant last read
an older version; that would punish the assistant for the host's caching.

**Caching hints, but not `listChanged`.** `tools/list` now returns `ttlMs: 0` and
`cacheScope: "public"`. Those are `2026-07-28` fields; a `2025-06-18` client ignores what it
does not know, and a later one honours them. Zero is the honest value and it pairs with
`listChanged: false`: this server has no stream to push
`notifications/tools/list_changed` on, because `GET /mcp` is `405` and always has been. A
server that cannot notify must not ask clients to cache, or a corrected tool description
waits for a reconnect that may never come. Declaring `listChanged: true` without a stream
would be worse than declaring nothing — a client that trusts it will never re-fetch, because
it believes it will be told.

### Found while testing

`spec/requests/outlines_spec.rb` asserted that a `get_outline` result does not contain the
string "probability" (Invariant 16: an outline shows counts by state, never a number). It
serialised the whole result, guidance included, and `STANDING` mentions probabilities in
order to forbid quoting one. The assertion now excludes the `guidance` key, which is what
it meant: guidance is advice, not payload. The rule text was not reworded to satisfy a
substring check.

### Outstanding

- Protocol `2026-07-28` proper, which is Stage 32 and a real piece of work rather than the
  version bump it was first described as. `2026-07-28` is a *modern* revision: it has no
  `initialize` handshake at all, carries version, identity and capabilities as per-request
  `_meta` plus an `MCP-Protocol-Version` header, requires `server/discover`, puts
  `resultType` on every result, returns `UnsupportedProtocolVersionError` (-32022) for a
  version it will not serve, and moves notifications onto a `subscriptions/listen` stream.
  Galedra is a legacy server by that vocabulary, and claude.ai is a legacy client, so the
  `initialize` path stays whatever else happens: the target is dual-era, not a migration.
- `listChanged: true`, which needs a stream to be honest, and therefore a held connection
  per client. That has capacity consequences worth measuring against Stage 26 before it is
  promised.
- The three generated skill forms still embed the connection preamble per host; nothing
  re-reads those either, but they change far less often than rules do.
- No host is known to surface `guidance.version` to a person. If one does, it is the cheap
  way to tell a stale connector from a current one.
