# Stage 45 — A preliminary result while the sources are read

**Status:** built 2026-10-05 · tagged `stage-45-preliminary-result` · the owner took all three decisions on 2026-10-05 (marked **Owner**)

**Tag:** `stage-45-preliminary-result` · **Spec:** 02 §1.1 and §3 (contributions and
projections), 04 §5 (packets), 06 §4 (display rules), 06 §5 (pages), Articles I (claims are
not truth), VI (unknown is a valid conclusion), XIV (contributors, not oracles), XIX
(transparency over persuasion), XXII (reveal our own weaknesses), Invariants 7 (AI is never
evidence by itself), 10 (summaries restate the graph), 11 (untrusted text stays inert), 16
(answers first), 17 (determinism is not objectivity), 18 (Galedra runs no model)

## Where this comes from

The owner, 2026-10-05: a frontier assistant asked to fact-check something answers in under
thirty seconds, and the answer can be pasted into the comments where the claim was met. The
same check through Galedra takes about thirty minutes before there is a link to paste,
because the assistant reads every source before it records anything. The proposal: record
the assistant's own first reading at once as a **preliminary result**, make that what a
person sees on following the link, and then test each assertion in it against sources. For
investigations only; outlines are untouched.

## What already exists, so this stays small

**Done ahead of this stage, 2026-10-05 (owner):** the statement a check holds was capped at
2,000 characters while `Guidance::SIZE` sends anything under about 3,000 words to one
`record_investigation` call, so a pasted passage had to be cut or summarised to fit. The cap
is now 20,000 characters (`Investigation::MAX_STATEMENT_CHARS`); an outline's statement, its
title and link, stays at 2,000. The check page shows a long statement's opening words and
the whole text behind one click; the share line, link preview and card image were already
excerpts. Guard: `spec/requests/share_link_spec.rb`. The same day, the guidance and the skill
changed to search one claim at a time: `Claims::Search` requires a match to contain at least
half the query's distinct words, so a paragraph searched whole matched nothing and every
claim in it looked new.

Most of the fast path is already possible. `Investigations::Validate` requires claims, not
evidence: a bundle of claims with no sources records today, the claims sit at
`INSUFFICIENT_EVIDENCE`, `OPPOSING_EVIDENCE_SEARCH` and `QUALIFIER_CHECK` open on each, and
Stage 34 lets the same assistant work those routine checks on its own claims. Evidence added
later with `attach_to` or `add_evidence` lands on the same claims, and the check page reads
each claim live, so it fills in as sources arrive.

What is missing is only **a home for the assistant's own reading**. Today that reading lives
in the chat and nowhere else, so the link, opened before any source is read, shows a column
of "not checked yet" and nothing a person could paste. The thirty minutes are a consequence
of `Guidance::SIZE` ("do the whole check now ... only when you can read every source it needs
right now"), not of anything the server enforces.

## The rules this stage is built on

1. **A preliminary result is an attributed contribution, not a verdict.** Article XIV: every
   judgment that needs a model "shall enter it as an attributed contribution open to audit".
   It is signed, in the log, projected by `Ledger::Apply`, reproduced by replay, and open to
   takedown like any contribution. It is **not** a column on `investigations`, which is
   outside the log.
2. **It never reaches a score.** Not `Scoring`, not `Investigations::Verdict`, not
   `Cards::Badge`, not the figure, not `Cards::Plain`, not `Investigation.summary`. It is
   display composition beside them. The scoring configs do not learn it exists. `MODEL_OUTPUT`
   evidence already weighs 0; this is not evidence at all, so it is not recorded as evidence.
3. **It never reaches a task packet.** A verifier told "the assistant expected this to be
   false" is anchored before reading anything. `Tasks::BuildContext` already includes only
   named fields and never notes; the preliminary falls under the same rule, and a spec proves
   it (Invariant 11).
4. **It is labelled for what it is, everywhere it travels.** An assistant's reading from what
   it already knew, before any source was read into Galedra. Article I: an AI generating it
   does not make it true, and the share line is the thing that leaves the site.
5. **It gives way to evidence, and the disagreement stays visible.** Once a claim has a state
   other than `INSUFFICIENT_EVIDENCE`, Galedra's reading leads and the preliminary moves
   beneath it. Where the two disagree, the page says so rather than quietly replacing one
   with the other (Article XIX). A preliminary that sources later overturned is information
   about how far a thirty-second check can be trusted.

## Deliverables

### 1. The action type

**`CREATE_PRELIMINARY_RESULT`**, epistemic, one per claim (the granularity of every other
bundle entry, so takedown and audit act on one claim's reading). Payload:

- `claim_id`;
- `expectation`, a closed list (**Owner**, decided 2026-10-05, see below): `EXPECTED_TO_HOLD`,
  `EXPECTED_TO_HOLD_IN_PART`, `EXPECTED_NOT_TO_HOLD`, `NO_EXPECTATION`;
- `rationale`, at most 600 characters, untrusted text, rendered escaped and shown as the
  assistant's words;
- `leads`, at most five URLs the assistant cited. Never fetched by the server (Invariant 11),
  shown as "links the assistant cited; Galedra has not read them", never in a packet;
- `model`, the model that produced the reading, as the assistant declares it.

The model is carried in the payload rather than read from the envelope's `software` object,
for two reasons. Stage 27 measured that object as unusable today: 173 of 600 sampled
contributions carry it, and `model_id` was `"oauth"` 93 times. And in the paste flow
(`/investigations/new`) the signer is the browser session's token, so `software` could name
nothing about the assistant that drafted the bundle. Stage 27's rule applies: a declared
model is a claim about itself, stored and shown as declared, never verified. Projection
`preliminary_results`, windowed like every projection. Refused on a claim placed in a
section (outlines are out of scope) and on a `NORMATIVE` claim, whose page already says it is
not a checkable fact.

Spec edits in the same commit: 02 §3.6 (the action list), 02 §3 (the projection), 04 §5
(excluded from packets), 06 §4 (the display rule below), `REVIEW-NOTES.md`, and
`build-full-spec.sh`.

### 2. The bundle

`record_investigation` gains `preliminary` on each claim entry:
`{ expectation, rationale, leads }`. The MCP tool schema and `Api::Openapi`
(`InvestigationBundle` is read from the tool's `inputSchema`) change in the same commit;
Stage 42 refuses any call that does not match the schema it was handed. `Validate` refuses
`preliminary` on a sectioned claim.

### 3. The check page

**Which preliminary belongs to which check.** Claims are shared: `attach_to` puts an existing
claim in a new check, so one claim can carry preliminaries from several checks, and
investigations live outside the log. `Investigation` therefore gains
`preliminary_contribution_ids`, an outside-the-log pointer into the log of the same shape as
`claim_ids`, set by `Investigations::Record` from the bundle. The check page shows only its
own; the claim page (§6) shows them all.

- Each claim card while the claim is `INSUFFICIENT_EVIDENCE` with a preliminary: the
  expectation in plain words, the rationale, the leads, and a label that cannot be mistaken
  for the badge — **"Preliminary · an assistant's first reading (model as declared), not yet
  checked against sources."** No badge from the ten-level scale, no figure. The badge scale
  belongs to scores.
- Once the claim has another state: the badge and headline lead as today; beneath them,
  "Preliminary: expected to hold up." When the expectation and the state point opposite
  ways, the line says so: "The first reading expected this to hold up; the sources so far
  lean against it."
- The top card, while every checkable claim is preliminary-only, reads the expectations by
  the same counting rule `Verdict` uses, in words and never as a badge: "An assistant expects
  three of these four parts to hold up; none has been checked against a source yet." No
  separate overall judgment is stored: the statement as a whole is not a log object, and a
  count of the parts says what they add up to without a second opinion.
- The og:image card shows a "Preliminary" stamp in place of the badge.

### 4. The share line

`Cards::ShareText` gains a preliminary form while every checkable claim is preliminary-only.
**Owner, decided 2026-10-05:** it carries the expectation, labelled in the same line:
"Preliminary (AI, not yet sourced): expected to mostly hold up · <link>". The alternative, the
link and "being checked" only, was set aside: the paste would carry nothing, and a person
given nothing to paste goes back to pasting the assistant's own answer, unlabelled and with no
link to where it is being checked. Once any claim is scored, the share line is today's, built
from scores alone.

### 5. Guidance

`Guidance::SIZE` and `Guidance::CHECK` gain the fast path, and `Guidance::VERSION` is bumped.
The skill is untouched (`spec/lib/skills_spec.rb`).

- For a statement under the size rule: split it into atomic claims, search Galedra for each
  claim (one query per claim, never the whole statement; in force since Guidance
  `2026-10-05.1`), record them at once with `preliminary` on each and no sources, attaching
  the ones that already exist, and hand the person the share line.
- Never describe a preliminary result as the result, and never repeat its expectation
  without saying it is unsourced.
- Then the sourcing. **Owner, decided 2026-10-05:** the assistant ends its turn after the
  preliminary, with the share line, and offers to source each claim; it does not carry on in
  the same turn. In a chat the person sees the reply only when the turn ends, so carrying on
  gives back the thirty-minute wait; and the routine checks are already open for anyone if the
  person never comes back. The cost is accepted: while few people work the queue, a check
  nobody returns to stays preliminary for a long time, and the page says so.

### 6. The claim page

A claim's page lists every preliminary result recorded on it, attributed, beneath the
evidence, in the same two forms as the check page.

## Acceptance

1. A bundle of three claims with `preliminary` and no sources records in one call, returns a
   share line, and the check page shows three preliminary cards and no badge.
2. Adding counted evidence to one claim moves that card to its scored form with the
   preliminary beneath; a contradicting source under `EXPECTED_TO_HOLD` shows the
   disagreement line.
3. A spec scores a claim with and without a preliminary result at the same seq under both
   models and gets byte-identical traces.
4. A spec builds every task packet for a claim carrying a preliminary result and finds
   neither its rationale, its leads nor its expectation in the bytes.
5. `preliminary` on a sectioned claim is refused with the field and the remedy.
6. `ledger:replay` reproduces `preliminary_results` row for row.
7. The share line for a preliminary-only check reads "Preliminary (AI, not yet sourced):
   expected to …" with the link, and carries no badge; the og:image carries none either and
   says "Preliminary".
8. Two checks that share a claim through `attach_to`, each with its own preliminary on it,
   each show only their own on their check page; the claim page shows both.
9. The guidance served on every result tells the assistant to end its turn after the
   preliminary pass with the share line and an offer to source each claim, and a spec on
   `Guidance` pins that sentence.

## Constitutional Test (visibility and selection)

1. **More traceable?** Yes: a reading that today exists only in a chat transcript becomes a
   signed, attributed record beside the claims it is about.
2. **Preserves the evidence chain?** Yes. Nothing in it is evidence, and nothing in the chain
   changes.
3. **Gives an identity or a model authority over evidence?** No. It never touches a score or
   a packet, and the model is shown as declared.
4. **Hides uncertainty?** No, provided rule 4 holds: the label says unsourced wherever it
   appears, and the page states the disagreement when sources turn against it. This is the
   question to argue with at review.
5. **Keeps unknown explicit?** Yes. `NO_EXPECTATION` is a valid preliminary, and the claim's
   own state stays `INSUFFICIENT_EVIDENCE` until evidence arrives.
6. **Open to audit and correction?** Yes: a contribution like any other, open to threads,
   reports and takedown.
7. **Resists capture?** Yes. It cannot move a score, so flooding preliminaries buys nothing
   but a visible label.
8. **Reproducible?** Yes, a projection of signed contributions.
9. **Separates shared and personal?** Yes. It is a shared, attributed contribution, not a
   personal assessment, and is labelled as one assistant's reading.
10. **Reveals our own weaknesses?** Yes, and usefully: preliminary against eventual state, per
    declared model, is a standing measure of how far a thirty-second check can be trusted.
    That comparison is left for Stage 44's accuracy benchmark, not built here.

## Owner decisions

All three were taken on 2026-10-05, each as proposed.

- **The expectation vocabulary:** the closed list of four in §1, deliberately not the badge
  labels or the state names, so a preliminary can never be read as a score. Free text quoted
  as the assistant's was set aside because it cannot be counted on the top card, compared
  with a later state to show a disagreement, or measured against outside verdicts; the
  600-character `rationale` carries the nuance.
- **The share line** (§4): it carries the expectation, labelled as unsourced and an AI's.
- **The turn** (§5): end the turn with the share line and offer to source each claim.

Stage 44 G2 proposes a feature freeze until a first audience uses the node weekly. This is a
new capability; the case for it under that rule is Stage 44's own principle, "cheap to try".
A thirty-minute wait before there is anything to paste is the first thing a new user meets.

## What remains after this stage

The per-model agreement measure in question 10, and any use of it, which waits on Stage 44's
accuracy benchmark.

## How it closed (2026-10-05)

### What was resolved

Every deliverable (§1 to §6) and acceptance criteria 1 to 9. An assistant records each claim
with its own first reading in the same `record_investigation` call that records the claims,
and gets the link back at once. The check page, its card image and its share line lead with
that reading, labelled as an AI's and unsourced, until evidence gives a claim a state of its
own. The reading never reaches a score or a packet.

### How

- **The action type.** `CREATE_PRELIMINARY_RESULT`
  (`app/services/ledger/appliers/create_preliminary_result.rb`) projects into
  `preliminary_results` (`db/migrate/20261005200000_create_preliminary_results.rb`,
  `PreliminaryResult`). It is registered in every list a new epistemic type has to be in:
  `Ledger::ActionTypes::EPISTEMIC`, `Ledger::Appliers::REGISTRY`,
  `Contribution::PROJECTION_MODELS` and `PROJECTIONS_BY_ACTION` (held by
  `spec/models/contribution_spec.rb`), `Scoring::Watermark::NONE`,
  `Ledger::Redaction::REDACTABLE` (`rationale`, `leads`, `model`) and
  `Attribution::Participants`. Two of those fail silently when missed. Without the watermark
  entry, a twenty-claim first pass would have marked every claim on the node twenty times and
  undone Stage 38. Without the redaction entry, the first takedown of a reading would have
  raised `KeyError`.
- **The bundle.** `preliminary: { expectation, rationale, leads, model }` sits on each claim
  of `record_investigation`'s input schema, so the OpenAPI document carries it too.
  `Investigations::Validate.check_preliminary` refuses a bad one under the bundle's own path,
  such as `$.claims[0].preliminary`. The applier holds the same rules for a direct write
  (`PRELIMINARY_NOT_FOR_OUTLINES`, `PRELIMINARY_NOT_CHECKABLE`).
  `Investigation#preliminary_contribution_ids` records which readings belong to which check.
- **The display.** `Investigations::Preliminary` decides whether a check is preliminary:
  every checkable claim is at `INSUFFICIENT_EVIDENCE` and at least one carries this check's
  reading. It also composes the top card's count, the share line's few words, the line
  beneath a scored claim, and the disagreement sentence. Its consumers are
  `app/views/shared/_preliminary.html.erb`, the check page, the claim page's "Preliminary
  readings", the og tags, `Cards::StatementImage` and `Cards::ShareText.preliminary`.
  `Verdict`, `Investigation.summary`, the badge and the figure are computed exactly as before.
- **The guidance** is version `2026-10-05.2`.
  - `Guidance::SIZE` no longer says "and you can read every source it needs right now". That
    clause was where the thirty minutes came from.
  - `Guidance::CHECK` describes the two passes.
  - `Guidance::END_TURN` is the stop-and-offer sentence.
  - `Guidance::MAX_CHECK_WORDS` is the one size number, which Stage 46 reads.
  - The `record_investigation` description names the first pass.
  - The skill is untouched.
- **The spec.** 02 §3.3 (the table) and §3.6 (the type), 04 §5 (excluded from packets), 06 §4
  rule 13 and §5 (the claim page), 13's rows for XIV and XIX, and `REVIEW-NOTES.md` entry P.
  `FULL-SPEC.md` was regenerated. The reference scorer still prints `ALL PASS`, since nothing
  in 03 changed.
- **The guard.** `spec/requests/preliminary_result_spec.rb` has one example per acceptance
  criterion, and acceptance 6 also takes a reading down.
  - Acceptance 3 builds the scoring input before and after a reading is appended, finds the
    two equal, and gets the same trace hash from each under every released model. It also
    checks that the watermark did not move.
  - Acceptance 4 builds every claim packet type and finds no expectation word, rationale or
    lead in the bytes.

**Decided while building**, each the simplest reversible reading:

- The rationale is required. The plan capped it at 600 characters without saying whether it
  could be empty, and a reading with no reason is an assertion nobody can audit. The model is
  optional and shown as "model not declared" when absent.
- A reading is accepted on the same rule as the claim it sits on: a person, or an assistant
  with direct work. TAG_CLAIM's own-claim rule was not copied. A reading on someone else's
  claim is attributed and moves nothing, and the plan wants two checks sharing a claim to
  carry a reading each.
- Disagreement is flagged only for opposite directions: expected to hold under a state
  against, or expected not to hold under a state for. "In part" never disagrees.
- The statement's few words follow `Verdict`'s counting rule:
  - all expected not to hold gives "expected not to hold up";
  - any expected not to hold gives "expected to hold up only in part";
  - any expected to hold in part gives "expected to mostly hold up";
  - otherwise "expected to hold up".

  A single claim uses its own words.
- `get_claim`, `fetch` and `search_claims` do not return readings. Another assistant reading a
  claim through a tool is the case rule 3 guards against, so tool output stays as it was. The
  claim page shows them to people.

### What remains

- **The per-model agreement measure** in question 10, and any use of it. It waits on Stage
  44's accuracy benchmark, as the plan said.
- **Deployment.** Connected assistants receive guidance `2026-10-05.2`, and with it the first
  pass, only once galedra.org is deployed. That waits on the owner.
- **Real assistants following the new guidance are unmeasured.** No run of the external-agent
  loop in `docs/CONTEXT.md` has been made against this stage. Until one is, how often an
  assistant stops after the first pass, and how often it fills in `preliminary` at all, is
  unknown.
- **The paste flow's example bundle** at `/investigations/new` does not show `preliminary`.
  A person pasting a bundle can include it, but the example does not teach it.
- **Found while building, not this stage's.** A takedown of a contribution whose table has no
  entry in `Ledger::Redaction::REDACTABLE` raises. On 2026-10-05 a `TAG_CLAIM` takedown in
  the test suite raised `KeyError: key not found: "claim_topics"`. The same gap is expected
  for sections, placements, inferences and source retrievals but was not run. Those tables
  also lack the `redacted_by_seq` column that `Redaction.apply!` writes. This stage gave
  `preliminary_results` both, and its spec takes one down.


### Code review, 2026-10-05

Found after the stage closed and fixed the same day. Each fix has an example in
`spec/requests/preliminary_result_spec.rb` that fails against the code above.

- **A taken-down reading still spoke for the check.** Redaction clears `rationale`, `leads`
  and `model` but keeps `expectation`, and `Investigations::Preliminary.reading` counted it.
  The share line, the og title, the card and the top count went on repeating a reading
  whose own card said it was taken down. Readings with `redacted_by_seq` now keep their stub
  beneath the claim and are left out of the whole; `beneath` and `declared` say "taken down".
- **Who recorded each reading was loaded per claim** on the check page: a contribution and a
  contributor for every card (two statements per claim). The controller preloads them for
  the set, as `ClaimsController#show` does. The example counts `contributors` statements for
  a two-claim and a five-claim check and requires them equal.
- **The bundle check had drifted from the applier.** `check_preliminary` did not cap a
  lead's length or refuse an `attach_to` claim already placed in an outline, so the applier
  refused both mid-transaction under `$.payload.…`, which does not say which claim. Both are
  now refused under `$.claims[i].preliminary`.
- **One part "in part" read as "mostly".** `phrase` took its one-reading shortcut before
  setting aside `NO_EXPECTATION`, so `[IN_PART]` said "in part" and `[IN_PART,
  NO_EXPECTATION]` said "expected to mostly hold up".
- **The share card scored every claim twice**, once per card and once for the set, and built
  the scored headline even when it drew the preliminary one. It now scores once and builds
  the cards only when it uses them.

**Reported, not changed.** A check stays preliminary while every checkable claim is at
`INSUFFICIENT_EVIDENCE`, as decided above. A claim whose only counted evidence is `QUALIFY`
or `NEUTRAL`, or weighs nothing, sits there too. Its check then says "not yet checked
against sources" and "None has been checked against a source yet" after a quoted source was
read and linked. Whether the rule should look at the trace's counted links, or the words
should change, is the owner's call.
