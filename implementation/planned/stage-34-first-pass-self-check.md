# Stage 34 — A person can finish their own investigation

**Status:** planned · tag will be `stage-34-first-pass-self-check`

**Tag:** `stage-34-first-pass-self-check` · **Spec:** 03 §5 (review checklist and coverage),
04 §2 (task types), 04 §3.1 (blind independent verification, and what no-self-certification
actually forbids), 05 §9 (audits), 06 §4 (display rules), Articles XI (identity does not
replace evidence), XIV (contributors, not oracles), XIX (transparency over persuasion),
XXII (reveal our own weaknesses), XXIII (re-examination), Invariants 7 (AI is never evidence
by itself), 8 (reputation is not a scoring input), 9 (no self-certification),
16 (answers first), 17 (determinism is not objectivity)

Goal (owner, 2026-09-19): *"a user can, if they want to spend the tokens, upload a document
and get a full investigation. It is not practical for them to wait until a volunteer comes
along to finish it for them. They should be able to both investigate the claim and add
their own accuracy score. The system will record that they validated their own claims so
this is ok. It can be reported that this is the case when someone views it. Over time
others will add additional validations."*

## The problem, precisely

A person outlined a two-hour source and recorded 247 claims with evidence: 1,679 signed
writes, hours of work, real money. Every one of the 742 verification tasks that opened
behind those claims is closed to them, so the outline reads **182 unresolved** and stays
that way until a stranger arrives. Asked to check its own work, the assistant correctly
refused and told the owner the unlock was "a second Galedra account, or someone else."

That is a dead end for the only user the node currently has, and it is a bad trade: it
protects a number nobody is reading yet at the cost of the product being finishable.

## What the rule actually says

`04 §3.1` is narrow and exact:

> **No self-certification:** a contribution cannot be **audited**, and a **proposed claim
> cannot be accepted**, by the same contributor or any contributor under the same principal.

Two things: **audits**, and **accepting a proposed claim**. It says nothing about
verification tasks. Article XI says cryptographic identity proves who submitted something
and not that it is correct — it forbids identity standing in for evidence, not a person
recording what they found.

`Tasks::Lease` is broader than either. Its self-authorship guard applies to **every task
type**, so `EVIDENCE_VERIFICATION`, `OPPOSING_EVIDENCE_SEARCH` and `QUALIFIER_CHECK` — none
of which are audits — are blocked along with audits. **The implementation is stricter than
the spec it implements**, and nothing in the spec asked for the extra strictness.

So this stage needs no constitutional amendment. It makes the code match `04 §3.1`.

## The design

**Do not add an accuracy rating.** The owner asked for "their own accuracy score", and the
instinct is right, but a new free-standing rating would be the assistant's own judgement
with a number attached — `MODEL_OUTPUT`, which Invariant 7 weighs at zero, and exactly the
thing Article XI forbids standing in for evidence. The verification task outcomes *are*
the rating, in a closed enum, server-validated, with the reading behind them. Unlocking
them gives what was asked for and invents nothing.

1. **The author may lease and answer their own verification tasks.** Extraction, evidence
   verification, opposing-evidence search, qualifier check.
2. **Audits stay closed**, and accepting a proposed claim stays closed, to the same
   contributor and the same principal. That is the rule, kept exactly.
3. **Every assignment records whether it was self-performed** — an explicit column, not
   something derived later by comparing principals, because the comparison changes as keys
   are adopted and merged, and a fact about what happened must not be recomputed.
4. **A self-check never raises `review_coverage`.** `Checklist.evaluate` counts independent
   checks toward coverage, and self-checks toward a separate `self_checked` figure. This is
   the whole safety of the stage: the work is recorded and visible, and the number that
   means *someone other than the author has looked* stays true.
5. **The claim says so in words**, not only in a figure: *"Checked by the author. No
   independent review yet."* Once someone else answers, it changes to what it is. Article
   XIX: the page tells the reader the weakness rather than hiding it in a decimal.

   **The share line names all three numbers** (owner, 2026-09-19):

   > 247 claims · 247 self-checked · 0 independently checked

   Not the shorter "none independently checked". The long form is what someone pasting the
   link is actually publishing about their own work, and it states the weakness in the same
   breath as the volume rather than leaving a reader to notice an absence. It also keeps
   reading correctly as the second number falls behind the third, which the short form does
   not: "12 independently checked" has no natural place in a sentence built around *none*.
6. **A self-check is superseded, not replaced, by an independent one.** Both stay visible;
   disagreement between them is information and shows as contested.

## What this deliberately does not do

- It does not let a self-check change `probability`. Evidence moves the score; checks move
  coverage. A person who checks their own claim and finds it sound has not added evidence,
  and the number must not move as though they had.
- It does not touch reputation (Invariant 8, not a scoring input in v0.1).
- It does not weaken audits, which are the actual integrity mechanism and where `04 §3.1`
  bites for a reason.

## Acceptance

1. The principal who recorded a claim can lease and submit its evidence verification,
   opposing-evidence search and qualifier check.
2. The same principal still cannot audit its own contribution, and cannot accept its own
   proposed claim. Both refuse with the existing codes.
3. A claim checked only by its author reports `review_coverage` unchanged from before the
   check, and a non-zero self-checked count.
4. That claim's page and card both say the author checked it and no one else has.
5. An independent answer afterwards raises coverage, and both answers remain visible.
6. A self-check and an independent check that disagree render as contested.
7. The seeded 47-leaf outline can be taken to a state with no open self-checkable work by
   one principal, which is the product claim this stage exists to make true.

## Open questions for the owner

- Whether a self-check should count toward `stability` at all, or only ever toward its own
  figure.
- Whether an anonymous principal should get the same latitude as a named one. The argument
  for no is that self-checking is only meaningful when the self is accountable.
