# Stage 21 — Large requests from a connector

**Status:** planned, not built · tag will be `stage-21-large-requests`

## Plan

**Tag:** `stage-21-large-requests` · **Spec:** 04 §2 (`CLAIM_EXTRACTION`), 04 §4.3
(extraction is proposal-only), 04 §5 (context compiler), 04 §7 (leases), 02 §1.1a
(acceptance by a different principal), 01 §7 (no copyrighted full text), Article II,
Article XI, Article XIV, Article XXIV (efficient skepticism)

Goal: "galedra: <a two-hour transcript>" works. The assistant records the structure
and the jobs when the whole check will not fit in about fifteen minutes, asks the
person whether to start on the research itself, and either way the work can be picked
up by anyone who says "work five open tasks in Galedra on <outline url>". Everything
recorded is attributed, signed, and open to audit exactly as a small check is.

Why this shape: every piece already exists. The outline is Stage 20; the extraction
task per leaf is the P0 `CLAIM_EXTRACTION` with a `location_id`, which
`Tasks::BuildContext` already supports; a volunteer answers it through Stage 18's
`submit_task`; the proposal-only rule of 04 §4.3 and Stage 19's `accept_proposal` are
the review step; verification tasks then open exactly as `Investigations::Record` opens
them today. This stage carries those pieces over the connector in the order an
assistant needs and adds the one judgment the server cannot make, the size rule, to
the skill.

The size rule (in the skill and in every `create_outline` reply): the assistant does
the whole check now, with `record_investigation`, when the text is short enough that
it can read it, read the sources it needs, and record, in about fifteen minutes of
work: roughly under 3,000 words of input, or under about 25 claims, and no source it
cannot read now. Above that it records the outline and its tasks first. It never
records a partial check as if it were whole: a large input recorded without an
outline is refused by the tool (`statement` over 2,000 characters, or more than 40
claims in one bundle without a `section`), with the reply pointing to
`create_outline`.

Deliverables:

- `create_outline` (connector tool, also `POST /api/v1/outlines`; no token needed,
  anonymous like `record_investigation`): `statement` (what the person asked, as they
  said it, at most 2,000 characters; for a transcript this is the title and link, not
  the text), `source` (as in `record_investigation`: by link, hash optional; a
  transcript is `VIDEO`, `AUDIO`, or `PRIMARY_TEXT`), `sections` (the nested tree with
  handles, headings, and a `locator` and quoted `anchor` on each leaf), `open_tasks`
  (default true), and `parent_section_id` to extend an existing outline. Records the
  source, one `CREATE_SOURCE_LOCATION` per leaf anchor, and one `CREATE_SECTION` for
  the tree; opens one `CLAIM_EXTRACTION` task per leaf with `location_id` set (so the
  packet carries the locator, the heading, and the anchor as `untrusted_excerpt`, and
  the volunteer reads the range in the source itself: Galedra never fetches). Returns
  the root URL, section ids by handle, tasks opened, the share line in the 06 §6 counts
  form, and `next`: the exact thing to say to the person: that the outline is
  recorded with N sections and M open tasks, and the question whether they want the
  assistant to start on the research itself now.
- `record_investigation` gains `section` on each claim (a section id): the claim is
  born placed (`CREATE_CLAIM` with `section_id`, Stage 20). A bundle whose claims all
  carry `section` under one root is a **section check**: the reply's share line is the
  root's counts line, not a verdict, and the leaf's open `CLAIM_EXTRACTION` task is set
  `CANCELLED` with `cancelled_reason: RECORDED_BY_REQUESTER` when the recorder's
  principal is the outline's (the task is not a log entry; cancelling it is not a
  correction). Verification tasks open per new claim as today. `add_evidence` is
  unchanged.
- Working the pieces: `tasks.section_id` (nullable, set on creation from the leaf or
  from the target claim's placement) so `list_tasks` and `next_task` take
  `section_id` and mean the whole subtree; `list_tasks` groups open work by outline
  root. `Tasks::Answer` for `CLAIM_EXTRACTION` puts the leaf's `section_id` on every
  `CREATE_CLAIM` op so extracted claims land in their section as pending placements.
  Acceptance of an extraction result (`accept_proposal`, or the Accept button on the
  section page, both under Stage 19's rule: the outline's principal, anyone named when
  it is anonymous, or a moderator, never the extractor's own principal) counts the
  claims and their placements, and `Tasks::OpenVerification` (idempotent, keyed by
  claim and seq) opens `OPPOSING_EVIDENCE_SEARCH`, `QUALIFIER_CHECK`, and
  `EVIDENCE_VERIFICATION` against the leaf's anchor location, with the anonymous
  priority factor when the outline is anonymous. The requester's assistant may accept
  its volunteers' extractions (it is a different principal) and is told in the reply
  that every accepted claim is now its principal's responsibility, which is also what
  lets its principal's tasks on those claims be worked by others and not by itself
  (Stage 18 rule).
- Caps: an outline of a few hundred sections is one `CREATE_SECTION` plus one location
  per leaf, so a 60-leaf outline is about 62 writes against the 200-a-day cap; the
  claims that follow are one write each, as they must be. `Assistants::Connect` gives
  named (OAuth or account-connected) assistants a `daily_cap` of 1,000 and keeps 200
  for anonymous and pasted ones; the cap reply names the outline so the assistant can
  say how far it got and that the rest is open work.
- Skill and instructions, "Large sources" procedure: (1) search first, as always; (2)
  apply the size rule; (3) for a large source, read the whole text once and write the
  outline as subjects the way a table of contents would, nested where the talk nests,
  leaves of roughly two to eight minutes or 300 to 800 words, each with a locator and
  a short quoted anchor; do not paste the transcript into Galedra; (4) call
  `create_outline`; (5) say what `next` says and ask; (6) if the person says yes, work
  leaf by leaf: read the leaf, record its claims and evidence with
  `record_investigation` and `section`, say which leaf is done, and stop when the
  person says so or the cap is reached, reporting the sections done and the tasks
  left; (7) the last line of every reply about an outline is its share line. Rules
  unchanged: only quoted passages are evidence; a speech is never given a score, only
  counts; claims about identifiable private individuals are never recorded (a guest
  or a speaker is public in that role; a person they mention may not be); an opinion,
  a prophecy, or a doctrine goes in typed (`NORMATIVE`, `FORECAST`, `METAPHYSICAL`) so
  the page says it is not a checkable fact.
- "Work five open tasks in Galedra on <url>": the skill maps an outline URL in the
  request to `section_id` on `next_task`. The section page carries that sentence.
- OpenAPI (`Api::Openapi`), the FAQ, and the connect page gain the outline flow.

Acceptance:

1. `create_outline` with a 3-level, 12-leaf tree over a source by link records one
   source, 12 locations, one `CREATE_SECTION`, and 12 `CLAIM_EXTRACTION` tasks with
   `section_id`; the reply carries `next` with the question, and its share line is the
   counts form; the same bundle twice records once.
2. A different principal's assistant calls `next_task` with the root's `section_id`,
   receives an extraction packet whose `untrusted_excerpt` is the anchor and whose
   context names the locator and heading, answers `CLAIMS_FOUND` with six claims; the
   claims are pending, appear on the section page only as a count, and are in
   `list_proposals` for the requester; `accept_proposal` there counts them, places
   them, and opens 18 verification tasks; the extractor's own assistant is refused on
   accept and cannot lease the tasks on its own claims; the requester's cannot lease
   the extraction tasks it opened.
3. The requester's assistant records a leaf directly with `record_investigation` and
   `section`; the claims are accepted at once, the leaf's extraction task reads
   `CANCELLED` with `RECORDED_BY_REQUESTER`, verification tasks open, and the reply's
   share line is the root's counts.
4. `record_investigation` with a 2,001-character `statement`, or 41 unsectioned claims,
   is refused with a message naming `create_outline`; a named assistant's 201st write of
   the day succeeds and its 1,001st is refused naming the outline; an anonymous one's
   201st is refused.
5. The section page of a speech shows counts by state and no probability, badge, or
   headline for the speech; `explain` and `share_card` on a section id are refused
   with a reason citing 06 §6; demo goldens, replay, and verify are unchanged.

Owner decisions to record: the size thresholds (3,000 words, 25 claims, 40 claims per
unsectioned bundle); the named-assistant cap of 1,000; whether an outline created
anonymously should open extraction tasks at all (planned: yes, at the anonymous
priority factor, as `record_investigation` does); whether a requester may accept its
own volunteers' extractions (planned: yes, it is a different principal and it becomes
responsible); the copyright stance for anchors (planned: at most 300 quoted characters
per leaf and never the passage; stored full text stays the signed-in Analyze-text path
where the person affirms they may store it).

## Decision Log

Written when the stage is executed.
