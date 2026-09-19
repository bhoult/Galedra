# Stage 29 — Noting a logical fallacy

**Status:** planned · tag will be `stage-29-fallacy-notes`

**Tag:** `stage-29-fallacy-notes` · **Spec:** 02 §1.1 and §3 (contributions and projections),
04 §2 (task types), 05 §9 (audits), 06 §4 (display rules), Articles V (contradiction is
preserved), XI (identity does not replace evidence), XIV (contributors, not oracles),
XVII (normative claims are not empirical ones), XVIII (political neutrality is structural),
XIX (transparency over persuasion), XXII (reveal our own weaknesses), XXIII (no conclusion
is immune from re-examination), Invariants 4 (deterministic scores), 7 (AI is never
evidence by itself), 8 (reputation is not a scoring input), 11 (untrusted text stays inert)

Goal: let a reader see where a statement's *reasoning* goes wrong, not only where its facts
do. A meme can be factually unimpeachable and still be a straw man. Today Galedra has
nothing to say about that, so the part of a statement that does the persuading passes
unremarked.

A note names one fallacy, points at the exact passage it applies to, carries one sentence
saying why *that text* fits, and shows a small icon with the fallacy's name. Clicking the
icon opens the general definition. Notes appear on investigation pages and on outline
sections.

## The line this stage must not cross

This is the most easily abused thing yet proposed here. "That's a straw man" is a
judgement about someone's argument, delivered with an icon, and icons are read as verdicts.
Three failures are close at hand, and every deliverable below is measured against them.

**A fallacy is not a refutation.** An argument can be badly made and its conclusion still
true; treating the label as a rebuttal is itself a fallacy. The page must say so where the
note is, not in a footnote, and a note must never change a claim's state, probability or
trace. The scoring configs do not learn this feature exists (Invariant 4).

**A fallacy attaches to a passage, never to a person.** The anchor is a `SourceLocation`,
the same quoted-and-hashed passage that evidence uses, so what is being described is
exactly the text and the text is verifiable. No note names an author, and the existing rule
against claims about identifiable private individuals applies unchanged.

**A fallacy note is a contribution, not a ruling.** It is signed, attributed, auditable and
disputable like everything else (Articles V, XXIII). One assistant's opinion that something
is whataboutism is model output, which Invariant 7 says is never evidence by itself, so a
note reaches the page only once independent principals agree, the same shape
`Reviews::Consensus` already uses for affiliations. A node with no paid moderators settles
this the way it settles everything else.

Article XVIII is the reason to be strict rather than cautious: fallacy labelling is a
standard partisan weapon, and a closed vocabulary with per-passage evidence and independent
confirmation is what stops this becoming one.

## The vocabulary

`config/fallacies.yml`, data like `config/topics.yml` and `config/affiliations.yml`, so
adding one is not a code change. Each entry: a slug, a display name, the general definition
shown in the modal, an example, the icon file, and where it is commonly confused with a
neighbour. Closed list, `UPPER_SNAKE_CASE` slugs, no free-text fallacy names ever.

A first set, chosen for being well defined and hard to weaponise:

| Slug | Name |
|---|---|
| `AD_HOMINEM` | Attacking the person |
| `STRAW_MAN` | Arguing against a weaker version |
| `FALSE_DILEMMA` | Only two options offered |
| `HASTY_GENERALISATION` | Too few cases |
| `POST_HOC` | After it, therefore because of it |
| `CIRCULAR` | Assuming what it sets out to show |
| `SLIPPERY_SLOPE` | A chain of consequences asserted, not shown |
| `APPEAL_TO_AUTHORITY` | Because someone said so |
| `APPEAL_TO_EMOTION` | Feeling offered in place of reason |
| `TU_QUOQUE` | Answering a charge with another charge |
| `EQUIVOCATION` | One word, two meanings |
| `CHERRY_PICKING` | Selecting the cases that fit |
| `LOADED_QUESTION` | A question with the answer built in |
| `BURDEN_SHIFTING` | Asking the doubter to disprove it |
| `FALLACY_FALLACY` | Treating a bad argument as a false conclusion |

`FALLACY_FALLACY` is in the list deliberately. It is the mistake this feature invites, and
it should be as nameable as the rest.

Two of these overlap with what the ledger already measures and the entries must say so:
`CHERRY_PICKING` is what independence groups and evidence coverage exist to expose, and
`APPEAL_TO_AUTHORITY` is close to the reputation question Article X settles. A note that
duplicates a measurement is weaker than the measurement.

## The icons

One pre-made SVG per fallacy in `app/assets/images/fallacies/`, drawn to the display rules
of 06 §4 rule 12: monochrome line work in the existing ink and muted tones, **no red or
green, no ticks or crosses, nothing that reads as a verdict**. `Cards::Badge` is the
precedent and its palette is deliberately not borrowed: a badge says where evidence stands,
and these say nothing about evidence at all. The name appears beside the icon always, never
the icon alone, because an unlabelled symbol is exactly the thing that gets read as a
judgement.

## Deliverables

- **`config/fallacies.yml`** and a `Fallacies` reader beside `Topics`, with `valid?`,
  `find`, and the ordered list for display.
- **`NOTE_FALLACY`**, an epistemic action type. Payload: `source_location_id`, `fallacy`,
  `reason` (one sentence, capped, about the text and not the author), and the existing
  `affirms_not_private_individual`. Projected by `Ledger::Apply` to `fallacy_notes`
  (Invariant 2), windowed like every projection so history answers at any seq.
- **Independent confirmation before display.** A note is recorded immediately and visible
  on the contribution, but shown on an investigation or outline only once
  `Reviews::Consensus` has it: two agreeing principals other than the author, or one
  uncontradicted after the standing interval. Until then it is pending, and the page says
  how many notes are pending rather than hiding the fact.
- **`FALLACY_REVIEW`**, a task type in `Tasks::Types::SPECS`, so confirmation is work the
  task board hands out rather than something that happens only if someone volunteers.
  Outcomes: `CONFIRMED`, `WRONG_FALLACY`, `NOT_A_FALLACY`, `CANNOT_DETERMINE`.
- **Display on the investigation page**: under the statement, each note as icon, name, the
  quoted passage it points at, and its one-sentence reason. Directly beneath the list, in
  the ledger's own voice and not as a tooltip: *a badly made argument can still have a true
  conclusion; these notes say nothing about whether the claims hold.*
- **Display on an outline section**: the same, scoped to that section's source passages, so
  a long speech shows where its rhetoric sits.
- **The modal**: clicking an icon opens the general definition, the example, and the
  neighbours it is confused with. A Stimulus controller, closed by Escape and by clicking
  away, focus moved into it and restored on close, `role="dialog"` and `aria-modal`.
  Without JavaScript the icon is a plain link to that fallacy's entry on a
  `/help/fallacies` page, which is the same text: the modal is a convenience, never the
  only way to read it.
- **The glossary and help**: `/help/fallacies` lists every fallacy with its icon,
  definition and example, linked from Help, and the glossary gains an entry for what a note
  is and is not.
- **The tool**: `note_fallacy` for a connected assistant, and a form on the investigation
  page for a signed-in person. Both go through `POST /api/v1/contributions` like every
  write (Invariant 1).
- **Moderation and review**: the `reason` is contributor-supplied free text, so it goes to
  content review like every other free text, and a note can be quarantined and taken down
  like any contribution.

## Acceptance

1. Scores are untouched: the demo and Watchers goldens are byte-identical before and after,
   and no `ClaimScore` row or trace mentions a fallacy.
2. A note names a passage; a payload naming a contributor, an author or a person is
   rejected at append.
3. A note by one principal does not appear on the investigation page. After two independent
   principals agree it does, and the pending count is visible in the meantime.
4. An unknown fallacy slug is rejected with `SCHEMA_INVALID` naming the closed list.
5. The investigation page states, next to the notes, that a bad argument can have a true
   conclusion.
6. With JavaScript disabled the icon still reaches the general definition.
7. The icons contain no red or green, asserted over the SVG files themselves, and every
   icon is rendered with its name.
8. Replay rebuilds `fallacy_notes` byte-identically.

## Constitutional Test

1. **More traceable?** Yes. It records where an argument's persuasion lives, pointing at
   the exact passage, which is more than the record says today.
2. **Disagreement more inspectable?** Yes, provided the note is disputable, which is why it
   is a contribution and not a verdict.
3. **Hidden authority?** This is the risk. An icon carries more weight than its evidence.
   Mitigated by the closed vocabulary, the per-passage anchor, independent confirmation,
   the name always beside the icon, and a palette that cannot be mistaken for a verdict.
4. **Reputation substituting for evidence?** No. Notes are confirmed by agreement about the
   text, not by who noticed them.
5. **Uncertainty preserved?** Yes: `CANNOT_DETERMINE` is an outcome, and a pending note is
   shown as pending.
6. **Reproducible?** Yes, it is a projection of signed contributions.
7. **Challengeable by an opponent?** Yes, by audit and by a re-review, like any
   contribution.
8. **History reconstructable?** Yes, windowed at a seq.
9. **Shared and personal separate?** Yes; a note is shared and signed, not a personal view.
10. **Would we want this used by people we disagree with?** This is the question the stage
    turns on. A closed vocabulary, a quoted passage, a stated reason and independent
    confirmation are usable by an opponent on our own writing, and should be. If any part
    of the design would embarrass us when turned around, that part is wrong.

## Owner decisions

- The starting vocabulary, and whether `CHERRY_PICKING` belongs at all given independence
  groups already measure it.
- Whether a note may point at a claim's canonical text rather than only at a source
  passage. Claims are the ledger's own wording, so a fallacy there is a fault in the
  extraction, which may be a correction rather than a note.
- How a note interacts with Stage 25 inferences. `INFERENCE_REVIEW` already has a
  `NON_SEQUITUR` outcome, which is the same judgement about the ledger's own recorded
  reasoning rather than about a source. They should probably meet; deciding how is design,
  not implementation.
- Whether the confirmation threshold is two principals or more for the fallacies most open
  to partisan use, `AD_HOMINEM` and `STRAW_MAN` among them.
- Whether a node may turn the feature off entirely, which is a governance power and so
  wants Article XXV treatment before it is built.
