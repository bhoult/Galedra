# Stage 44 — From working to used

**Status:** planned 2026-09-23 · not started · most items need an owner decision first (marked
**Owner**)

**Tag:** `stage-44-from-working-to-used` · **Spec:** 01 (scope), 06 (API and display), 09 §2
(ClaimReview with conditions) · **Articles:** I (claims are not truth), VII (model-conditional),
XII (resist capture), XVIII (neutrality, selection), XIX (transparency), XXI (cumulative),
XXII (reveal weaknesses) · **Depends on:** Stage 43 M3, M4 and G4 before any item here that
brings in readers

## Where this comes from

On 2026-09-23 the owner asked whether Galedra meets a real need, what would stop people adopting
it, and what to change. The assessment, in short:

- **The need is real and narrow.** Nothing else combines four things:
  - claims broken down so each can be checked on its own, with the quoted evidence behind
    each;
  - rules that stop repeated reports of one story counting as independent confirmation;
  - a signed log that can be replayed;
  - AI assistants doing the reading while people audit it.

  Fact-checkers publish verdicts, not reusable evidence. Community Notes records agreement,
  not reasons. Wikipedia forbids original research. Scite covers only academic citations.
  AI answers are thrown away after each chat.
- **What stands in the way is not the engineering.** The node had 386 claims, 3 accounts, 2
  people with a connected assistant, and 14 audits, all from one key. A search usually finds
  nothing. The labels promise more checking than has happened (Stage 43 M3 and M4). Nobody
  has measured whether the scores are right. There was no terms page, privacy policy or
  takedown contact until today.

This stage turns those recommendations into work items. Each has a recommendation, its pros
and cons, and what it waits on.

**The principle:** *stop adding capability; make what exists trustworthy, measured, findable,
and cheap to try.* A deep, well-audited corpus on one subject, used daily by one serious
group, is worth more than any feature not yet built.

---

## A. Before anyone is invited

### A1. The labels match what was checked

**Recommendation:** ship Stage 43 M4 (the "one contributor's reading, not yet checked by anyone
else" caveat) and G4 (headlines that say what they add up) **before any publicity**. Ship
M3(b) (a decisive state needs corroboration) with model 0.4.0, and make 0.4.0 the default
before a public launch.

- **Pros:** removes the single most likely reason for a damaging first review: "AI grades its
  own homework and calls it SUPPORTED".
- **Cons:** most decisive states on the node drop a notch, and the node looks less
  impressive. It is also more accurate.
- **Waits on:** Stage 43.

### A2. The legal basics, beyond the pages

`/terms`, `/privacy` and `/takedown` were added on 2026-09-23 and are linked from every page and
from `/api/v1/meta`. The same change stopped sign-up publishing the part of an email address
before the "@" as the permanent public name (`Users::PublicName`). What remains:

1. **Legal review.** The pages were written to describe what the node actually does. They
   have not been reviewed by a lawyer. **Owner**, and before a public launch.
2. **Governing law and a venue.** These are deliberately absent until the owner decides where
   the node is operated from. **Owner.**
3. **A DMCA designated agent,** if the node is operated from the US. Registering one with the
   US Copyright Office is what makes the notice-and-takedown safe harbour available. The
   takedown page already asks for the elements a notice needs. **Owner.**
4. **Log retention.** The privacy page promises the request log is kept "as short a time as
   that needs". Set an actual rotation in Compose and `docs/HOSTING.md` (for example 14 days),
   then put the number on the page.
5. **Closing an account.** The privacy page promises closure by email, which deletes email,
   password hash, sessions, tokens, affiliations and private views. Build it as a rake task,
   `users:close[email]`, with a spec asserting what goes and that nothing in the log is
   touched, so the promise is carried out the same way every time.
6. **Names already published.** The keys registered before 2026-09-23 carry the email prefix
   in a signed `REGISTER_KEY`. On the development node, that is one of its three accounts
   (checked 2026-09-23). A `REGISTER_KEY` is a control contribution, and `TAKEDOWN` redacts
   only epistemic ones. Decide whether to let a person ask for their name to be redacted
   (extending `Redaction` to that one field), or to accept it for a node that was never
   public. **Owner.**
7. **A legal entity or fiscal host,** so the operator is not personally the publisher of
   record. For example, a fiscal sponsor through Open Collective or a nonprofit umbrella.
   **Owner.**

- **Pros:** closes the exposure that could end the project on the first complaint.
- **Cons:** each is slow and some cost money. None of it is visible progress.

### A3. Measure whether the scores are right

Reproducible is not the same as accurate. The node has never been compared with an outside
standard.

**Recommendation:** an **accuracy benchmark**, run outside the node as Invariant 18 requires:

- **Scope.** Take 200 to 500 claims with established answers from a public fact-checking
  dataset. Candidates are AVeriTeC, the FEVER family, or a sample of ClaimReview verdicts
  from recognised fact-checkers, whichever licence permits reuse.
- **Procedure.**
  - Have a connected assistant investigate each claim through the ordinary MCP tools, on a
    scratch node, without seeing the answer.
  - Record the assistant's model and version with every run.
  - Compare the assessment states with the expert verdicts, as a confusion matrix, and
    check whether the probabilities match how often claims turn out true (calibration).
  - Measure how often the result is INSUFFICIENT_EVIDENCE.
- **Publication.** Write it up as `docs/experiments/YYYY-MM-DD-accuracy-benchmark.md`, and put
  a plain summary on `/about` ("How often does it agree with professional fact-checkers?").
- **Re-runs.** Run it again for every new default model and every new assistant model worth
  naming.

- **Pros:** the most persuasive thing the project could show anyone. It turns "determinism is
  not objectivity" (Invariant 17) from a disclaimer into a measured statement. It will also
  find scoring defects the audit could not, because it has an outside answer to compare
  against.
- **Cons:**
  - **Token cost.** Several hundred investigations. The owner's local model could drive the
    MCP loop cheaply, but it would measure a 20B model, not the assistants people actually
    use. Run one of each and say which is which.
  - **Dataset licences** vary. Check each before use.
  - **It measures the assistant and the ledger together,** not the ledger alone. That is what
    a user gets, so it is the right thing to measure, but the write-up must not claim more.
  - **Expert verdicts are not ground truth either.** Say so, and report disagreement rather
    than calling it error.
- **Owner:** which dataset, and a token budget.

---

## B. One audience, one subject

### B1. Choose the first audience

**Recommendation: fact-checkers and newsroom researchers, as a shared evidence workspace.**
They already do the work, they have audit labour and credibility, and they redo each other's
evidence-gathering constantly. The INSTITUTIONAL identity tier exists for them. What they
would need:

- **Organisation standing:** the attestation from Stage 43 M1, granted to an organisation's
  keys, so its members' audits count.
- **A drafting space outside the log.** Journalists will not work in public before
  publication. That means private notes and a private investigation draft, kept outside the
  log like personal views, and published into the log as one signed investigation when
  ready. Invariant 13 already separates shared from personal, and this is the same
  separation.
- **A citation that works in an article:** an embeddable card (C2), and a stable link to a
  claim at a named snapshot.

| Alternative | Pros | Cons |
|---|---|---|
| Students and researchers checking a literature | Real demand (Scite shows it); patient; teachable | Little audit credibility; academic claims need a model the ledger does not have for statistics |
| "Check before I share" consumers | Lowest friction; already built (`galedra:`) | Brings almost no audit labour; best as a growth channel once a base exists |
| Wikipedia editors | Care about sources deeply | The community is wary of outside tools and of AI |

- **Pros of the recommendation:** one organisation using it daily gives a corpus,
  audits, feedback and credibility at once.
- **Cons:** newsrooms are slow to adopt, cautious about AI, and politically exposed. One
  outlet's adoption will be read as the node taking that outlet's side. Two outlets from
  different directions would answer that, and are harder to find.
- **Owner:** the audience, and the first few people to approach.

### B2. Seed one subject deeply

**Recommendation:** pick one bounded subject and investigate its central claims thoroughly,
with real audits, before inviting anyone. Record the reason for the choice publicly, because
choosing a subject is selection (Article XVIII). The subject should matter, be contested,
and have good public sources. Examples: a recent public-health question, a well-documented
historical controversy, or a set of claims from one high-profile public report.

- **Pros:** a newcomer's first search finds something rich, and the demonstration shows the
  whole pipeline: evidence, independence, audits, uncertainty.
- **Cons:** whichever subject is chosen will be read as a statement. Choosing a politically
  charged one first invites the bias accusation before there is a record to answer it with.
  A less charged but still contested subject is safer for a first corpus.
- **Owner:** the subject.

---

## C. Being found where claims are met

Nobody visits a fact-checking site on the off chance. Checks have to appear where the claim is
read.

### C1. A browser extension

**Recommendation:** a small extension that, **only when the person clicks it**, sends the
selected text to `search_claims` and shows any matching claims with their answer cards. It
never sends a whole page unasked, never reads in the background, and runs no model (it is
text search against the node). "Record this" hands the text to the person's own connected
assistant.

- **Pros:** meets people where the claim is. Cheap to build on the existing search API.
- **Cons:** extension stores take maintenance and review time. Search by similarity misses
  paraphrases, so misses will be common until the corpus is large. It needs its own short
  privacy note: only what the person selects, only when they click.

### C2. Embeddable cards and oEmbed

**Recommendation:** an oEmbed endpoint and an embeddable card for a claim at a snapshot, built
on the existing share cards (`Cards::Image`, `share_card`). A publisher can then cite
"0.86 under ledger-default@0.3.0 at snapshot 212" and link to the reasons.

- **Pros:** makes Galedra something an article can cite, which is exactly what B1's audience
  needs.
- **Cons:** an embed fixed at one snapshot goes stale as evidence arrives. It must say which
  snapshot it shows, and link to the current state.

### C3. ClaimReview output, with conditions

**Recommendation:** publish `ClaimReview` structured data on claim pages, following the
conditions spec 09 §2 already sets:
- the rating is the assessment state and model, never a truth verdict;
- nothing is published for INSUFFICIENT_EVIDENCE, UNRESOLVED or NOT_APPLICABLE;
- only audited claims qualify, meaning review coverage above a threshold.

- **Pros:** search engines and fact-check aggregators can surface the checks.
- **Cons:** ClaimReview expects a truth rating, and anything it shows will be read as a
  verdict whatever the markup says. The spec already allows it only as opt-in per record.
  It also depends on A1, or it would advertise unaudited states.
- **Owner:** whether to do this at all.

---

## D. Making auditing worth doing

### D1. Auditor profiles

**Recommendation:** each auditor's page shows their audit record per domain:
- how many audits;
- how their audits fared when re-audited;
- the domains where they have standing, and how they earned it (attestation, or Stage 43's
  earned route).

Link it from every audit they sign.

- **Pros:** gives auditors something to point to. It is also what Article X describes:
  reliability per task and domain, from audited outcomes.
- **Cons:** visible records invite gaming and status-seeking. Show the record, not a rank,
  and never a leaderboard of "most trusted".

### D2. An audit queue someone would work

**Recommendation:** for people with standing, `next_task` offers audits first. For people
earning standing, it offers advisory audits. The task board counts audits waiting per domain,
so an organisation can see where its members are needed.

- **Pros:** makes the thin layer of human judgment the thing the queue feeds, rather than
  more investigation.
- **Cons:** without people to do them, a larger audit queue is just a longer list.

---

## E. Continuity and trust in the operator

### E1. More than one keyholder

**Recommendation:**
- The system key has a documented second custodian, or is split, for example under a
  threshold scheme.
- A succession document says who can run the node, and how, if the owner cannot.
- At least one other person is a moderator.

- **Pros:** a project whose premise is resisting capture cannot rest on one person. The
  first critic to notice will say so.
- **Cons:** finding people to trust with this is the hard part. The rest is paperwork.
- **Owner:** entirely. This is already a reserved decision, and naming a second keyholder
  would settle part of it.

---

## F. The cost of trying

### F1. Say what an investigation costs

**Recommendation:** after each recording, `record_investigation` reports how many signed writes
it took. The connect page gives a rough guide to how much of an assistant's usage a typical
investigation consumes (for example "a news article: a few minutes; a two-hour transcript:
most of an afternoon's allowance"), measured, not guessed.

- **Pros:** people stop being surprised by the cost, and the project stops being blamed for
  it.
- **Cons:** the costs belong to other companies and change without notice. State them as
  measured on a date.

### F2. A path that needs no assistant

**Recommendation:** make the paste-and-analyse path (`/investigations/new`, `/analyze`) a
first-class entrance for someone with no connected assistant. Make the manual evidence form
on a claim page equally prominent.

- **Pros:** removes the steepest step: "first, connect an AI assistant over MCP".
- **Cons:** manual contributions are slower and rarer, and the web forms get less attention
  than the tools do.

### F3. Less jargon on first contact

**Recommendation:**
- The answer card, the landing page and the share line use plain words first, with the
  canonical term beside them: "evidence mostly supports this (SUPPORTED)".
- A first visit gets a two-sentence explanation of what the page is.
- The glossary is linked from every canonical term.

- **Pros:** the canonical vocabulary stays exact where it matters, and stops being the first
  thing a stranger meets.
- **Cons:** plain words are less exact. `CLAUDE.md` forbids synonyms for canonical terms, so
  the plain phrase must be a fixed gloss beside the term, one per state, defined in one
  place. It must never replace the term.

---

## G. Knowing whether it is working

### G1. Adoption measures

**Recommendation:** extend `metrics:report` with a weekly adoption section, all from data
already held and none of it about individuals:
- distinct contributing principals, and how many return;
- claims with at least one non-kin audit;
- the median review coverage of claims read;
- the proportion of `search_claims` calls that return nothing.

Record the zero-result rate without the query text by default. If the owner chooses, keep
query text for zero-result searches only, as the privacy page would then have to say. Those
misses are the best guide to what to investigate next.

- **Pros:** says whether this stage is working, in numbers, with no tracking.
- **Cons:** keeping query text would be a new kind of data. Default is off.
- **Owner:** whether to keep the text of zero-result queries.

### G2. A feature freeze

**Recommendation:** until B1's audience is using the node weekly, build only:
- what Stage 43 requires;
- what this stage lists;
- what that audience asks for.

Every other feature request is recorded and held.

- **Pros:** focus. Forty-three stages built a great deal for three users.
- **Cons:** some good ideas wait. They are recorded, not lost.

---

## Order of work

1. **Before anyone is invited:** A1 (Stage 43 M4 and G4, then 0.4.0); A2 items 4 and 5
   (log rotation and the account-closure task); F1; F3; G1 without query text.
2. **Owner decisions, all needed early:**
   - A2 items 1–3, 6 and 7: legal review, governing law, the DMCA agent, published names,
     and an entity;
   - A3: the dataset and the budget;
   - B1: the audience;
   - B2: the subject;
   - C3: whether to publish ClaimReview;
   - E1: a second keyholder;
   - G1: whether to keep zero-result query text.
3. **Then:** A3, run and published. B2, the seeded subject. C2 and C1. D1 and D2. F2.
4. **Throughout:** G2.

## Constitutional Test

1. *Does it make evidence more traceable or less?* **More.** A3 publishes how the scores
   compare with outside verdicts. C2 cites a claim at a named snapshot. D1 makes an auditor's
   record visible.
2. *Does it make disagreement more inspectable or less?* **More.** A3 reports where the node
   and professional fact-checkers disagree, instead of hiding it. B2 records why a subject
   was chosen.
3. *Does it increase hidden authority?* **No.**
   - The largest new authority is organisation standing (B1). It is Stage 43's attestation,
     visible and challengeable.
   - E1 reduces authority now held by one person.
   - C3 could lend the node an authority it does not claim, which is why it is conditional,
     opt-in, and restricted to audited claims.
4. *Does it allow reputation to substitute for evidence?* **No.** D1 displays a record. It
   feeds no score.
5. *Does it preserve uncertainty?* **Yes.**
   - A1 makes the labels less certain where the evidence is thin.
   - A3 reports how often the answer is INSUFFICIENT_EVIDENCE.
   - C3 publishes nothing for an unresolved claim.
   - F3's plain glosses must keep the uncertainty the canonical term carries. The fixed-gloss
     rule exists for that.
6. *Can the result be reproduced?* **Yes.** A3 is a written procedure with the model named, run
   on a scratch node whose log can be replayed. Embeds name their snapshot.
7. *Can an opposing investigator challenge it using the same system?* **Yes.** A3's method and
   data are published for anyone to rerun. B2's seeded subject is open to contrary evidence
   like any other.
8. *Can the history of the conclusion be reconstructed?* **Yes.** Nothing here edits the log.
   The drafting space (B1) is outside it by design, and what is published from it enters as
   an ordinary signed investigation.
9. *Does it preserve the distinction between shared evidence and personal belief?* **Yes.** B1's
   private drafts are kept outside the log with personal views, and they reach the shared
   layer only as signed contributions (Article XV as revised).
10. *Would we still want this mechanism if it were used by people whose conclusions we
    strongly disagree with?* **Yes, with one watch-point.** An outlet we disagree with could
    adopt the node first and seed the corpus with its own subject choices. The answers are
    in B1 (seek outlets from different directions), in XVIII's selection visibility (G5 of
    Stage 43), and in the fact that anyone can add evidence against anything they seed. The
    record would show the lean, and the constitution requires that it can.

No "no" to 1, 2, 5, 6, 7, 8, 9 or 10, and no "yes" to 3 or 4.

## Acceptance

- **A1:** Stage 43 M4 and G4 shipped, and 0.4.0 released and made the default through
  `SET_DEFAULT_MODEL` before any launch announcement.
- **A2:**
  - `users:close[email]` deletes exactly what the privacy page lists, and leaves the log
    byte-identical (`ledger:verify` and a spec).
  - Log rotation is configured, and the privacy page states its length.
  - Items 1–3, 6 and 7 are recorded as decided, with the date, in this file.
- **A3:** the write-up exists, with the dataset, its licence, the models, the confusion
  matrix, the calibration, the rate of INSUFFICIENT_EVIDENCE, and the cost. `/about` links it.
- **B2:** the subject and the reason for choosing it are published. Its central claims each
  have at least one non-kin audit.
- **C1 and C2:**
  - The extension sends only selected text, only on a click, and says so on its own
    privacy note.
  - Every embed names its snapshot and links to the current state.
- **G1:** `metrics:report` prints the weekly adoption section with no per-person data.
