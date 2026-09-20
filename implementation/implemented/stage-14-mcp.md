# Stage 14 — MCP, OpenAPI, and the skill

**Status:** implemented · tag `stage-14-mcp` · decisions recorded 2026-09-18

## Plan

**Tag:** `stage-14-mcp` · **Spec:** 06 §2 (API), 06 §5 (embeddable cards), 04 §9

Goal: any assistant can be pointed at Galedra in one step, and the instruction "check
this in Galedra before you post it" produces the same procedure everywhere.

Deliverables:

- An MCP endpoint served by Rails over streamable HTTP at `/mcp`, bearer-authenticated,
  with a small tool set: `search_claims`, `get_claim`, `record_investigation`,
  `add_evidence`, `explain` (why plus the calculation on request), and `share_card`.
  Tool descriptions carry the rules, not just the schemas.
- An OpenAPI 3.1 document at `/api/v1/openapi.json` covering the public reads and the
  bearer writes, for GPT Actions and plain HTTP clients.
- The skill text, one file per host format (Claude skill, ChatGPT GPT instructions, a
  generic system-prompt block), all generated from a single source in `skills/`. It says:
  search Galedra first; do your own reading, Galedra never fetches; quote the exact
  passage and its link; one assertion per claim, typed; your own reasoning is not
  evidence; look for what would count against it before recording; never record claims
  about private individuals; report the headline and the link, and say it is provisional.
- Share card: `GET /claims/:id/card` renders a compact answer card page with Open Graph
  tags so the link previews correctly when pasted into a social post, and
  `/claims/:id/card.png` renders it as an image. No number on the card; model and
  snapshot in small print.
- The connect page shows copy-paste setup for Claude (MCP), ChatGPT (Actions), and a
  generic MCP client, using the token from Stage 12.

Acceptance:

1. An MCP client run in the suite lists the tools, searches, records a bundle, and reads
   back the card, all under one token.
2. The OpenAPI document validates and every path in it responds.
3. The generated skill files are byte-identical to their source rendering (a spec fails
   when they drift).
4. The share card page carries Open Graph title, description, and image, and the image
   renders for a claim in each assessment state without a probability.
5. The end-to-end "check before you post" scenario runs from `bin/demo --example
   check`: a meme source, an investigation bundle from the fixture agent, a share card.

Reserved for the owner: the licence line shown on share cards (CC0 vs CC-BY, already
reserved); whether share cards may be requested for quarantined claims (conservative
reading: they render the public stub).

## Decision Log (2026-09-18)

- MCP is served by Rails itself: `POST /mcp` takes one JSON-RPC 2.0 message and answers
  with JSON (streamable HTTP without server push; `GET /mcp` is 405). Protocol version
  2025-06-18; `initialize`, `ping`, `tools/list`, `tools/call`, and notifications.
  Six tools: `search_claims`, `get_claim`, `record_investigation`, `add_evidence`,
  `explain`, `share_card`. Reads are open like the rest of the public API; the two
  writing tools need a connected assistant's bearer token and otherwise return a tool
  error naming the connect page. Tool descriptions and the `initialize` instructions
  carry the working rules. Applier rejections come back as `isError` results with the
  usual codes, not as protocol errors.
- `GET /api/v1/openapi.json` is a hand-maintained OpenAPI 3.1 document covering the
  public reads and the three bearer writes; the spec walks every `GET` path in it. The
  bundle schema is shared with the MCP tool so the two surfaces cannot drift apart.
  `/api/v1/meta` now links the OpenAPI document, the MCP endpoint, and the connect page.
- The skill lives once, in `skills/galedra.md`. `bin/rails skills:build` renders it into
  `skills/claude/SKILL.md` (frontmatter plus MCP setup), `skills/chatgpt/instructions.md`
  (Actions import plus API-key auth), and `skills/generic/system-prompt.md`; a spec
  fails when the generated files are stale. `GALEDRA_URL` is a placeholder the user
  replaces, since the same text serves every deployment.
- Share cards: `GET /claims/:id/card` is a small page with Open Graph and Twitter tags,
  and `/claims/:id/card.png` a 1200×630 image rendered with libvips (`Cards::Image`):
  the plain headline, the claim, "say instead", and the model, snapshot, and review
  checks in small print. No probability anywhere on the card (rule 3) and no colour
  coding (rule 12). Quarantined claims 404 here rather than render a stub image,
  the conservative reading of the reserved decision. `libvips` was added to the
  development image; the production image already had it.
- The connect page now shows the three setups (Claude/MCP JSON, ChatGPT Actions import
  with API-key auth, plain HTTP) with the freshly minted token filled in, and links the
  skill files.
- `bin/demo --example check` runs the whole "check before you post" flow: an anonymous
  assistant, the fixture bundle, plain cards, a rendered share card, replay, and chain
  verification.
- Correction (2026-09-20): this stage also changed what a card says, and said nothing about
  it. `Cards::Plain#say_instead` returned `"This has not held up: <statement>"` and
  `"This is only partly supported: <statement>"`; the commit dropped both prefixes and
  returned the bare statement, under a message about the MCP endpoint, OpenAPI, the skill
  and share cards. Found by tracing the say-instead precedence, not by a spec — nothing
  tests that a commit's message covers what it changed.

  **The change was right and is kept.** A prefix is text the graph does not contain, and
  Invariant 10 says nothing is invented; Stage 15 later put the same principle in words
  when the owner asked for the line to be "either a whole graph sentence or absent". It was
  right by accident and unrecorded for a week, which is the part worth noticing: the
  reasoning arrived after the code, so nothing would have caught it had it been wrong.
