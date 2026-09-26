# Constitution Amendment Log

Append-only once the ledger is released. Every entry follows Article XXV: what changed, why, what motivated it, what risks it introduces, and compatibility impact. Once the ledger is running, each adopted entry is also recorded as an `AMEND_CONSTITUTION` contribution containing the new `constitution_hash`.

---

## 1.0.0 — Initial adoption

- **What:** Articles I–XXV, Constitutional Test, and Foundational Statement adopted as written by the project owner. Editorial additions only: a header stating version, precedence, the meaning of "shall/should", and scope; and a paragraph requiring the Constitutional Test answers to be recorded for sensitive features.
- **Why:** The spec needed an explicit rule for what happens when an implementation choice conflicts with an Article. Without one, Article XXV's "never drift through undocumented implementation choices" had no enforcement point.
- **Risks:** The recording rule adds process overhead to the POC. It is limited to features touching scoring, identity, reputation, moderation, visibility, or history.
- **Compatibility:** None; no prior version.

### 1.0.0 revised before first release (2026-09-23)

The project owner decided that, because no node had been released, the review's findings should be folded into 1.0.0 rather than adopted as 1.1.0. The version number is unchanged, and the hash is not. `GET /api/v1/meta` publishes the new hash. From this revision on, a text takes effect only when it is recorded as a signed `AMEND_CONSTITUTION`, and the first such record is this text.

- **What:**
  - **Proposals adopted.** P-1 (protection of persons) and P-2 (visible removal) are folded into Article XIII, P-3 (unknowability designations are claims) into Article VI, and P-5 (the ledger runs no model) into Article XIV.
  - **Header.** A departure from a "should" must be recorded in `13` or it is a violation.
  - **"Should" becomes "shall"** in II, XII, XIII, XVIII, XIX and XXV.
  - **Rewriting and deletion (XII and XIII).** The qualifiers "silently", "accepted" and "merely because they were later found to be wrong" are removed from the prohibitions. XIII now names the only permitted removal and its grounds, and restriction may never be grounded in disagreement.
  - **Powers held by roles, and defaults and selection (XII).** Every power a role holds is exercised only through signed, visible, challengeable contributions. The default scoring model, search ranking, task priority, what is proposed for examination, and the wording of summary verdicts are governed by published rules.
  - **Earned standing (XI).** Every standing, including the standing to audit, can be reached through a record of audited work. Attestation alone is never the only route.
  - **Personal belief (XV).** It may enter the shared layer only as an ordinary attributed contribution.
  - **Aggregates and selection (XVIII).** A summary over many claims is not a verdict on a person or party, and selection is made visible.
  - **Adoption (XXV).** Who adopts an amendment, that adoption takes effect when it is signed into the ledger, and that no amendment may resolve a conflict in the same change that introduces it.
  - **The Test.** Answers go in the change's own record. Questions 2 and 10 now block, "selection" joins the list of sensitive features, and a justification is published and open to challenge.
- **Why:** The review found protections whose triggers were narrow enough to walk around:
  - a rewrite was forbidden only if silent;
  - a deletion was forbidden only if made "merely" because the contribution was wrong;
  - only accepted contributions were protected;
  - the amendment rule itself was a "should";
  - moderators and defaults had no governing text;
  - Article XI promised earnable trust that the code made unreachable for auditing.

  Three mechanisms already running (`TAKEDOWN`, reasons on `SET_TRUTH_EVALUABLE`, and Invariant 18) rested on proposals nobody had adopted.
- **Risks:**
  - **The node now falls short of the text in several places**, each recorded as a Gap in `13`. The chief ones are the moderator's bypass of audit eligibility, the lack of an earned route to auditing, defaults set without a recorded rule, and the investigation headline, which reads as a verdict.
  - **Removal grounds are narrower.** Moderators lose any removal ground other than law or protection of persons.
  - **Owner adoption concentrates authority**, and the text now says so.
- **Compatibility:** The text changes without a version change, which is allowed only because nothing was released. Any external copy of the 1.0.0 hash taken before 2026-09-23 is stale. The live development node has never recorded an `AMEND_CONSTITUTION`.

---

## Proposed (not adopted — requires the project owner's decision)

These came out of reconciling the constitution with the POC spec. P-1, P-2, P-3 and P-5 were adopted into the 1.0.0 revision of 2026-09-23 and are kept below as the record of where that text came from. P-4 and P-6 remain proposed, and the spec implements the conservative reading of each.

### P-1 — Protection of persons (adopted into 1.0.0, 2026-09-23)

- **Proposed text:** *"The system shall not become an instrument for harming identifiable individuals. Claims about private persons, personal data, and material whose publication is unlawful may be restricted. Every such restriction shall itself be recorded, attributed, and publicly visible as a restriction, even where its content cannot be."*
- **Why:** The constitution protects contributors' privacy (Articles XI, and the spec's 05 §15) but says nothing about the people claims are *about*. A permanent, signed, append-only ledger of scored assertions is an unusually durable defamation and doxxing vector.
- **Risk:** Restriction powers can be abused for capture (Article XII). The second sentence is the safeguard: restriction is never silent.
- **Compatibility:** The POC already excludes private-individual claims and makes quarantine visible (05 §13).

### P-2 — Lawful removal is visible (adopted into 1.0.0, 2026-09-23)

- **Proposed text (addition to Article XIII):** *"Where law requires content to be removed, the content may be withdrawn, but the fact of removal, its date, its stated legal basis, and the cryptographic record of what was removed shall remain."*
- **Why:** Article XIII forbids erasing contributions "merely because they were later found to be wrong," which does not address legally compelled removal. The spec needs a takedown path; without this amendment it sits in an unaddressed gap.
- **Risk:** Even a visible tombstone can leak that something sensitive existed. Accepted as the lesser harm compared with silent removal.
- **Compatibility:** Implemented as the `TAKEDOWN` action (02 §5).

### P-3 — Designations of "unknowable" are themselves claims (adopted into 1.0.0, 2026-09-23)

- **Proposed text (addition to Article VI):** *"A designation that a claim is untestable, non-empirical, or outside a model's competence is itself a contribution subject to provenance, audit, and challenge."*
- **Why:** Article VI makes "untestable" a valid state. Without this sentence, labeling a claim untestable could shield it from evidence — the evidence-free denial Article XXIII warns against, pointed the other way.
- **Compatibility:** Implemented: `SET_TRUTH_EVALUABLE` requires a `not_evaluable_reason` and is auditable (02 §3.3).

### P-4 — Strength of evidence for extraordinary conclusions

- **Question:** Article XXIV requires extraordinary conclusions to have "correspondingly strong" evidence. `ledger-default@0.1.0` uses the same 0.50 prior for ordinary and extraordinary textual/historical claims, so it satisfies only the "well-audited" half (via `provisional` and the high-impact audit policy).
- **Options:** (a) accept this as a v0.1 limitation; (b) add an auditable `prior_class` qualifier (e.g. `ORDINARY`, `EXTRAORDINARY`) set by signed contribution and mapped to priors in a future model; (c) leave priors flat and let competing models (Article XII) express different stances.
- **Risk of (b):** whoever sets `prior_class` holds real power over outcomes (Articles X, XII). Must be contestable and visible in the trace.
- **Current spec:** option (a), recorded as a known gap; (b) listed as deferred in 09.

### P-5 — The ledger runs no model (adopted into 1.0.0, 2026-09-23)

- **Proposed text (addition to Article XIV):** *"The system itself shall perform no model inference. It is a deterministic framework, signed records, closed vocabularies, replayable projections, and versioned scoring, through which people and the AI agents they bring collaborate on a durable record of claims and the reasons for them. Every judgment that requires a model shall be made outside the system, by a person or by an agent acting for one, and shall enter it as an attributed contribution open to audit."*
- **Why:** Article XIV makes humans and AI contributors, not oracles, and Article VII makes every probability model-conditional and reproducible. A model running inside the ledger would be an unattributed, unreproducible contributor whose outputs could not be replayed, audited, or challenged like any other. Keeping every model outside, behind a signed contribution, is what makes "reproducible from the log" true.
- **Risk:** Some conveniences (drafting summaries, splitting text into claims, deduplicating requests) are worse without a model. Accepted: they run on deterministic stubs, or become tasks and tools for connected agents whose answers are signed.
- **Compatibility:** Implemented since the owner's instruction of 2026-09-19: the only `Llm::Adapter` is the stub; summaries cite graph ids only (04 §10); extraction, review, and deduplication are tasks or tools for connected assistants (Stages 14, 18, 21, and the review queues); the server's only outbound requests are Stage 17 source fetches. Recorded as Invariant 18 in `CLAUDE.md`.

### P-6 — Money buys no part of the record

- **Proposed text (addition to Article XII):** *"The project may accept donations, sponsorship, or grants to meet its running costs. No such support shall purchase a claim, an assessment, a scoring model, a task, an audit result, a moderation decision, or standing of any kind, and none shall alter the procedures applied to any subject or party. Every sponsor shall be named publicly. Support that would make the record appear bought shall be refused."*
- **Why:** Article XII names commercial advantage among the ways a system is captured, and answers it with structural defences: attribution, append-only history, open models, public traces, independent audits. It says nothing about the money that keeps the node running, and a single-maintainer project funded personally will be asked for sponsorship sooner or later. The gap matters because the harm here is not a rewritten entry, which the log would expose, but an unrecorded arrangement that never touches the log at all. Article XII's own sentence is about silence: no operator should be able to *silently* rewrite the record. Naming every sponsor is the same principle applied to funding.
- **Risk:** A named sponsors page is itself a mild form of influence, since prominence is worth something. Accepted as the lesser harm: the alternative is either refusing all support, which ends the node, or taking it quietly, which is the thing Article XII exists to prevent. The refusal clause is the safeguard, and it is deliberately a judgment rather than a rule, because the cases that matter will not be anticipated.
- **Compatibility:** Nothing in the POC pays attention to funding, and nothing would: a sponsors page is ordinary content outside the log, carrying no claim and citing nothing. The contact page already states the rule in plain words and links here. Article XVIII already requires the same procedures regardless of institutional alignment, so the "no altered procedures" clause restates an existing duty rather than adding one.
