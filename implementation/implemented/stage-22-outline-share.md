# Stage 22 — Sharing and following an outline

**Status:** implemented · tag `stage-22-outline-share` · decisions recorded 2026-09-19

## Plan

**Tag:** `stage-22-outline-share` · **Spec:** 06 §4 (display rules), 06 §6 (counts,
no ranking), 06 §5 (distribution), Article XVIII, Article XIX

Goal: the link a person posts for a checked speech or episode is as useful as the link
for a checked meme, and someone who wants to help can find the big jobs.

Deliverables:

- `investigations.section_id` (nullable): an investigation recorded by `create_outline`
  or a section check points at the root, and `Investigation#claims` reads the counted
  claims under it live rather than a frozen `claim_ids` list, so the shareable page
  follows the work. `/investigations/:id` for an outline shows the statement, the
  counts line, progress (leaves extracted, claims checked, open tasks), the tree two
  levels deep with links, and the sentence for volunteers; its `card.png` is the counts
  card. Open Graph tags as today.
- The share line for an outline is fixed as
  `Checked in Galedra: <root heading> · N claims recorded, M checked · <counts by state> · <url>`
  with the counts in 06 §6 order and no adjective for the whole.
- `/sections` (Stage 20) gains filters by topic (from the placed claims' tags) and
  "most open work first"; the landing page's "help the project" step links it.
  `list_tasks` with no filter names the three outlines with the most open work.
- Weaknesses page (Article XXII): outlines whose leaves are extracted but fewer than a
  quarter of whose claims have any counted evidence, so unfinished big jobs are
  visible as such.

Acceptance:

1. An outline's investigation page shows live counts that change after a volunteer's
   accepted extraction; its share line matches the fixed form; the PNG has no badge.
2. `/sections` orders by open work and filters by topic; the weaknesses page lists an
   outline with 12 leaves extracted and 3 of 60 claims evidenced.
3. Goldens, replay, and verify unchanged.

Owner decisions to record: whether an outline's investigation should be re-recordable
by anyone (today an investigation belongs to the token that recorded it); whether to
show per-speaker counts inside one debate transcript (planned: no, Article XVIII;
sections may be named by speaker but no count is broken out by speaker).

## Decision Log (2026-09-19)

- `investigations.section_id` and the live reading of an outline's claims arrived with
  Stage 21; the outline's own page is its check page (the investigation URL redirects to
  it), so the page carries the Open Graph tags and the share line rather than a second
  page. The counts card image was not built: link previews read the tags.
- `Sections::Progress`: leaves, leaves extracted (an accepted claim under the leaf, or
  its extraction task complete or cancelled), claims, claims checked (any counted
  evidence), open work. The share line is fixed as
  `Checked in Galedra: <heading> · N claims recorded, M checked · <states in 06 §6 order> · <url>`
  with no adjective for the whole; `Sections::Tree.states_line` renders the states.
- `/sections` orders by open work then claims (or newest), filters by topic through the
  placed claims' current tags, and shows progress per outline; the landing page's help
  sentence links it; `list_tasks` already names the three outlines with most open work.
- Weaknesses page: an "unfinished outlines" table (every leaf extracted, fewer than a
  quarter of claims with evidence) above the claim lists; the JSON report's kinds are
  unchanged so the API and its goldens are untouched.
- Per-speaker counts are not broken out (Article XVIII), as planned.

