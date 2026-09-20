# Stage 20 — Sections and placements in the log

**Status:** implemented · tag `stage-20-sections` · decisions recorded 2026-09-19

## Plan

**Tag:** `stage-20-sections` · **Spec:** 02 §1.1a (epistemic vs control), 02 §3
(projections), 02 §3.2 (`source_locations`), 02 §3.6 (action types; two are added),
06 §5 (claim page, source page), 06 §6 (political speech rule), Article XIII
(corrections do not erase), Article XVI (disagreement localized), Article XVIII
(political neutrality: no speaker score), Invariants 1–3

Goal: the tree exists in the log, is rebuilt by replay, and is shown on the claim page
and on its own page. Nothing in this stage needs a connector; a signed-in person can
build an outline from a source page and file claims into it.

Why in the log, and why two new action types: sections are organizational, not
epistemic, but they are shared structure that many principals will add to over weeks,
and the public will read a speech through them. Stage 15 set the precedent: topics
are signed `TAG_CLAIM` contributions, never edited columns, so that filing is
attributed, replayable, and reversible. Sections and placements follow it. Two
alternatives were rejected: sections as `SOURCE_LOCATION` rows with a parent in the
locator (a section such as "OpenAI" in a two-hour conversation is a subject, not one
range of the recording; it may span several ranges or none) and a tree outside the
log like `investigations` (then a volunteer's placement, which arrives inside a
signed `TASK_RESULT`, would have nowhere signed to land).

Deliverables:

- `CREATE_SECTION`, epistemic (accepted on validation, like `CREATE_CLAIM`). One
  contribution creates one subtree, so an assistant records an outline of a few
  hundred sections in one signed write: payload `source_id`, `parent_section_id`
  (null for a root), `sections`: an ordered array of `{heading, location_id?,
  ranges?, sections?}` nested to at most 6 levels and at most 500 nodes per
  contribution, at most 2,000 per root. `heading` is at most 120 characters and is
  untrusted display text like a note: never scored, never in another agent's packet
  except as the section it is working. `location_id` names a `CREATE_SOURCE_LOCATION`
  on the same source (`TIME_RANGE`, `CHAR_RANGE`, `PAGE`, `LINE_RANGE`, or `SECTION`)
  whose excerpt is at most a 300-character quoted **anchor**: enough to find the place
  in the source, not the passage itself. A root section's `parent_section_id` is null
  and it names the source; a child inherits the root's source, and every section in a
  tree has one source (a debate with two transcripts is two outlines).
- `PLACE_CLAIM`, epistemic: `claim_id`, `section_id`, optional `position`. Accepted on
  validation for any principal (placing is filing, not certifying; Article XI is
  untouched because a placement changes no score). A claim may be placed in more than
  one section; the same claim in the same section twice is `DUPLICATE`. `CREATE_CLAIM`
  gains an optional `section_id`, so a claim born in a section is one contribution,
  and the applier writes the placement alongside the claim with the same seqs; inside
  a `TASK_RESULT` that placement is counted only when the result is (the extraction
  case, Stage 21). Removal is the existing `INVALIDATE` of the placement contribution.
- Projections `sections` (`id, contribution_id, source_id, root_id, parent_id, depth,
  position, heading, location_id, created_seq, invalidated_seq, accepted_seq,
  redacted_by_seq`) and `claim_placements` (`id, contribution_id, claim_id, section_id,
  position, created_seq, invalidated_seq, accepted_seq`), both in
  `Contribution::PROJECTION_MODELS` so digests, `ledger:replay`, and `ledger:verify`
  cover them; `Ledger::Ids.derive(contribution_id, "section", index)` for the nodes of
  one contribution, in preorder. `Ledger::ActionTypes::EPISTEMIC` gains both types;
  `Contributions::Schemas` and `schemas/eir-contribution-v1.json` gain their payloads.
  `TAKEDOWN` redaction covers `heading` and the anchor.
- `Sections::Tree`: the counted tree under a root at a seq, with per-section counts:
  claims placed, of which accepted, and counts by `assessment_state` under the default
  model in the 06 §6 form. **No section, root, source, or speaker ever gets a
  probability, a headline, or a badge.** `Investigations::Verdict` and
  `Cards::StatementImage` refuse a section; a root's share card is its counts.
  Descriptive counts carry the fixed note "counts depend on extraction granularity".
- Website:
  - `/sections/:id`: the outline page. Breadcrumb from the root; the subtree as a
    directory tree (`<details>` per section, open along the path to the current one,
    children and claims sorted by `position` then `created_seq`); each claim as one
    line with its `Cards::Badge` and headline linking to the claim; counts per section;
    "Proposed claims awaiting acceptance: N" where extraction results are pending
    (their text is not public until accepted, 04 §4.3); the source; open tasks under
    this section with the sentence a volunteer needs (Stage 21).
  - Claim page: when the claim has a placement, a left column `<aside class="outline">`
    on wide screens (a collapsible block above the card on narrow ones) shows the tree
    from the root to this claim: every ancestor expanded, the current section's claims
    listed with this claim highlighted, other branches collapsed and lazily rendered
    by Turbo Frame on open. `?section=` picks which placement's tree to show when a
    claim is in several; the first placement otherwise. The rest of the claim page is
    unchanged (06 §5 order).
  - Source page: "Outlines of this source" with root links; the per-source answer
    card is unchanged. `/sections`: every root, newest first, with progress (sections,
    claims, checked, open tasks).
  - Signed-in people: "Add an outline" on a source page (a textarea of indented
    headings, one per line, becomes one `CREATE_SECTION`), and "File under a section"
    on a claim page (through `Ui::Write`, like topics).
- API: `GET /api/v1/sections/:id` (the subtree with counts, `depth` capped by a
  parameter, default 2, and paginated children), `GET /api/v1/sections` (roots).
  `GET /api/v1/claims/:id`, `get_claim`, and `fetch` carry `sections: [{id, path:
  [headings from the root], url}]`. `GET /api/v1/claims?section_id=` lists claims
  under a subtree. Field names are the projection's; no synonyms.

Acceptance:

1. One `CREATE_SECTION` with a three-level tree of 40 nodes appends once, derives 40
   ids in preorder, and `/sections/:root` renders the tree; a second contribution with
   `parent_section_id` extends it; a 7-level tree, a 501-node contribution, a heading
   of 121 characters, a location on a different source, and a cycle are each rejected
   with `SCHEMA_INVALID` naming the path.
2. `CREATE_CLAIM` with `section_id` places the claim; `PLACE_CLAIM` files an existing
   claim in a second section; the claim page shows the tree for `?section=` with the
   claim highlighted and every ancestor open; `INVALIDATE` on a placement removes it
   from the tree at that seq and the earlier snapshot still shows it.
3. `Sections::Tree` counts match a hand count over the demo; no code path returns a
   probability for a section, and a request for a section's card returns the counts
   form; the fixed granularity note is present in HTML and JSON.
4. Truncate and replay reproduce `sections` and `claim_placements` byte for byte;
   `ledger:verify` passes; a `TAKEDOWN` on a section contribution nulls `heading` and
   the anchor and the tree still renders with `[redacted]`.
5. Demo goldens, Watchers goldens, and every existing acceptance scenario pass
   unchanged.

Owner decisions to record: the caps (depth 6, 500 nodes per contribution, 2,000 per
root, 120-character headings, 300-character anchors); whether a section heading can be
revised (this stage has no `SUPERSEDE_SECTION`; a wrong heading is fixed by a new
section and an `INVALIDATE`, which is heavy, and a supersession is the likely later
answer); whether placements should be proposals when the placer is not the outline's
principal (planned: accepted at once, since a placement changes no score and is
reversible).

## Decision Log (2026-09-19)

- Built as planned. `CREATE_SECTION` and `PLACE_CLAIM` are epistemic action types with
  their own appliers; `sections` and `claim_placements` are in `PROJECTION_MODELS`, so
  digests, replay, and `ledger:verify` cover them. Section ids derive from the
  contribution and a preorder index (`Ledger::Ids.derive(id, "section", n)`); a placement
  born with a claim shares the claim's contribution and seqs.
- `PLACE_CLAIM` is accepted for any principal (`auto_accept?` true): filing changes no
  score and is reversible by `INVALIDATE`. `CREATE_SECTION` follows `CREATE_CLAIM`'s rule
  (a human's own, or a connected assistant's, is accepted on validation). The same claim
  in the same section twice is `DUPLICATE`; an identical resubmission is absorbed by the
  log's idempotency before it reaches the applier.
- `Sections::Tree` computes counts per section in the 06 §6 form; "checkable" means
  truth-evaluable (everything but `NOT_APPLICABLE`), as the spec's example counts it.
  Nothing returns a probability, headline, or badge for a section; the fixed granularity
  note travels with every rendering and JSON.
- Website: `/sections` (roots with counts), `/sections/:id` (breadcrumb, counts line, the
  subtree as `details` elements open along the path, claims as lines with their state),
  the claim page's left column when the claim is placed (`?section=` picks which), "Add an
  outline" on the source and section pages from indented headings (`Sections::Outline`),
  and "File under a section" on the claim page. API: `GET /api/v1/sections`,
  `GET /api/v1/sections/:id?depth=`; `claim.sections` on the claim JSON and `get_claim`.
- Lazy rendering of collapsed branches by Turbo Frame was not needed: the tree renders
  whole and the browser collapses it; revisit at thousands of claims.
- `ClaimsController#place` needed `require_authentication` because the controller allows
  unauthenticated access for every other action.
- Constitutional Test: adds display structure only. 1 yes; 2 n/a; 3 no; 4 no; 5 yes; 6 yes;
  7 yes (replay byte-identical); 8 yes; 9 yes; 10 yes. No blocker.

- Correction (2026-09-20): the deliverable above placed `PROJECTION_MODELS` under
  `Ledger::Apply`. That module exists but does not define the constant, which is why the
  name resolved to nothing; it is `Contribution::PROJECTION_MODELS`
  (`app/models/contribution.rb`), and `Ledger::TableDigest::MODELS` is built from it. The
  substantive claim was true — `sections` and `claim_placements` really are covered by
  digests, `ledger:replay`, and `ledger:verify` — so only the namespace changed. The
  Decision Log below already named the constant correctly, unqualified.
