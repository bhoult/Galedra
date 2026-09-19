# Stage 30 — The whole text, readable in Galedra

**Status:** planned · tag will be `stage-30-section-text`

**Tag:** `stage-30-section-text` · **Spec:** 02 §1.1 and §3.2 (contributions, sources and
locations), 02 §6 (canonical JSON and hashing), 06 §4 (display rules), 13 §Stage 17 (source
retrieval), 14 §P1 (mirrors), Articles VII (attribution), XIII (corrections do not erase
history), XIX (transparency over persuasion), XXIII (re-examination), Invariants 2
(projections are derived), 11 (untrusted text stays inert), 18 (the ledger runs no model)

Goal (owner request, 2026-09-19): a person reading an outline can read the source. A leaf
holds the text of its own passage; a branch's text is its leaves in order; the root shows
the whole transcript. The assistant is asked to clean what it records: paragraphs where the
speaker paused, and obvious transcription errors put right.

Today the skill says the opposite. It asks for "a short quoted anchor of at most 300
characters, the first words of the leaf" and states "do not paste the transcript into
Galedra; it is never stored." The Moonshots outline followed that exactly: 35 anchors, 72
to 222 characters each, 4,514 characters standing in for an episode of several hours. The
page then labels one of those an anchor as "the passage this section covers", which is the
misreading that prompted this.

## The line this stage must not cross

**A cleaned transcript is not a quotation, and the two must never be the same field.**

The excerpt on a `SourceLocation` is hashed, and Stage 17 retrieval goes and checks that
those exact words appear in the fetched source. That check is the reason a quotation in
this record can be trusted at all. The moment an assistant is asked to fix transcription
errors and insert paragraph breaks, what it produces is no longer what the source says: it
is a reading of what the source says, produced by a model, and the invariants are explicit
that model output is never evidence by itself.

So this stage adds a second thing rather than changing the first:

| | What it is | Hashed | Checked against the source | Shown as |
|---|---|---|---|---|
| **Anchor** | the leaf's opening words, verbatim | yes | yes, by retrieval | a quotation |
| **Reading** | the leaf's full text, cleaned | yes, over the cleaned text | no | a transcription, attributed and dated |

The anchor stays exactly as it is and keeps doing the verifying. The reading is new,
carries `locator_type: TRANSCRIPTION`, which this project already means "text an assistant
read off something", and is displayed as a transcription with the assistant that made it
named. A reading is a contribution like any other: signed, auditable, correctable by a
later one, and never presented as the speaker's exact words.

If that distinction is collapsed, Galedra becomes a place where edited speech is attributed
to real people with a hash beside it, which is the failure this whole project exists to
prevent.

## Deliverables

- **A reading per leaf.** `CREATE_SOURCE_LOCATION` with `locator_type: TRANSCRIPTION`, the
  same locator as the anchor so the two point at the same span, and the cleaned text as its
  excerpt. `sections.reading_location_id` beside the existing `location_id`, written by
  `Ledger::Apply` like every projection.
- **Branches compose, they do not copy.** A branch's text is its descendants' readings in
  document order, assembled at read time. Nothing is stored twice, so a correction to one
  leaf corrects every level above it, and Invariant 2 holds: the composition is derived.
- **Display.** A leaf shows its reading in full. A branch shows its leaves' readings in
  order, each under its heading. The root shows the whole transcript that way. The anchor
  stays on the page as the quotation it is, next to a line saying which is which.
- **A cleaning rule in the skill**, and it has to be narrow, because "fix errors" is an
  invitation to rewrite. Proposed wording: break the text into paragraphs where the speaker
  changes subject or another speaker begins; correct plain transcription errors, meaning
  misheard words, mangled proper nouns, and punctuation; mark a word you cannot make out as
  `[unclear]`; and change nothing else. Do not tidy grammar, do not remove repetition or
  filler, do not summarise, do not reorder. A speaker who misspeaks stays misspoken.
- **The size rule changes with it.** Today's rule exists because transcripts were not
  stored; it is now a question of what a node can carry, so it moves to a byte budget per
  contribution and per outline rather than a flat prohibition.
- **Capacity, honestly.** An episode is on the order of 100 KB of text where 4.5 KB was
  stored before, roughly twenty times. That lands on the contributions table, on every
  mirror, and on `bench:report`. The Stage 26 numbers were taken before this and will need
  taking again.
- **Retrieval learns the difference.** Stage 17 checks anchors, not readings, and records
  a reading as unchecked rather than as failing to match. A reading that does not resemble
  its anchor is a weakness worth surfacing, not a verification failure.

## Acceptance

1. A leaf's full text is on its page, and the root's page holds every leaf's text in
   document order.
2. A branch stores no text of its own: emptying the leaves empties the branch, and
   correcting one leaf changes what the root shows.
3. The anchor is unchanged and still verifies. Retrieval reports `VERBATIM` for anchors
   after this stage exactly as before.
4. A reading is never labelled a quotation anywhere in the interface, and names the
   assistant that made it and when.
5. Replay rebuilds readings byte-identically.
6. `bench:report` is run again at a corpus with readings, and `docs/HOSTING.md` §3 is
   updated with what a text-heavy node costs.

## Constitutional Test

1. **More traceable?** Yes. A reader can now read what a claim was extracted from rather
   than a sentence standing in for four minutes of speech.
2. **Disagreement more inspectable?** Yes, and materially: an extraction can be argued with
   only if the text it came from is there.
3. **Hidden authority?** This is the risk, and it is the reason for the two-field split. A
   cleaned transcript presented as a quotation would be a model's words wearing a source's
   authority.
4. **Reputation substituting for evidence?** No.
5. **Uncertainty preserved?** Yes: `[unclear]` is required rather than optional, and a
   reading is marked as unverified against the source.
6. **Reproducible?** Yes; a projection of signed contributions.
7. **Challengeable?** Yes. A reading can be audited and superseded like any contribution,
   and the anchor gives an auditor a fixed point to check it against.
8. **History reconstructable?** Yes, windowed at a seq like every projection.
9. **Shared and personal separate?** Unchanged.
10. **Used by people we disagree with?** Storing someone's words at length, edited by a
    machine, is a power worth being uneasy about. The split, the attribution, and the
    audit trail are what make it acceptable; without them it would not be.

## Owner decisions

- **Copyright.** A podcast transcript is not ours. The database is offered under ODbL-1.0
  and project-authored records under CC0-1.0, and a third-party transcript is neither.
  Either the licence page gains a carve-out for quoted source text, or readings are held
  under a fair-dealing rationale and excluded from bulk export, or long-form text is
  limited to sources whose licence permits it. This wants deciding before the first
  transcript is public, not after.
- Whether a reading may be recorded for a source the node could not retrieve, where nothing
  can ever check it against anything.
- The byte budget per outline, and what happens at the ceiling.
- Whether `[unclear]` should be a closed marker the schema validates, so a reading cannot
  quietly invent a word.
