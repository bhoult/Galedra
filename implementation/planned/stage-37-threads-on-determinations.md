# Stage 37 — A thread on a determination

**Status:** planned · tag will be `stage-37-determination-threads`

**Tag:** `stage-37-determination-threads` · **Spec:** 02 §1.1 and §3 (contributions and
projections), 05 §9 (audits), 06 §4 (display rules), Articles V (contradiction is
preserved), XI (identity does not replace evidence), XIV (contributors, not oracles), XIX
(transparency over persuasion), XXII (reveal our own weaknesses), XXIII (no conclusion is
immune from re-examination), Invariants 1 (log first), 8 (reputation is not a scoring
input), 10 (nothing invented), 11 (untrusted text stays inert), 13 (shared and personal stay
separate)

Goal: let two parties disagree about **how a determination was made**, across several
rounds, where the determination is — instead of in the bug register, which is the only place
in Galedra today where that is possible.

## Why, from a run rather than from first principles

On 2026-09-20 a connected assistant checked claim `16fb6733` and produced three findings:

1. The card's `say_instead` read *"Ipsos found 85% in China and 37% in the US agree AI
   products have more benefits than drawbacks"*, while the excerpt it rested on was the
   survey's question stem and carried no figures at all. The numbers were right; a reader
   following them to the source could not see that.
2. `independent_lineages` read 2, and the two contradicting items may both trace to one
   pollster — the second is Stanford's AI Index figure, and that chapter draws from Ipsos.
   It said explicitly that it had not confirmed this and was not asserting it.
3. The two items answer **different survey questions** — *excited by AI products* (38/84)
   and *benefits outweigh drawbacks* (37/85) — and nothing on the card says so. A reader
   sees two figures a point apart about the same two countries and takes them for one
   survey.

Every one of those is a statement about the record. None is a claim about the world. All
three were filed as a **bug report against Galedra**, because that is the only surface here
where a filer and a maintainer can exchange turns until both agree it is settled. The
register earned its keep this way all day; the point of this stage is that the same shape
belongs where the determinations are.

The third finding is the one that could not have been filed any other way. It is not a
defect in Galedra and not a defect in either evidence item — each is accurate about its own
excerpt. It is a defect in what the two say *standing together on one card*, and there is no
object in the system that owns it.

## What a thread is, and the line it must not cross

A thread is **about the record, not about the world.** Its turns say things like: this
statement's figures are not in its excerpt; these two lineages may share an origin; these
two items answer different questions; this excerpt stops one clause short of the sentence
that makes it legible.

**A turn that is about the world is not a thread turn, and the answer to it is a
contribution.** If someone writes "this claim is false", the reply is: record the evidence.
Threads must never become a channel through which unsigned assertions reach a reader who
takes them for findings — that is the whole of Article XI and Invariant 1, and it is the
obvious way this feature goes wrong.

Three consequences, each testable:

- **A thread never reaches scoring.** Not as an input, not as a weight, not as a flag the
  scorer reads. `spec/` asserts no file under `app/services/scoring/` mentions the model.
- **A thread never appears on the share card or in the share line.** It appears on the claim
  page with a count and a link. A share card is what travels without the page attached, and
  a disagreement quoted out of its thread is a rumour with a Galedra URL on it.
- **A thread's text is untrusted and content-reviewed**, like bug reports and personal
  views: `ContentReview::SUBJECTS` gains it, and `Reviews::Consensus` settles it.

## What makes it Galedra-shaped rather than a comment section

**A thread resolves into a signed contribution, or into "no change needed", and it says
which.** That is the difference. A comment section accumulates; a thread is a queue of work
on the record and it empties.

So a turn may name the contribution that answers it — a superseding link with a fuller
excerpt, a new independence group, a qualifying edge, a `TAG_CLAIM` — and the thread shows
that contribution inline, as the answer. Closing without one is allowed and has to be
stated as such: *nothing was changed, and here is why*.

That also gives the honest reading of finding 3 above: the answer is not a code change but a
contribution — an independence group, or a claim edge, or a qualifier saying these are two
questions.

## What can carry one

`Claim`, `EvidenceClaimLink`, `EvidenceItem`, `SourceLocation`, and a `TaskAssignment`'s
result. Not a `Contribution` itself: the log is the thing being discussed, and a thread on an
immutable row would invite the reading that the row changed.

Scores are deliberately excluded. A score is a function of the graph and the model; disputing
it means disputing an input, and the input is what carries the thread. This is worth stating
because "comment on the score" is the first thing anyone will ask for.

## Reusing what the register proved

`Triageable` and `ReportMessage` already carry the mechanics, and every one of them was
built because something went wrong without it:

- **Both sides agree to close.** `ANSWERED` hands it back; only the opener's verdict reaches
  `CLOSED`.
- **Held.** An answer that agrees to work not yet done does not start the timeout
  (`settles: false`), because "if the reporter does not respond and *you think it is
  settled*" has two halves.
- **Silence settles.** `UNANSWERED_AFTER`, so a thread does not wait forever on someone who
  has gone, and it reopens if they come back disagreeing.
- **Whose turn it is, in one glance.** The state badge, in three widths.
- **A turn is prose.** 5,000 characters, clipped with notice, never a bare 422.

The generalisation is the deliverable: lift `Triageable` from the two report models onto a
`Threadable` concern, and let both the register and determinations use it. If the register's
behaviour changes as a result, the register's specs fail, which is the point.

## Deliverables

1. `Threadable` concern extracted from `Triageable`, with the register as its first two
   consumers and no behaviour change (its existing specs must pass untouched).
2. `determination_threads` and reuse of `report_messages` via a polymorphic parent, or a
   sibling table if the columns diverge — decided by writing the migration, not in advance.
3. `open_thread`, `list_threads`, `get_thread`, `respond_to_thread` on MCP, mirroring the
   report tools an assistant already knows.
4. The claim page shows threads: open count, whose turn, and each turn with the contribution
   that answered it where there is one.
5. `Guidance` gains the rule: a thread is for how the record was made; a disagreement about
   the world is a contribution. `Guidance::VERSION` bumps.
6. Content review covers thread turns.
7. The three findings above, filed as threads on `16fb6733` and its two links, as the
   acceptance fixture.

## Acceptance

1. The register's existing specs pass with no edit after the extraction.
2. A thread opened by one principal and answered by another closes only when the opener says
   so, holds when the answerer says `settles: false`, and settles on silence.
3. A thread naming a contribution shows it inline; a thread closed without one states that
   nothing changed and why.
4. No file under `app/services/scoring/` mentions threads; a claim's probability and trace
   are byte-identical with and without one.
5. The share card and share line for a claim with an open thread are byte-identical to the
   same claim without.
6. A thread turn is queued for content review on creation.

## The Constitutional Test

1. **Does it preserve the reasons?** Yes, and it captures reasons that currently have
   nowhere to live: today they are filed as bugs against Galedra or lost.
2. **Could it manufacture agreement?** No. A thread changes nothing about a claim; only the
   contribution it resolves into does, and that is signed and auditable as usual.
3. **Does it let identity substitute for evidence?** This is the risk, and the reason for the
   line above. A thread turn is not evidence, is never scored, and never leaves the page. The
   answer to a turn about the world is a contribution.
4. **Does it hide anything?** No; it reveals disagreement that is presently invisible.
5. **Is it deterministic and versioned?** Not applicable to the thread, which is outside the
   log; the determinations it hangs on are unchanged, which acceptance 4 pins.
6. **Does it double-count?** No; nothing here reaches a weight.
7. **Is AI being treated as evidence?** No. An assistant's turn is an assistant's turn.
8. **Does reputation leak in?** No. Thread activity must not reach `ReputationEvent`, and
   this is worth a test: "argues a lot" is not "audits well" (Invariant 8).
9. **Can it be audited and reversed?** Threads are append-only in practice — turns are never
   edited — and content review can redact a turn the way it redacts any other free text.
10. **Is anything invented?** No.
