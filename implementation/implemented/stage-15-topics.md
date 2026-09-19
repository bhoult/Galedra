# Stage 15 — Topics

**Status:** implemented · tag `stage-15-topics` · decisions recorded 2026-09-18

## Plan

**Tag:** `stage-15-topics` · **Spec:** 02 §3 (projections), 05 §5 (domains), 06 §5, §7
(pages, search), Art. III (evidence and interpretation are distinct), Art. XIX

Goal: every claim can be placed in a small hierarchical vocabulary of subjects, so
people can browse and filter by what a claim is about, assistants can file what they
record, and audited reliability stays per domain. A topic is a judgment about a claim,
so it is a signed, attributable, challengeable log entry like everything else, never a
column someone edits.

**The vocabulary** lives in `config/topics.yml`, closed and two levels deep, each node
with a slug, a label, a one-line scope note, and the audit/reputation domain it maps to.
First draft, for the owner to edit before the stage starts:

| Top level | Children |
|---|---|
| `science` | `biology`, `medicine`, `neuroscience`, `psychology`, `physics`, `chemistry`, `earth` |
| `mathematics` | `statistics`, `numeracy` |
| `technology` | `software`, `ai`, `security` |
| `health` | `nutrition`, `vaccines`, `public-health` |
| `environment` | `climate`, `energy`, `wildlife` |
| `politics` | `elections`, `policy`, `government`, `geopolitics` |
| `economics` | `markets`, `employment`, `prices`, `business` |
| `law` | `courts`, `legislation` |
| `history` | `ancient`, `modern`, `archaeology` |
| `religion` | `theology`, `scripture`, `church-history` |
| `society` | `media`, `education`, `crime`, `immigration` |
| `culture` | `memes`, `entertainment`, `sports` |

Paths are `top/child` (`science/biology`). A claim may carry several. The existing
demo domains stay: `history/ancient` maps to `ancient_near_east`, `economics/*` to
`us_economics` until the owner renames them; every other top level maps to a domain of
the same name, and untagged claims stay in `general`.

Deliverables:

- `TAG_CLAIM` (action class `epistemic`, payload `claim_id`, `topics: [paths]`, optional
  `note`): validated against the vocabulary, applied to a `claim_topics` projection
  with validity windows, superseded by a later `TAG_CLAIM` from the same principal and
  invalidated like any other contribution. Auto-accepted for a human's or a connected
  assistant's own claims; a tag on someone else's claim stays `PENDING` until accepted,
  as proposals do (`02 §1.1a`). Replay reproduces the projection.
- The bundle and the tools: `claims[].topics` in `POST /api/v1/investigations` and the
  MCP `record_investigation` tool (one `TAG_CLAIM` per claim after the claim), a
  `tag_claim` MCP tool for existing claims, and the skill text telling assistants to
  file each claim under one or two topics and never to invent one.
- The extractor proposes topics from surface cues for the Analyze text form, shown as
  editable checkboxes; the claim page shows topics with the contributor who set them
  and a "suggest a different topic" action that appends a `TAG_CLAIM`.
- Topic pages: `/topics` (the tree with counts), `/topics/science`, `/topics/science/biology`,
  each listing claims with counts by assessment state that roll up from children.
  Counts only, never an aggregate score for a topic (`06 §6` extended). `?topic=` on
  the claims index, the search, and the API (`/api/v1/claims?topic=`, `/api/v1/topics`).
- Domains: `Audits::Policy.domains` extends with the mapped domains; tasks opened for a
  tagged claim take the claim's first topic's domain, so reputation buckets follow the
  subject. Existing buckets and the demo goldens are unchanged.
- Delegations may restrict `permissions.topics`; a tag outside the grant is rejected.

Acceptance:

1. A `TAG_CLAIM` with a known path creates a `claim_topics` row; an unknown path is
   `SCHEMA_INVALID`; a second tag by the same principal supersedes the first; replay
   reproduces the rows and digests.
2. A bundle with `topics` on a claim appends the tag after the claim; the claim page,
   the API, and the MCP `get_claim` tool show it with its contributor.
3. `/topics/science` counts a claim tagged `science/biology` under both `science` and
   `science/biology`, by assessment state, with no probability anywhere on the page.
4. A task opened for a claim tagged `history/ancient` carries domain `ancient_near_east`,
   and an audit of its result lands in that reputation bucket.
5. The demo goldens, reputation tables, and replay checks still pass untouched.

Owner decisions to record before starting: the vocabulary itself; whether a claim
needs at least one topic to be scored (conservative reading: no, untagged is
`general`); whether `culture/memes` is a subject at all, given that a meme is already
a source type (`SOCIAL_POST`, `IMAGE`) and its claim is about whatever the meme asserts;
how a new topic gets added later (a signed config release like a scoring model, or a
plain code change).

## Decision Log (2026-09-18)

- The vocabulary is `config/topics.yml`: twelve top-level subjects with children, each
  naming the audit/reputation domain it maps to (`history/ancient` keeps
  `ancient_near_east`, `economics/*` keeps `us_economics`). `Topics` reads it once and
  offers lookup, the domain for a path, a keyword guess for the Analyze form, and a
  claim's current topics at a seq. `Audits::Policy.domains` is the configured list plus
  every mapped domain, so delegations and tasks accept them without a second vocabulary.
- `TAG_CLAIM` is a new epistemic contribution: `claim_id`, one to five distinct paths,
  an optional note. Unknown paths are `TOPIC_UNKNOWN`. It projects to `claim_topics`
  (one row per topic, in `PROJECTION_MODELS`, so digests, replay, ACCEPT, and
  INVALIDATE cover it). A later tag by the same principal sets `replaced_seq` on that
  principal's earlier rows, deterministically at apply time; `ClaimTopic.current_at`
  reads the window. Auto-accepted only for the claim's own principal (human, or a
  connected assistant acting for them); a tag on someone else's claim stays `PENDING`
  until accepted, like a proposal. A delegation may carry `permissions.topics`, a list
  of allowed prefixes; tags outside it are `DELEGATION_INVALID`.
- Bundles take `claims[].topics`, appended as one `TAG_CLAIM` after the claim; the
  MCP schema enumerates the paths, `tag_claim` and `list_topics` were added, and
  `get_claim` and the claim API carry `topics`. Tasks opened for a tagged claim take the
  first topic's domain, so reputation buckets follow the subject (acceptance #4 audits
  a result into `ancient_near_east`).
- Pages: `/topics` (the tree with counts), `/topics/<top>` and `/topics/<top>/<child>`
  with claims and counts by assessment state rolled up from children and never a
  probability; `?topic=` on the claims index and the API; `/api/v1/topics`. The claim
  page lists topics with who set them and lets a signed-in person suggest others
  (a `TAG_CLAIM` of their own). The Analyze form pre-selects guesses from surface cues.
- Demo goldens, reputation tables, and replay checks are unchanged (acceptance #5).
- Reserved decisions unchanged: an untagged claim is scored and sits in `general`;
  `culture/memes` exists for claims about memes as a phenomenon, while a meme itself is
  a source; adding a topic is a code change for now.
- Constitutional Test (visibility): 1 more traceable; 2 yes, competing tags coexist and
  name their contributors; 3 no; 4 no; 5 yes; 6 yes; 7 yes, anyone can propose a tag;
  8 yes; 9 yes; 10 yes.
- Backfill (owner request, same day): `bin/rails topics:backfill` files untagged claims
  under topics guessed from wording as system-signed `TAG_CLAIM` entries whose note says
  they are guesses; the applier accepts the system's own tags. `REPLACE=1` re-guesses
  claims whose only current tags are earlier backfills and never touches tags set by
  people or assistants. The topics page shows only populated subjects. `science/space`
  was added and the law and markets cues tightened after the first pass mis-filed
  "bandstand" and "Market Street".
- One plugin, the person decides (owner decision, 2026-09-18): the consent page no
  longer requires sign-in up front. A signed-out person sees "Sign in and connect under
  my name" (sign-in, then straight back to the same request) or "Continue
  anonymously"; a signed-in person can still choose anonymous. An anonymous grant
  issues a fresh anonymous assistant key per grant, adoptable later, so a single
  `/mcp/connect` plugin serves both attributed and anonymous use, and reinstalling a
  plugin is never needed to switch.
- Making it work with ChatGPT (2026-09-18), three fixes found by watching the log:
  ChatGPT fetches `/.well-known/openid-configuration` first, so the same metadata is
  served there with `jwks_uri` and the OpenID fields; it requires
  `authorization_response_iss_parameter_supported` and `client_id_metadata_document_supported`
  in the metadata and verifies `iss` before exchanging a code (RFC 9207, now sent on every
  authorization response); and the consent form was submitted by Turbo, which cannot
  follow a redirect to another site, so approvals went nowhere until the form was made a
  plain page submission. CORS is enabled on the OAuth, discovery, and MCP endpoints for
  clients that exchange codes from a browser. Cloudflare passed everything except a
  default Python user agent. The website's connect page, FAQ, landing page, and README
  now describe OAuth as the way in, with tokens under "Advanced".
- Testing with claude.ai (2026-09-18): the custom connector at `/mcp/connect` connected
  and called tools with no server change beyond the Claude items above (port-agnostic
  loopback redirects for Claude Code, `offline_access`, `scope` in the 401 challenge, the
  return host on the consent page). What failed was recording: Claude's host shows it
  rendered text, not page bytes, so it rightly refused to invent a `content_hash` and
  recorded nothing. The page hash is now optional for a source held by reference (the
  applier and the bundle validator still reject a malformed one). What Galedra verifies
  for such a source is the quoted excerpt, which carries its own hash, the link, and the
  time of reading; the source page says "no page hash" when none was given. The tool
  descriptions, rules, and skill now say to omit the hash rather than fabricate it or
  refuse. Article II still holds: the excerpt is traceable to an exact location and the
  log records exactly what the reader had.
- Say instead, short and plain (owner request, 2026-09-18): the first claude.ai
  recording put a 46-word evidence statement on a supported claim's card as the
  sentence to say instead. `Cards::Plain` now offers a say-instead line only when the
  claim as stated does not hold up (a supported claim is itself what to say), prefers
  for a qualifier the claim that the same evidence supports and that holds up over the
  evidence statement, and skips any candidate over 25 words rather than cutting it
  short, so the line is either a whole graph sentence or absent. The tool schema and
  the skill ask assistants for evidence statements of at most 25 words that a stranger
  could read aloud. Invariant 10 is unchanged: nothing is composed or paraphrased.
- Purpose before plumbing (owner feedback, 2026-09-18): asked "what can I do with
  Galedra?", Claude listed the ten tools and their enums. The MCP `initialize`
  instructions and the skill now open with the three things a person does with it
  (check before sharing and post the link; send someone a claim link so they see the
  reasons; help by checking recorded claims) and ask the assistant to say those first.
  An empty search now returns the total of accepted claims and a note that the subject
  is more likely unrecorded than mis-searched, since Claude could not tell an empty
  ledger from a narrow search.
