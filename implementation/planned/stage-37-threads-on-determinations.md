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

## Not versioned, and not a little bit versioned

A thread is **outside the log and carries no version at all** (owner decision, 2026-09-20).
No `seq`, no snapshot, no model, no goldens, no replay. It is mutable in the way
`bug_reports` and `personal_assessments` are mutable, and `bin/rails ledger:replay` neither
knows nor cares that threads exist.

This is worth stating as flatly as possible because the reflex in this codebase is to sign
things, and signing a thread would be wrong twice: it would put unsigned opinion about the
record into the same object class as evidence about the world, and it would make a
conversation replayable, which invites the reading that its turns are findings. Anything in a
thread that deserves to be permanent deserves to be a contribution, and the thread's job is
to produce one.

## Settling: three principals, not two parties

Threads do **not** use the register's opener-and-maintainer shape. A thread is settled when
**three distinct principals agree** (owner decision, 2026-09-20) — not three tokens. Three
tokens of one principal is self-certification, which Invariant 9 forbids by contributor *and*
by principal, and every other settlement rule here already works this way.

The consequence has to be said plainly rather than discovered: **on a node with one working
principal, threads do not settle.** That is the same deadlock content review is in today — 66
items pending, `content_reviews_for_you` permanently 0, because one principal wrote them all.
The owner chose this knowing that, and it is the right trade: a thread that settles because
one person ran three tokens says "three agreed" on a page where that is false, and this
project's whole position is that the reasons are visible and true.

What follows from it:

- The `/admin` escape that content review has is the escape threads have. An admin settles
  one by hand, and the page says settled by an admin rather than by agreement.
- A single-principal node accumulates open threads. That is honest, and the open count
  becomes a real measure of how much of this record nobody else has looked at.
- `Reviews::Consensus` is the existing home for "N principals agree", already used by content
  review and affiliations. Threads take a third `REQUIRED` value rather than a second
  mechanism. Whether a lone uncontradicted turn settles after `ALONE_AFTER` is deliberately
  **not** adopted here: it is available if the owner later wants it, and adopting it silently
  would undo the decision above.

## Unresolved threads are work anyone can volunteer for

An open thread is a piece of work, and the system already knows how to hand work out. But a
thread is not a `Task`: tasks are signed packets in the log with costs, leases and audit
sampling, and a thread is none of that. It gets the lighter mechanism.

- `next_thread` hands an assistant the oldest open thread it has not already spoken on and
  whose subject its own principal did not record — the same two exclusions
  `ContentReview.available_for` makes, and for the same reasons.
- `list_threads` reports `open` and `open_for_you` **both**, because the one-count-read-as-
  another fault was reported three times in one day and this is a fourth surface for it.
- No lease. A thread has no exclusivity to protect: two assistants answering the same thread
  is two opinions, which is what it wants. Leases exist for blind independent verification;
  this is the opposite.
- An assistant that has already spoken on a thread is not offered it again and its second
  turn does not count twice toward the three.

## Reusing what the register proved

`Triageable` and `ReportMessage` carry mechanics worth lifting, and each exists because
something went wrong without it:

- **Whose turn it is, in one glance.** The state badge, in three widths, because "answered"
  read the same for a thread waiting on someone and one already settled.
- **A turn is prose.** 5,000 characters, clipped with notice, never a bare 422.
- **A turn can agree to work not yet done** without pretending the matter is closed.
- **Every step visible**, which is the property that made the register worth having at all.

What does **not** lift is the settlement rule: the register closes when the filer agrees,
threads close when three principals do. So the extraction is a `Threadable` concern holding
the turn-taking and display, with settlement injected — `Triageable` keeps its two-party
rule, threads take `Reviews::Consensus`. If the register's behaviour changes as a result, the
register's specs fail, which is the point.

## Deliverables

1. `Threadable` concern extracted from `Triageable` — turn-taking, clipping, state badge —
   with settlement injected, so the register keeps its two-party rule and threads take
   consensus. The register's existing specs must pass untouched.
2. `determination_threads` and reuse of `report_messages` via a polymorphic parent, or a
   sibling table if the columns diverge — decided by writing the migration, not in advance.
   No `seq` column, no snapshot, nothing versioned.
3. `Reviews::Consensus` gains a third required-count for threads: three distinct principals,
   never three tokens.
4. `open_thread`, `list_threads`, `get_thread`, `respond_to_thread`, `next_thread` on MCP,
   mirroring the report tools an assistant already knows. `list_threads` returns `open` and
   `open_for_you`.
5. The claim page shows threads: open count, how many principals have agreed of the three,
   and each turn with the contribution that answered it where there is one.
6. `/admin` settles a thread by hand, and the page says settled by an admin rather than by
   agreement — the escape a single-principal node needs.
7. `Guidance` gains the rule: a thread is for how the record was made; a disagreement about
   the world is a contribution. `Guidance::VERSION` bumps.
8. Content review covers thread turns.
9. The three findings above, filed as threads on `16fb6733` and its two links, as the
   acceptance fixture.

## Acceptance

1. The register's existing specs pass with no edit after the extraction.
2. Two principals agreeing does not settle a thread; a third does. Three **tokens** of one
   principal do not, and the spec uses three tokens of one principal as its negative case,
   because that is the shape a node like this one actually has.
3. An assistant that has already spoken is not offered the thread by `next_thread`, and a
   second turn from it does not count twice toward the three.
4. A thread naming a contribution shows it inline; a thread closed without one states that
   nothing changed and why.
5. No file under `app/services/scoring/` mentions threads; a claim's probability and trace
   are byte-identical with and without one, at the same seq.
6. `bin/rails ledger:replay` produces identical row and snapshot digests on a database with
   threads and one without: nothing versioned, nothing replayed.
7. The share card and share line for a claim with an open thread are byte-identical to the
   same claim without.
8. Thread activity produces no `ReputationEvent`.
9. A thread turn is queued for content review on creation.

## The Constitutional Test

1. **Does it preserve the reasons?** Yes, and it captures reasons that currently have
   nowhere to live: today they are filed as bugs against Galedra or lost.
2. **Could it manufacture agreement?** No. A thread changes nothing about a claim; only the
   contribution it resolves into does, and that is signed and auditable as usual.
3. **Does it let identity substitute for evidence?** This is the risk, and the reason for the
   line above. A thread turn is not evidence, is never scored, and never leaves the page. The
   answer to a turn about the world is a contribution. Settlement by three distinct
   principals rather than three tokens is the same guard applied to closure: agreement has to
   be between people, not between sessions.
4. **Does it hide anything?** No; it reveals disagreement that is presently invisible.
5. **Is it deterministic and versioned?** Deliberately neither, and that is the decision
   rather than an omission (owner, 2026-09-20): a thread carries no version, no seq and no
   replay, because signing a conversation would put opinion about the record into the same
   object class as evidence about the world. The determinations it hangs on are unchanged,
   which acceptances 5 and 6 pin.
6. **Does it double-count?** No; nothing here reaches a weight.
7. **Is AI being treated as evidence?** No. An assistant's turn is an assistant's turn.
8. **Does reputation leak in?** No. Thread activity must not reach `ReputationEvent`, and
   this is worth a test: "argues a lot" is not "audits well" (Invariant 8).
9. **Can it be audited and reversed?** Threads are append-only in practice — turns are never
   edited — and content review can redact a turn the way it redacts any other free text.
10. **Is anything invented?** No.
