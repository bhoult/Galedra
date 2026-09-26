# Review Notes — Changes Across Revisions

v2 (sections A–F) revised the original spec. v3 (section G) reconciles v2 with `12-constitution.md`. v4 (section H) applies the external v4 review notes, with the deviations explained in H.3.

Not required for implementation. Records what was wrong or risky in the previous spec and what this revision does about it, ordered by impact.

## A. Blocking design problems

1. **Snapshots could not be reproduced.** Projection tables had mutable `status` / `invalidated_by_contribution_id` columns and snapshots were keyed by `max_contribution_timestamp`, so there was no way to know what was active at an earlier point. → Log-first event sourcing with a gap-free `seq`, validity windows (`created_seq` / `invalidated_seq` / `accepted_seq`), snapshots as `(seq, entry_hash)`, and a mandatory replay test (02 §1, 07 Phase 2/F).

2. **The hash chain was unimplementable.** `parent_hash = hash(previous contribution)` was inside the client signature, but asynchronous agents cannot know the previous entry. → The server builds the chain around the client envelope under an advisory lock and signs each entry (02 §1.2).

3. **UI users had no way to sign**, yet every mutation had to be signed. → Labeled server custody for browser users; self-custody for API users and agents (05 §2).

4. **Roadmap order contradicted the handoff.** 07 built CRUD tables before signed contributions; 10 said the opposite. Snapshots and summaries were in the DoD but in no phase. → Log first; every DoD item mapped to a phase with acceptance tests (07).

5. **Evidence-free claims showed their prior.** An unsupported claim (including the seed's poisoned claim after invalidation) would display 0.50. → `INSUFFICIENT_EVIDENCE` with no number; assessment states lead the UI (03 §4–5, 06 §4).

## B. Scoring defects

6. **Reputation inside scores broke determinism and fairness.** Scores depended on unrelated audit history; the Beta(2,2) prior silently halved every new contributor's evidence (contradicting "new contributors are not assumed malicious"); agent self-reported `extraction_confidence` was trusted. → Reputation removed from v0.1 scoring; `provisional` flag communicates unaudited work (03 §4 Step 1).

7. **Coverage was unmeasurable.** "Reviewed surface / estimated surface" had no data source. → A four-item checklist derived purely from the log (03 §8).

8. **Underspecified algorithm.** Factors (authenticity, extraction, replication, method quality, source proximity) had no schema fields; `CALCULATION`/`OTHER` had no weights; claim-edge propagation was implied but undefined (and cyclic); strongest-only didn't say whether grouping was per direction; ungrouped evidence was silently independent; floating-point "byte-identical" output was asserted without rounding rules. → Exhaustive config, explicit per-(group, direction) rule, `independence_unreviewed`, no propagation in v0.1, BigDecimal and string serialization (03, `scoring-config-v0.1.json`).

9. **Stability rewarded weak evidence.** A single weak item near 0.5 has a tiny variant spread and would read as HIGH. → Group-count cap and model-dependent cap (03 §9).

10. **Naming drift.** `belief_probability`, `probability`, `truth_probability`, `truth_score`, `support_strength` vs `support_score`, `not_applicable` vs `null`. → One canonical field set (README conventions, 03 §2).

## C. Security and protocol gaps

11. **No lease semantics or blind verification**, so "independent" verifications could see each other or be filled by one principal's agents. → Leases, per-principal slot uniqueness, blind reveal (04 §3.1, §7).

12. **A single audit could invalidate anyone's work** with no recourse, and auditors were never audited. → Auditor eligibility, `RE_AUDIT`, appeals, auditor reputation (05 §7–9).

13. **Audit sampling was operator-discretionary.** → Hash-based deterministic sampling anyone can recompute (05 §9).

14. **Reputation laundering via new agent keys.** → Principal roll-up and compromise windows (05 §4).

15. **Prompt injection was handled only by "tell agents to ignore instructions,"** which the server cannot enforce. → Closed-enum ops; notes excluded from packets, scoring, and summary inputs; test with an injection string (04 §5, §9).

16. **SSRF**: "claimed source location accessible" implied fetching agent-supplied URLs. → No server fetch of agent URLs in P0 (04 §6).

17. **`UNSIGNED` identity tier** contradicted the all-signed invariant. → Removed.

18. **Defamation/privacy risk** of scoring claims about private people was unaddressed. → Out of scope for POC; quarantine (01 §7, 05 §13).

19. **Two write paths** (resource POSTs and `/contributions`). → One write endpoint (06 §1).

## D. Scope

20. **The POC was too broad** (12 task types, ~20 tables, forecasts, causal metadata, marketplace, cost accounting). → P0/P1/Deferred tiers; four P0 task types; deferred items listed with reasons (01 §5, 09 §1).

21. **pgvector in Phase 0** added a dependency nothing in P0 needs. → pg_trgm in P0; pgvector P1.

## E. Seeded example

22. `C4` had two types ("HISTORICAL / INTERPRETIVE") while the schema allows one, and bundled a textual claim with a historical inference. → `C4` is textual; the inference is `H3`.
23. No expected numbers existed, so "byte-identical" had nothing to test against. → Golden table with derivations (08 §7), verified by `reference/reference_scorer.py`.
24. The demo's "score changes after new contribution" had no data. → Checkpoints S4→S5 show double counting and its correction.
25. The atomicity example used `1 Enoch` claims typed `HISTORICAL`; claims about what a text says behave differently. → New `TEXTUAL` type.
26. `AgentBad` created a claim directly although extraction should be reviewed. → Curator creates `C5`; `AgentBad` falsely verifies it — a more realistic poisoning path that passes validation.

## F. Document hygiene

27. README reading order omitted 10 and 11; `FULL-SPEC.md` placed 11 before 10 and duplicated every file (an agent told to "read all Markdown files" would read everything twice and risk drift). → Complete reading order; `FULL-SPEC.md` generated by `build-full-spec.sh`; read one or the other.
28. The Rails/Go/Rust extraction discussion was repeated in six places. → Consolidated in 11.
29. `starter-config.json` was unreferenced and listed a different principle set from the README. → Replaced by the authoritative `scoring-config-v0.1.json`.
30. Example IDs mixed `C104`, `SNAP-42`, `SNAP42`, `S2026-09-16-001` while the schema required UUIDs. → UUIDv7 in the DB; handles are display-only.

## G. v3 — Constitutional reconciliation

31. **Precedence was undefined.** Nothing said what wins when the spec and the constitution disagree. → Constitution header states precedence; 10 tells the agent to stop and record conflicts; `13-constitutional-compliance.md` maps every Article to spec sections with P0/P1/Partial/Gap status.
32. **Article XII required alternative scoring models; v2 shipped one.** → `ledger-strict@0.1.0` (config-only) and `/compare` in P0, with golden rows; C3 is where the two models disagree.
33. **Article VI named states v2 couldn't express** (untestable, dependent on disputed assumptions, underdetermined, indistinguishable). → `not_evaluable_reason` on claims, `not_applicable_reason` on results, `model_dependent` flag; question-level states planned for P1. Mapping table in 13.
34. **Article XV (personal belief) had no representation.** → Reserved `personal_assessments` table outside the log (P1), plus display rule that personal views never occupy the assessment position.
35. **Quarantine in v2 hid content from public reads, and takedowns replaced payloads** — both collide with Article XII's "no silent rewriting." → Public stubs, a closed list of reason categories, a public moderation log, appeals, and a `TAKEDOWN` action. Proposed amendment P-2 closes the gap in Article XIII's text.
36. **Article V lists "predicts"; v2 had dropped `PREDICTS`/`EXPLAINS`.** → Restored as stored edge types.
37. **Article XXII (reveal weaknesses) had no concrete surface.** → Weaknesses page and API in P0; suspicious-cluster report in P1.
38. **Article XXIV's "correspondingly strong evidence" isn't met by flat priors.** → Recorded honestly as a gap (03 §12) with options in proposed amendment P-4, instead of hand-tuning priors.
39. **Article XIX (transparency over persuasion)** → Display rules: model selector, default labeled as default, no true/false color-coding or "debunked" badges.
40. **Article XXV had no enforcement hook.** → Amendment log, `AMEND_CONSTITUTION` action, `constitution_hash` in `/meta`, and a recorded Constitutional Test for sensitive changes.

### Critique of the constitution itself (addressed by proposals, not silent edits)

- It protects contributors' privacy but not the people claims are *about* → P-1.
- Article XIII doesn't cover legally compelled removal → P-2.
- "Untestable" (Art. VI) could be used to shield a claim from evidence → P-3.
- Article XXIV's evidentiary standard has no operational definition, and any definition hands someone power over outcomes → P-4 as a question.
- The Constitutional Test had no decision rule ("fails several") → an editorial rule was added at adoption (see amendment log 1.0.0).
- The Articles mix "shall" and "should" without saying which binds → the header now defines them. The article text itself was left unchanged.

## H. v4 — External review applied

The v4 review notes described seven fixes as "already made" but arrived without the corresponding files, so all of them were implemented here against v3.

### H.1 Consistency fixes

41. **Key bootstrap.** seq 0 is a self-signed system `REGISTER_KEY` pinned in deployment config; `REGISTER_KEY` is self-signed with `contributor_id = null`; `signer_key_id` is authoritative elsewhere (02 §1.2a).
42. **ACCEPT recursion.** Contributions are now CONTROL (self-effective if authorized) or EPISTEMIC (uncounted until accepted). The undefined `PROPOSED` status is gone; proposals are rows with `accepted_seq = null`. Who may accept what is tabulated (02 §1.1a).
43. **Coverage ceiling.** The checklist denominator comes from the model, and a release is rejected if any declared check is unexecutable (03 §8).
44. **Audit sampling anchored** to the contribution's own seq, with inputs stored in `audit_schedules`; `outcome_is_unusual` defined (05 §9).
45. **Two-model contradiction** in 05 §14 fixed.
46. **Takedown vs. replay.** Redaction manifests, `CHAIN_VERIFIED_WITH_REDACTIONS`, and `UNREPRODUCIBLE_REDACTED` instead of claiming complete replay (02 §5).
47. **Cross-language determinism narrowed** to canonical outputs on shared fixtures, with a `rounding_boundary` flag (03 §10).

### H.2 Product and strategy changes

48. Product hypothesis narrowed to single-user/team value; public graph treated as emergent (README, 01 §1.1).
49. Prior art positioned as infrastructure; PROV/nanopublication export mappings planned for P1 (01 §1.2, 09 §2).
50. Claim identity: no text uniqueness; candidate relationships only; explicit, reversible `MERGE_CLAIMS`; P0 test with a near-duplicate narrower claim (02 §3.3, 07 Phase 2).
51. "Determinism is not objectivity" stated as a principle (README 15, 03 §1, 10).
52. Audit cost retained for later net-value scheduling (`audits.effort_seconds`, 09 §1).
53. Correlated AI errors added to the threat model; independence extended to verification processes (05 §1, 04 §3.1).
54. Answer cards are the default view; numbers sit behind Show calculation (06 §4).
55. **New public demo**: an AI memo with a viral statistic that traces to one customer survey, an omitted sampling qualifier, a near-duplicate narrower claim, and a fabricated journal citation (08). Golden values for both models verified by the reference scorer. Watchers moved to `examples/watchers/` as an internal stress test.
56. Per-source answer cards and a P1 embeddable card API (06 §5).
57. "First Experiments" added after P0 (07).
58. Outward-facing examples in 02, 03, 04, 06 switched from Watchers to the public demo.

### H.3 Where this revision departs from the v4 notes

59. **`QUALIFIER_CHECK` promoted to P0 instead of shrinking the checklist to three.** The notes' fix #3 (three P0 checks) conflicts with their own recommendation #16, whose public demo depends on discovering an omitted qualifier. Keeping the general fix (model-declared, executable checklist) and promoting the task resolves both.
60. **Coverage is not shown as low/medium/high.** The notes' #15 suggests "evidence coverage: low / medium / high." A checklist can't support that label — "high" would read as "most evidence found," which Article VIII warns against. Shown as "review checks N of M."
61. **ClaimReview output comes with conditions.** ClaimReview expects a truth rating, which conflicts with the no-verdict display rules; any use is opt-in per record and carries the state and model rather than a verdict (09 §2).
62. **Model-family diversity is declared, not verified.** Useful, but the notes' #14 should not be read as a strong guarantee (04 §3.1).
63. **Personal belief overlays** are listed in the notes' section C as an existing strength; they are P1 and reserved only (02 §3.6a).
64. **New bug found while building the demo:** with a non-0.50 prior, the v3 state rule labeled a claim with only supporting evidence "leans contradicted" (08 `C6`). Directional states now require evidence in that direction (03 §4 Step 5). Watchers golden values are unaffected.
65. **Supersession needed a real mechanism.** The qualifier story requires revising other contributors' links; `SUPERSEDE_LINK` was added, and it requires acceptance by a different principal.

## I. Post-v4 consistency pass

66. Cross-reference and path fixes only; no semantic change. `04 §7` and `05 §2, §5` now use the versioned `/api/v1/` paths that `06` defines. `04 §4.2` derives `idempotency_key` from `signer_key_id`, matching the `02 §3.1` schema (it said `contributor_id`). `13` Article XV points at `02 §3.6a` (it said §3.7). `05 §16` no longer implies an `anomaly` factor already exists in the §9 formula. The reference scorer's docstring cites `08 §8` for the golden table.

## J. Proposed amendment P-5 (2026-09-19)

Added `P-5 — The ledger runs no model` to `CONSTITUTION-AMENDMENTS.md` on the owner's
instruction. Verified against the code: the only `Llm::Adapter` is the deterministic stub,
no gem or code calls a model API, and the server's only outbound requests are the Stage 17
source fetches. The principle is recorded as Invariant 18 in `CLAUDE.md`, stated in the
README and the FAQ, and the spec README's "LLM features are optional and stubbed by
default" should be read in its light: optional means absent from the server, present in
the connected assistants.

## K. Proposed amendment P-6 (2026-09-19)

Added `P-6 — Money buys no part of the record` after the owner asked whether offering a
sponsors page in exchange for meeting the running costs is consistent with the
constitution. It is: Article XII forbids silent capture rather than funding, and says
nothing about money at all. P-6 writes the missing rule down, that support buys no
epistemic thing and no altered procedure, that sponsors are named publicly, and that
support which would make the record look bought is refused. The contact page states it in
plain words and links the amendment log.

## L. Extraction is accepted by the system, and the demo gains a second volunteer (2026-09-19)

**What changed.** `CLAIM_EXTRACTION` results are now accepted by the system after
validation, like the other object-adding task types, and their verification tasks open with
them. `08 §7` and the reputation table in `08 §8` change with it: `AgentVerifier` extracts,
and a second volunteer's agent, `AgentChecker` under `Bob`, answers T1, T3 and T4.

**Why.** Extraction was the only task type held as a proposal, waiting for the outline's
principal to accept it. It was the odd one out: a qualifier check and an inference review
both create claims and are accepted by the system, and extraction only ever adds, which is
exactly what `02 §1.1a` sanctions. In practice a volunteer's work sat unusable until someone
came back to approve it, and outlines stalled at nothing.

**What it forced.** Accepting the extraction makes those claims the extractor's principal's,
and `04 §3.1` and Article XI say a principal never checks its own claim. The demo had
`AgentVerifier` extract and then answer the checks on what it had extracted, which was only
possible while the extraction was unaccepted. The rule is right and the narrative was wrong,
so the narrative moved: the checks are another volunteer's, which is how this works outside
a demo anyway.

**What did not change.** Every scoring golden in `08 §8` and in Watchers `§7` is
byte-identical, under both models. Only the reputation table moved, and only by which agent
holds which bucket; every alpha, beta, mean and n is the same.

## M. The per-delegate limit becomes hourly (2026-09-19)

**What changed.** `agent_delegations.max_tasks_per_day` is now `max_tasks_per_hour`, counted
over a rolling hour rather than a calendar day, in `02 §` (domain model) and `04 §5`.

**Why.** A first pass over a two-hour podcast transcript was measured at about 1,600 signed
writes: 34 per leaf across 47 leaves, plus the outline. Against the old named cap of 1,000 a
day, an investigation stopped roughly two thirds of the way through and could not resume
until the next calendar day. The cap exists to bound a runaway agent, not to make a
legitimate long job impossible, and an hour is the window that does the first without the
second. Named delegations are now 5,000 an hour, which carries two complete investigations
of that size with headroom; anonymous ones are 500.

**Rolling, not calendar.** A fixed boundary lets an agent spend a full cap at 10:59 and
another at 11:01, so a window meant to bound a burst briefly permits twice the rate. Both
the write cap and the task-lease limit count backwards from now.

**What it forced.** The field is written into signed `DELEGATE` payloads, so the name is a
statement in the log and leaving it saying `per_day` while it meant per hour would have put
a false one there. Renaming it means contributions already signed carry the old key:
`Ledger::Appliers::Delegate` reads either, and rejects a payload carrying both, so replay
reproduces every historical row unchanged (Invariant 2). Delegations signed under the old
name are now enforced hourly at the number they were given daily, which loosens them; that
is a consequence of one column holding both, and the alternative — two columns, two
meanings, forever — is worse.

## N. The constitution revised in place before first release (2026-09-23)

**What changed.** The owner asked for a review of `12-constitution.md` for inconsistencies
and loopholes, then for every finding to be applied to 1.0.0 as the initial version, since
no node has been released. `CONSTITUTION-AMENDMENTS.md` lists the changes one by one.

**Why.** The review found three kinds of problem:

- **Loopholes.** Core protections were written as "should", and XXV's amendment rule was
  one of them. The bans on rewriting and deletion were limited by "silently", "accepted",
  and "merely because they were later found to be wrong". Nothing named who adopts an
  amendment. Moderators and defaults had no governing text. Test questions 2 and 10 could
  not block. Nothing protected the people claims are about.
- **Inconsistencies.**
  - Three running mechanisms rested on proposals that had not been adopted.
  - The adopted text was never signed into the log, although the amendment log said it
    would be.
  - Article XI promised that trust could be earned, but auditing could only be reached
    through a self-declared tier.
  - `13` said the tier never affects a score, which is false through audits.
  - The Test's answers were said to go in `IMPLEMENTATION.md`, but they go in stage files.
- **Unrecorded violations.** The node breaks several "musts" that `13` marked as met:
  IX (passages counted as independent, and origins splittable by anyone), VII (challenged
  links missing from the trace, and `code_hash` coverage), XXIV (one link reaches
  SUPPORTED), and XVIII (an investigation headline that reads as a verdict).

**What it forced.**

- `13` gains Gap rows for everything the new text asks and the node does not yet do.
  Stage 43 carries most of the remedies.
- `AMEND_CONSTITUTION` is implemented. It is signed by the system key, and the hash it
  carries must equal that of the text the node serves. `/meta` reports whether the served
  text is the one recorded.
- The Test's blocking list is updated in `10` and `CLAUDE.md`.

## O. A score and a badge at every level (2026-09-23)

**What changed.** The owner asked for a score wherever there is enough evidence for one, on
claims, investigations and outlines, and for a small badge (icon only, meaning on hover) at
every parent level of an outline.

- **Claims.** The answer card now shows "Score: 0.8581 under … at snapshot N" under the
  headline, and the claims list has a Score column. 06 §4 rule 1 and Invariant 16 changed
  from "numbers on request" to "numbers never the headline". Rule 3 is untouched:
  INSUFFICIENT_EVIDENCE and NOT_APPLICABLE show no number.
- **Outlines.** Every section gets the reading `Investigations::Verdict` already gave an
  investigation. The figure is the product of the probabilities, shown only when every
  checkable claim has one. 06 §6 said no section ever gets a score. It now says what the
  reading is and what it never is.

**What building it found.** The investigation rule treats a set as one statement, so any
part against the evidence makes the whole lean against it. Applied to an outline on the
development node, it read a 54-claim outline, with 36 claims holding and 6 against, as
"Leans against". A section is a collection of separate statements, so it is now read by
proportion (06 §6 lists the thresholds, and a spec pins the measured case).

**Corrected the same day.** A section's figure was first the investigation's product, shown
only when every checkable claim had a probability. On a real outline almost no section
qualified, because nearly every section held one claim with too little evidence. The few that
did qualify shrank with their size: 0.0047 for a chapter whose claims mostly held. The owner
saw no score anywhere on the page. A section's figure is now the average score of its scored
claims, shown once at least half its checkable claims have one, and it appears beside every
heading and claim in the tree as well as on hover. Investigations keep the product, since
an investigation is one statement.

The owner then asked whether the badges should be based on the score. They should: the
proportion rule could put "Leans against" beside an average of 0.70. A section's badge is now
its average read through the model's state bands, the same bands that set a single claim's
state.

## Open questions for the project owner

- Adopt, revise, or reject proposed amendments P-4 and P-6? (P-1, P-2, P-3 and P-5 were adopted into 1.0.0 on 2026-09-23.)

- Data license for the public log (CC0 vs CC-BY)?
- Who holds the system key and appoints moderators after the POC?
- Should `LEGAL` claims be scored at all before a legal model exists (currently: not truth-evaluable by default)?
- Is `TEXTUAL` the right name, or should it be folded into `OBSERVATIONAL` with a qualifier?
