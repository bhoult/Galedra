# Stage 19 — Correct what is recorded, from a connector

**Status:** implemented · tag `stage-19-corrections` · decisions recorded 2026-09-18

## Plan

**Tag:** `stage-19-corrections` · **Spec:** 02 §1.1a (acceptance by a different
principal), 02 §5 (`SUPERSEDE_CLAIM`), 02 §3.3 (`MERGE_CLAIMS`), 02 §3.6
(`SUPERSEDE_LINK`), 04 §3 and §7 (tasks), 05 §9 (audits), Article XI, Invariant 3
(append-only: corrections are new contributions)

Goal: an assistant that finds something wrong can fix it when it is its own person's
work, propose the fix when it is someone else's, and hand a doubt to a different
principal as a blind task; and the person whose claim was corrected can accept the
proposal through their own assistant or on the claim page. A revised claim is marked
as such and points forward; the old entry stays in the log. Nothing is deleted, and
invalidation stays with human audits.

Why this shape: every primitive already exists in the log. `SUPERSEDE_CLAIM` replaces
a claim with a corrected one, `MERGE_CLAIMS` folds a duplicate into another,
`SUPERSEDE_LINK` revises an evidence link, `ACCEPT` by a different principal turns a
proposal into counted structure, and a task is the blind hand-off. None of them is
reachable from a connector, and the website has no way to accept a proposal, so today
a correction proposed by anyone but the claim's own principal waits forever.

Deliverables:

- Six connector tools, also usable through `/mcp/:token`:
  - `revise_claim`: `claim_id`, corrected `text`, `type` (defaults to the current
    type), `reason`, optional `topics`. Appends `SUPERSEDE_CLAIM`. On the caller's own
    principal's claim it is accepted at once: the old claim reads `SUPERSEDED` from
    that seq and points to the new one, and with `carry_links` (default true) every
    counted link on the old claim is re-issued by the assistant onto the new one, with
    the same direction, strength, and steps and a note naming the link it carries. On
    someone else's claim it is a proposal (`PENDING`) and the reply says whose
    acceptance it waits for.
  - `merge_claims`: `from_claim_id`, `into_claim_id`, `reason`. Appends
    `MERGE_CLAIMS`; accepted at once when both claims are the caller's principal's,
    otherwise a proposal.
  - `revise_link`: `link_id` (from `get_claim`'s evidence), `direction`, `strength`,
    `steps`, `reason`. Appends `SUPERSEDE_LINK`; own link accepted at once, another's
    a proposal.
  - `open_task`: `claim_id`, `type` (`OPPOSING_EVIDENCE_SEARCH`, `QUALIFIER_CHECK`,
    `SOURCE_INDEPENDENCE_CHECK`, or `EVIDENCE_VERIFICATION` with `location_id`).
    Opens a task for a different principal to work blind; an open or leased task of
    the same type on the same target is returned instead of duplicated. Named
    assistants only. The requester's principal can never lease a task it opened.
  - `list_proposals`: pending corrections (`SUPERSEDE_CLAIM`, `MERGE_CLAIMS`,
    `SUPERSEDE_LINK`, `TASK_RESULT`) on one claim, or on every claim of the caller's
    principal when no claim is given: what each would change, who proposed it, and
    whether the caller may accept it.
  - `accept_proposal`: `contribution_id`, `carry_links` (default true). Appends
    `ACCEPT` under the assistant's delegation. Connected-assistant delegations list
    `ACCEPT` under `permissions.allowed_actions` from this stage on; an older
    connection is told to reconnect. When the accepted proposal is a
    `SUPERSEDE_CLAIM`, the acceptor's assistant carries the old claim's counted links
    onto the new one, since the acceptor is the one affirming the corrected text.
- Acceptance scope at the connector, stricter than the applier's "any different
  principal": the target's own principal; any named principal when the target's
  principal is anonymous; or a moderator. The applier's no-self-certification check
  still runs underneath.
- Website: the claim page shows a banner on a revised claim ("Revised at seq N by …:
  new text, reason", linking forward) and on the revision ("Revises …"), and on a
  merged claim. A "Proposed corrections" section lists pending proposals with an
  Accept button for a signed-in person under the same acceptance rule, through
  `Ui::Write`. `get_claim` and `fetch` carry `status`, `revises`, `superseded_by`,
  `merged_into`, and the count of pending proposals, so an assistant reports a
  superseded claim as superseded and gives the current one.
- Skill and instructions: "Correcting what is recorded": own work is fixed at once,
  others' work is proposed and the person told it awaits acceptance, a doubt about
  a passage or an origin becomes a task, and "review corrections proposed on my
  claims" means `list_proposals` then `accept_proposal` for each the person agrees
  with, leaving the rest pending. Never claim something was fixed when it is a
  proposal.
- Unchanged: audits, invalidation, quarantine, and takedown stay human; an assistant
  cannot retract anything, including its own earlier result, except by revising it.

Acceptance:

1. `revise_claim` on the caller's own claim: the new claim is accepted, the old one
   reads `SUPERSEDED` at that seq and its page links forward, the counted links are
   carried with a note, the card moves to the new claim, and `get_claim` on the old id
   names the new one.
2. `revise_claim` on another principal's claim is `PENDING`; `list_proposals` from
   that principal's assistant shows it; `accept_proposal` there accepts it, supersedes
   the old claim, and carries the links; the proposer's own assistant is refused with
   `NOT_AUTHORIZED`; an unrelated named principal is refused when the target's
   principal is named and allowed when it is anonymous.
3. A `merge_claims` proposal accepted by the claims' principal marks the source claim
   `MERGED`; `revise_link` on the caller's own link is accepted and counted, on
   another's it is pending and the old link still counts.
4. `open_task` creates the task, returns the existing one on a repeat, refuses
   `EVIDENCE_VERIFICATION` without a location and anonymous callers, and the
   requester's assistant cannot lease it while a different principal's can.
5. A signed-in person accepts a proposal on their own claim from the claim page; the
   proposer's principal sees no Accept button and is refused if it posts anyway;
   demo goldens, `ledger:replay`, and `ledger:verify` are unchanged.

Owner decisions to record: the acceptance scope (the applier allows any different
principal; the connector and the page allow the target's principal, anyone named when
the target is anonymous, and moderators); whether declining a proposal should be
recorded (today leaving it pending is the decline; there is no `REJECT`); whether
proposals should expire.

## Decision Log (2026-09-18)

- Six MCP tools over primitives the log already had: `revise_claim`
  (`SUPERSEDE_CLAIM`), `merge_claims`, `revise_link` (`SUPERSEDE_LINK`), `open_task`,
  `list_proposals`, `accept_proposal` (`ACCEPT`). `Corrections` holds the logic and
  is shared with the claim page, which now shows a "Revised" or "Merged" banner
  pointing forward, "Revises …" on the revision, and a "Proposed corrections" table
  with an Accept button for an entitled signed-in person through `Ui::Write`.
  `get_claim` and `fetch` carry the revision status so an assistant never presents a
  superseded claim as current.
- Own work at once. `same_principal?` now treats an agent under a `direct_work`
  delegation as its principal's hand, as Stage 12 already did for direct
  contributions, so an assistant revising its own person's claim or link is accepted
  immediately; anyone else's stays a proposal. Carried links are new `LINK_EVIDENCE`
  entries by whoever affirms the corrected text (the reviser for own work, the
  acceptor for a proposal), each noting the link it carries.
- Acceptance scope (owner decision, conservative): the applier admits any different
  principal; the connector and the page admit the principal of every touched claim,
  anyone named when that principal is anonymous, and moderators. New connected
  assistants get `allowed_actions: [ACCEPT]` in their delegation; older connections
  are told to reconnect. Declining is leaving a proposal pending; there is no
  `REJECT`, and proposals do not expire (both reserved).
- Blind hand-off. `open_task` dedupes against open or leased tasks of the same kind
  on the target, needs a location for `EVIDENCE_VERIFICATION`, refuses anonymous
  callers, and `Tasks::Lease` never gives a task to the contributor or principal that
  opened it.
- Unchanged: invalidation, quarantine, takedown, and audits stay human; an
  assistant cannot retract anything, only revise it.
- Constitutional Test (history, visibility): 1 more traceable (every correction is a
  signed entry pointing at what it corrects); 2 yes; 3 no; 4 no; 5 yes, the old
  entry stays and is shown; 6 yes; 7 yes; 8 yes, acceptance needs a different
  principal and is itself logged; 9 yes; 10 yes.
- The link to paste (owner request, 2026-09-18): a check ends with one line the
  person can paste where they were going to post. `record_investigation` takes an
  optional `statement` (the exact text they wanted checked) and every recording
  creates an `Investigation` row, an index over log content like receipts, with a
  public page at `/investigations/:id` showing what was asked, each claim's plain
  headline and say-instead line read live from the log, the sources read, and a
  1200×630 PNG for link previews. The result carries `share_line` ("Checked in
  Galedra: <headline> <url>", or the claim count when the claims' headlines differ),
  and the rules, the skill, and the tool note tell the assistant to end its reply with
  it verbatim on the last line. Existing claims carry a `share_line` to their card in
  `get_claim`, `search_claims`, and `fetch`. Nothing about scoring or the log changes.
- The number on the share line (owner request, 2026-09-18, asked for as "98% accurate
  according to x model"): the share line, the check page, the claim card page, and both
  PNGs now carry the probability, in the only form the rules allow: `0.9800 under
  ledger-default@0.1.0 at snapshot 412`, next to the state and the review-check count,
  and absent when the state carries none. "Accurate" and "% true" are not used: Article
  XXII forbids presenting a computed probability as a property of reality, 06 §4 rule 1
  keeps the number off the headline, and the vocabulary rule in CLAUDE.md fixes the
  form. Percent formatting or the word "accurate" would be a spec change to 06 §4 and
  the vocabulary, reserved for the owner. The card hash gains `stated` so every
  surface says it the same way.
- The whole statement (owner feedback, 2026-09-18): a five-claim meme came back as a
  two-claim check page, because the assistant recorded the two new claims and only
  read the three that existed. The rules, the skill, and the `attach_to` description
  now say every claim the statement makes goes into the one record call, existing
  ones by reference, opinions as `NORMATIVE`, calls to action left out. The check
  page and its share line lead with a verdict for the statement as a whole
  (`Investigations::Verdict`): a rule-based headline in the plain vocabulary read from
  the claims' states, the counts behind it, and, when every checkable claim has a
  probability, their product stated with model and snapshot and labelled as the
  figure for all claims holding at once under independence. Claim scores are
  untouched; the verdict is display composition, reversible, and never a percentage.
- Validity badges (owner decision, 2026-09-18, departing from 06 §4 rule 12): the
  check page's claim-by-claim section shows each claim first, then one of ten SVG
  badges coloured from green through amber to red with a glyph and a label:
  Strongly, Mostly, or Leans supported; Evidence mixed; Leans, Mostly, or Strongly
  against; Not checked yet; Not a checkable fact; Withheld by moderation. The level
  comes from the assessment state, split by probability at 0.9 and 0.1 where the
  state is wide (`Cards::Badge`). Rule 12 forbids colour-coding claims and badges of
  this kind; the owner chose them for the page people paste into social media, and
  they appear nowhere else (claim pages, cards, and the API stay neutral). The labels
  keep the evidence wording rather than "true" or "false", which Article XXII rules
  out; the owner asked for "mostly true" and "completely false" and may still choose
  those words, which would need a constitutional amendment under Article XXV. 06 §4
  rule 12 should be revised by the owner to name this exception.
- Guidance in results, not descriptions (owner question, 2026-09-18): hosts cache the
  tool list from the moment of connection and refresh it on their own schedule, so
  rule text in descriptions goes stale until a person reconnects, while results are
  read fresh on every call. The connector now returns a versioned `guidance` block
  with every result (the check rules on search, read, and record; the task procedure
  on task tools; the correction rules on correction tools), the descriptions are cut
  to what the tool is, and the first tool's description says the guidance is fresher.
  Tool names and input schemas are treated as an interface: additive, batched into
  releases, since only those still need a reconnect. `tools/list_changed` is not
  sent: it needs the streaming channel Galedra does not serve and would not refresh a
  host's stored catalog anyway. The FAQ says when a reconnect is needed.
- Landing animation keeps evolving (owner feedback, 2026-09-18): growth stopped at a
  fixed cap of 130 nodes because births were refused there and only old leaves were
  retired, one every few seconds. The cap now follows the window (about one node per
  3300 px², 140 to 700), births never stop, and above the cap the oldest nodes go at
  the pace new ones arrive, fading over seven seconds. Branches turn inward near an
  edge instead of being clamped to it, which had piled nodes along the margins once
  the graph was dense. Decorative only; nothing reads ledger data.
- Assistants can say what they could not do (owner request, 2026-09-18): a
  `request_feature` tool records, in the assistant's own words at the moment it fell
  short, what the person asked, what it needed, and the tool or field it expected.
  The rows live outside the log (untrusted text), repeats within 30 days are counted
  on one row, ten a day per assistant, and only moderators see them, at
  `/feature_requests` or through `bin/rails features:report`. The assistant is told it
  can at three points: the tool list, a hint on every refusal, and the guidance that
  rides on every result. Alongside: one structured log line per tool call (tool,
  outcome, error codes, duration, caller kind, argument keys; never claim text), a
  `caller` note on reads so an assistant never guesses whether it is connected under
  a name, and `search_claims` by `source_id` for "what else cites this source", both
  of which today's transcripts had shown assistants wanting.
