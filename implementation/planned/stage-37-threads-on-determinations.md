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

## What settling a thread does, and the one thing it must never do

**Settling a thread does nothing to the scored evidence chain** (owner decision,
2026-09-20). No link is created, superseded, reweighted or grouped by a thread reaching
agreement. A claim's probability, state and trace at a given seq are byte-identical before
and after, and acceptance 5 pins that. Three principals agreeing that a passage is
misquoted does not unquote it; someone has to record a contribution, signed and auditable
like any other, and that act is separate from the thread that prompted it.

What a settled thread does instead is act on **work**, in exactly one of two ways, chosen
by the settling consensus:

- **`INVESTIGATE`** — *raise a new investigation, given the discovered facts.* The thread
  opens work: tasks on the determination it hangs on, carrying the thread as context so
  whoever leases one can read why it exists. The thread has found something that deserves
  checking and says so in the only currency that gets things checked here.
- **`NO_FURTHER_WORK`** — *this no longer needs to be an open work task; it is settled.* The
  open tasks on that determination are cancelled with a stated reason naming the thread, and
  nothing is created. This is how a queue stops asking a question three principals have
  agreed is not worth asking.

Both are about what should be done next, never about what is true. That is the whole
containment: a thread's authority runs to the work queue and stops there, and the queue has
never been a scoring input.

`NO_FURTHER_WORK` is the more powerful of the two and takes the tighter guard: it may cancel
only the open tasks on the determination the thread hangs on, never a task elsewhere, and
never a task already leased or submitted — a worker mid-lease is not overruled by a
conversation it was not in. Cancellation is the existing mechanism with a new
`cancelled_reason`; a cancelled task's history stays readable, as `TARGET_NOT_CURRENT`
cancellations already do.

A turn may still **name a contribution** that someone made in response — a superseding link
with a fuller excerpt, a new independence group, a qualifying edge — and the thread shows it
inline. That is a citation, not the thread's doing: the contribution stands on its own
signature and would count identically if the thread had never existed.

That also gives the honest reading of finding 3 above. *These two items answer different
survey questions and the card does not say so* settles as `INVESTIGATE`: it opens a
`SOURCE_INDEPENDENCE_CHECK` and a qualifier check, and somebody's assistant records the edge
or the group that fixes it. The thread found the problem; it does not get to fix it.

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

**This is a matter of who is connected, not a wall.** A principal is a person's account, so
reaching three means connecting assistants under three accounts, which the owner can do
whenever the node needs it. Measured on this node on 2026-09-20: 3 users, 23 tokens, 13
distinct principals — but 11 of those tokens are anonymous and cannot vote at all, leaving
**two** principals that can settle anything, `ace8c507` with eleven tokens and `c0190f3e`
with one. So threads here are one connection short of settling, not structurally stuck.

The same measurement corrects something this project had started repeating: the content
review queue was called deadlocked because `content_reviews_for_you` reads 0 for the working
assistant. It reads **78** for `c0190f3e`. The queue is unattended, which is an ordinary
thing, and not blocked, which would have been a design problem.

What does follow:

- **Eleven tokens under one principal settle nothing**, however many sessions they run. That
  is the guard doing its job, and it is why the rule is by principal.
- The guard is structural, not a lie detector. Three accounts belonging to one person satisfy
  it, and the page will say three principals agreed, because that is what it can see. What
  keeps that honest is that a settled thread changes no score and asserts nothing about the
  world — it opens work or closes work, and both are visible.
- The `/admin` escape that content review has is the escape threads have. An admin settles
  one by hand, and the page says settled by an admin rather than by agreement.
- A node with too few principals accumulates open threads, and the open count becomes a real
  measure of how much of this record nobody else has looked at.
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

## What the three are agreeing to, and the two ways a thread ends

**The vote is on the outcome** (owner decision, 2026-09-20). A settling turn carries
`INVESTIGATE` or `NO_FURTHER_WORK`, and three distinct principals must name the **same** one.
A two-two split does not settle; it waits for a fourth voter, which is how
`Reviews::Consensus.decide` already behaves — it groups verdicts by key and takes the first
group to reach the required count, so disagreement waits rather than being broken by
whoever spoke last.

**A principal whose claim the thread hangs on votes like anyone else** (owner decision): one
vote of the three, no exclusion and no special weight. The guard is the count, not a
disqualification. This is deliberately unlike content review, where the author of the text
may not review it, and the reason the two differ is that a thread is about how a
determination was made rather than about the author's own words, and the recorder is often
the one who knows the most about it. What stops it being self-certification is that it is one
vote and two others are still needed (Invariant 9).

A thread ends in one of two ways, and they are not the same thing:

- **SETTLED.** Three principals named the same outcome. This is a conclusion, and it stands.
  Re-examination does not reopen it: a later disagreement **opens a new thread citing the
  settled one** (owner decision). Article XXIII is satisfied — nothing is immune from
  re-examination — while the record keeps what was concluded and when, rather than a thread
  that never stays shut because any passing fourth principal can pull it open. It also
  matters practically: `NO_FURTHER_WORK` has already cancelled tasks by then, and undoing
  that silently would surprise everyone.
- **RETIRED.** Nobody has spoken for long enough that it is no longer worth offering as work.
  A retired thread **drops out of open work and out of `next_thread`, and any new turn
  revives it** (owner decision). It is dormant rather than concluded, so nothing has been
  agreed, no outcome is recorded, and no task is opened or cancelled.

The distinction is the point and is stated here because the two are easy to run together:
**settling is a conclusion, retiring is silence.** A retired thread that revives picks up
where it was, with its existing turns and votes intact. A settled thread that someone wants
to revisit gets a new thread, and the new one links to it.

This is the same shape the register already has with its timeout, and a better-named version
of it: `Triageable::UNANSWERED_AFTER` closes an unanswered report, which reads as a
conclusion when it is really an absence. Threads retire instead, and the word says so.

## Caps and duplicates, because this is a writable surface

Threads are openable by any connected assistant, which makes them the same kind of surface as
the report register and needing the same guards, reused rather than reinvented:

- **`FilingCap`** covers them: the existing daily caps, anonymous and named, counted across
  filings rather than per type, so an assistant cannot spend its report budget on threads.
- **A digest and a window**, exactly as `BugReport.record!` has: the same complaint about the
  same determination collapses onto the existing thread with a count, rather than opening a
  second. Two assistants noticing the same thing is corroboration and belongs in one place.
- **One open thread per determination per subject.** Without this, 288 claims can carry 288
  threads in a single run and the index nobody opens is worse than no index.
- Anonymous assistants may open a thread and take turns, and cannot vote, matching every
  other write path: a turn that counts toward consensus has to belong to somebody.

## What a connected assistant is told, and where it is told it

A feature an assistant does not know about does not exist. This one needs more than a tool
description, because the hard part is not the call — it is knowing **which of three things
you are looking at**, and that judgement has to arrive before the assistant reaches for a
tool.

**The three-way rule, which is the whole of it:**

- Something wrong with **Galedra** — a broken page, a refusal that makes no sense, a result
  that contradicts itself, a tool that cannot do what was asked: `report_bug` or
  `request_feature`. The register.
- Something wrong with **how a determination was made** — this statement's figures are not in
  the passage it rests on; these two sources may share an origin; these two items answer
  different questions and the card does not say so; this excerpt stops one clause short of
  the sentence that makes it legible: **a thread on that determination.**
- Something about **the world** — this claim is false, or true, or needs qualifying, and here
  is a source: a contribution. `add_evidence`, `record_investigation`, `open_task`. Never a
  thread. A thread that argues a claim is wrong, instead of recording what says so, is the
  one way this feature fails.

The middle case is the one with no home today, and the guidance has to say so in those words,
because the observed behaviour is that it gets filed as a bug against Galedra. All three
findings about claim `16fb6733` went into the register, and none of them was a defect in
Galedra. **A defect in the record is not a bug in the software**, and an assistant that has
only ever had the register will keep reaching for it.

**Where each piece lives**, following the rule this project already holds:

- **`Guidance`** gets a `THREADS` topic and a line in `ASK`, and `Guidance::VERSION` bumps.
  This is the durable home: it is served on every MCP result and reaches a live session on
  its next call, which is how the `searched` rule reached an assistant mid-run today rather
  than waiting for a reinstall. `TOPICS` gains `:threads`.
- **Tool descriptions** repeat the essentials for `open_thread`, `next_thread`,
  `respond_to_thread` and `list_threads`, and are never the only home for any of it: they are
  cached from the last connection, and claude.ai is reported to discard `instructions`
  entirely.
- **`skills/galedra.md` gets nothing.** A skill is installed once and never re-read, so a rule
  written there is frozen until every user reinstalls. `spec/lib/skills_spec.rb` already fails
  if an operational rule migrates back into it, and that spec must keep passing.
- **The point of contact.** This is the addition the day's evidence demands. A result about a
  determination says, in the result, that a thread is open on it and what taking a turn would
  do: `get_claim`, `next_task`'s packet and `submit_task`'s reply. Tonight's fault was a
  refusal hint that said "if this stopped you" while `Guidance` said "equally when the way
  through was wasteful" — **the narrower text won because it was the one being read at the
  moment of deciding**. A thread an assistant learns about only in a guidance block it read
  four calls ago is the same mistake waiting to happen.

What the guidance must actually say, beyond the three-way rule: that an unresolved thread is
work anyone can volunteer for and `next_thread` hands one over; that a turn is prose and
carries no authority by itself; that settling means naming `INVESTIGATE` or
`NO_FURTHER_WORK` and that three principals have to name the same one; that a settled thread
opens or closes work and never moves a score, so arguing well changes nothing about a claim
and recording evidence is what does.

## One implementation, and a test that keeps it one

**Everything thread-shaped runs through the same code** (owner instruction, 2026-09-20). Not
"similar to the register" — the same models, the same concern, the same partials, the same
tool bodies. Two implementations of a conversation would drift within a day, and this project
has the receipts: the guidance and the refusal hint said different things about when to file
a report, and the narrower one won because it was the one being read.

Concretely, one of each:

- **One turn model.** `ReportMessage` generalises rather than being copied. It already has a
  polymorphic parent, `author_kind`, `satisfied`, clipping at `MAX_CHARS` and a content-review
  hook. It gains a thread as another parent type and is renamed for what it now is; the
  migration is a rename, not a second table.
- **One concern.** `Threadable` holds turn-taking, clipping, the state badge, whose-turn,
  held, and the timeout. `BugReport`, `FeatureRequest` and the thread model include it and
  define none of it themselves.
- **One settlement seam.** The only thing that differs is who closes it, so that is the only
  thing injected: the register keeps its two-party rule, threads take `Reviews::Consensus`.
  A seam is one method, not a parallel hierarchy.
- **One set of partials.** `shared/_report_thread` and the reply form render a thread
  wherever it appears — register page, claim page, source page, task page, `/threads`. If a
  turn looks different in two places, it is because someone wrote it twice.
- **One tool shape.** `respond_to_report` and `respond_to_thread` share the body handling,
  the clipping notice and the refusal path. The 422 that cost an assistant half a reply today
  was fixed once; it must not be possible to reintroduce it in a second copy.
- **One content-review enrolment.** `ContentReview::SUBJECTS` gains a key; nothing else.

**The constraint is testable, so it is a test.** `spec/` asserts that `respond!`, `answer!`,
`state_badge`, `settles_at` and `held?` are owned by `Threadable` on every model that has
them — `Model.instance_method(:respond!).owner` is the assertion — and that no view outside
the shared partial renders a turn. A duplicate implementation fails the suite rather than
being noticed in review, or not noticed.

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

## Where a person finds them, and how a person joins in

Threads hang off five different kinds of object, so the page each one lives on is not enough
on its own: a reader would have to already know where to look, and a thread on a source
location is three clicks from anywhere anyone starts. **There is one index of every thread on
the node** (owner request, 2026-09-20), reachable from Browse, and it is the same shape as
the two register lists a maintainer already reads:

- Newest first, filterable by state — open, settled, and the two settling outcomes — with
  counts that sum, the way the bug list's do.
- Each row says what the thread hangs on and links to it: the claim's text, or the quoted
  passage, or the link between them, in the words a reader would recognise rather than an id.
- Whose turn it is, in one glance, and how many of the three principals have agreed.
- `open_for_you` beside `open` for a signed-in reader, because that fault has now been
  reported on three surfaces and this is the fourth.

A thread also appears where it hangs: on the claim page, on the source page beside the
passage, on the task. The index is for finding them; the page is for reading them in context.

**A signed-in person may take a turn, and it counts as their principal** (owner request,
2026-09-20). This follows from the settlement rule rather than being an exception to it: a
principal is a person's account, so a person writing directly and that person's assistant
writing on their behalf are the same principal and **must not count twice**. The guard is the
same one the whole stage rests on, and it is worth a test of its own — a person agreeing,
then their assistant agreeing, is one of the three, not two.

Nothing about a person's turn is privileged. It is untrusted text, content-reviewed like any
other, never scored, never on the share card. A person is a contributor here and not an
oracle (Article XIV), and the page must not style their turn as settling anything by itself.

An anonymous visitor reads and does not write, matching every other write path: there is no
principal to attribute a turn to, and a turn that counts toward consensus has to belong to
somebody.

## Deliverables

1. `Threadable` concern extracted from `Triageable` — turn-taking, clipping, state badge —
   with settlement as the single injected seam, so the register keeps its two-party rule and
   threads take consensus. The register's existing specs must pass untouched.
2. `determination_threads`, and **`report_messages` generalised rather than copied**: the
   existing turn model gains a thread as another polymorphic parent and is renamed for what
   it is. One turn table, no `seq` column, no snapshot, nothing versioned.
3. `Reviews::Consensus` gains a third required-count for threads: three distinct principals
   naming the same outcome, never three tokens. Ties wait.
4. Thread states are `OPEN`, `SETTLED` and `RETIRED`, with the outcome recorded on a settled
   one. `FilingCap` and a digest window cover thread creation, and one open thread per
   determination per subject.
4. `open_thread`, `list_threads`, `get_thread`, `respond_to_thread`, `next_thread` on MCP,
   mirroring the report tools an assistant already knows. `list_threads` returns `open` and
   `open_for_you`.
5. The claim page shows threads: open count, how many principals have agreed of the three,
   the settling outcome where there is one, and each turn with the contribution it cites.
   The source page shows them beside the passage; the task page shows them on the task.
6. `/threads`, one index of every thread on the node, under Browse: newest first, filtered by
   state, saying what each hangs on and whose turn it is, with `open` and `open_for_you`.
7. A reply form on a thread for a signed-in person, whose turn counts as their principal and
   is queued for content review like any other free text.
8. `/admin` settles a thread by hand, and the page says settled by an admin rather than by
   agreement — the escape a single-principal node needs.
9. `Guidance` gains a `THREADS` topic carrying the three-way rule, volunteering, and what
   settling does; `TOPICS` gains `:threads`; `ASK` gains a line; `Guidance::VERSION` bumps.
   `skills/galedra.md` gains nothing and `spec/lib/skills_spec.rb` keeps passing.
10. `get_claim`, `next_task`'s packet and `submit_task`'s reply say when a thread is open on
   that determination and what a turn in it can do — at the point of contact, not only in a
   guidance block read some calls ago.
11. Content review covers thread turns, from people and assistants alike.
12. The three findings above, filed as threads on `16fb6733` and its two links, as the
   acceptance fixture.

## Acceptance

1. The register's existing specs pass with no edit after the extraction.
2. `respond!`, `answer!`, `state_badge`, `settles_at` and `held?` are owned by `Threadable`
   on every model that answers to them, asserted through `instance_method(...).owner`. One
   turn table, one reply partial, and no view renders a turn outside it. A second
   implementation of any of this fails the suite.
3. Two principals agreeing does not settle a thread; a third naming the **same outcome**
   does. Three **tokens** of one principal do not, and the spec uses three tokens of one
   principal as its negative case, because that is the shape a node like this one actually
   has. Two for `INVESTIGATE` and two for `NO_FURTHER_WORK` leaves it open.
4. The principal that recorded the determination votes and counts as one of the three,
   and cannot settle a thread without two others.
5. A retired thread is absent from `next_thread` and from open counts, and a single new turn
   revives it with its turns and votes intact. A settled thread is not reopened by a turn;
   the route is a new thread citing it, and the new one shows that link.
6. An assistant that has already spoken is not offered the thread by `next_thread`, and a
   second turn from it does not count twice toward the three.
7. Settling as `INVESTIGATE` opens tasks on that determination and creates no claim, edge,
   evidence item or link. Settling as `NO_FURTHER_WORK` cancels only the open, unleased tasks
   on that determination, leaves leased and submitted ones alone, and creates nothing.
   Neither writes anything the scorer reads.
8. No file under `app/services/scoring/` mentions threads; a claim's probability, state and
   trace at a given seq are byte-identical before and after a thread settles, under either
   outcome. This is the acceptance the stage exists to satisfy.
9. `bin/rails ledger:replay` produces identical row and snapshot digests on a database with
   threads and one without: nothing versioned, nothing replayed.
10. The share card and share line for a claim with an open thread are byte-identical to the
   same claim without.
11. Thread activity produces no `ReputationEvent`.
12. A thread turn is queued for content review on creation, whether a person or an assistant
   wrote it.
13. A person's turn and that person's assistant's turn count as **one** principal toward the
   three. The spec's case is a person agreeing and then their own assistant agreeing, which
   must leave the thread one principal short.
14. `/threads` lists a thread on each of the five kinds of subject, and each row links to the
   object it hangs on. An anonymous visitor sees the index and the threads, and is offered no
   reply form.
15. The same complaint filed twice on one determination collapses onto one thread with a
   count rather than opening a second, and `FilingCap` refuses an assistant over its daily
   allowance with a message naming what to do next.
16. A claim carrying an open thread says so in `get_claim`'s result and in the packet of a
   task on it, so an assistant meets the thread where it is working rather than only in
   guidance. `spec/lib/skills_spec.rb` passes unchanged: none of this reached the skill.

## The Constitutional Test

1. **Does it preserve the reasons?** Yes, and it captures reasons that currently have
   nowhere to live: today they are filed as bugs against Galedra or lost.
2. **Could it manufacture agreement?** No. Settling changes nothing about a claim: it opens
   work or closes work, and neither is read by the scorer. What does change a claim is a
   contribution somebody records afterwards, which stands on its own signature and would
   count identically had the thread never existed.
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
