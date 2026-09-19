# Constitution Amendment Log

Append-only. Every entry follows Article XXV: what changed, why, what motivated it, what risks it introduces, and compatibility impact. Once the ledger is running, each adopted entry is also recorded as an `AMEND_CONSTITUTION` contribution containing the new `constitution_hash`.

---

## 1.0.0 — Initial adoption

- **What:** Articles I–XXV, Constitutional Test, and Foundational Statement adopted as written by the project owner. Editorial additions only: a header stating version, precedence, the meaning of "shall/should", and scope; and a paragraph requiring the Constitutional Test answers to be recorded for sensitive features.
- **Why:** The spec needed an explicit rule for what happens when an implementation choice conflicts with an Article. Without one, Article XXV's "never drift through undocumented implementation choices" had no enforcement point.
- **Risks:** The recording rule adds process overhead to the POC. It is limited to features touching scoring, identity, reputation, moderation, visibility, or history.
- **Compatibility:** None; no prior version.

---

## Proposed (not adopted — requires the project owner's decision)

These came out of reconciling the constitution with the POC spec. The spec currently implements the conservative reading of each and records it as a known gap or interpretation in `13-constitutional-compliance.md`.

### P-1 — Protection of persons

- **Proposed text:** *"The system shall not become an instrument for harming identifiable individuals. Claims about private persons, personal data, and material whose publication is unlawful may be restricted. Every such restriction shall itself be recorded, attributed, and publicly visible as a restriction, even where its content cannot be."*
- **Why:** The constitution protects contributors' privacy (Articles XI, and the spec's 05 §15) but says nothing about the people claims are *about*. A permanent, signed, append-only ledger of scored assertions is an unusually durable defamation and doxxing vector.
- **Risk:** Restriction powers can be abused for capture (Article XII). The second sentence is the safeguard: restriction is never silent.
- **Compatibility:** The POC already excludes private-individual claims and makes quarantine visible (05 §13).

### P-2 — Lawful removal is visible

- **Proposed text (addition to Article XIII):** *"Where law requires content to be removed, the content may be withdrawn, but the fact of removal, its date, its stated legal basis, and the cryptographic record of what was removed shall remain."*
- **Why:** Article XIII forbids erasing contributions "merely because they were later found to be wrong," which does not address legally compelled removal. The spec needs a takedown path; without this amendment it sits in an unaddressed gap.
- **Risk:** Even a visible tombstone can leak that something sensitive existed. Accepted as the lesser harm compared with silent removal.
- **Compatibility:** Implemented as the `TAKEDOWN` action (02 §5).

### P-3 — Designations of "unknowable" are themselves claims

- **Proposed text (addition to Article VI):** *"A designation that a claim is untestable, non-empirical, or outside a model's competence is itself a contribution subject to provenance, audit, and challenge."*
- **Why:** Article VI makes "untestable" a valid state. Without this sentence, labeling a claim untestable could shield it from evidence — the evidence-free denial Article XXIII warns against, pointed the other way.
- **Compatibility:** Implemented: `SET_TRUTH_EVALUABLE` requires a `not_evaluable_reason` and is auditable (02 §3.3).

### P-4 — Strength of evidence for extraordinary conclusions

- **Question:** Article XXIV requires extraordinary conclusions to have "correspondingly strong" evidence. `ledger-default@0.1.0` uses the same 0.50 prior for ordinary and extraordinary textual/historical claims, so it satisfies only the "well-audited" half (via `provisional` and the high-impact audit policy).
- **Options:** (a) accept this as a v0.1 limitation; (b) add an auditable `prior_class` qualifier (e.g. `ORDINARY`, `EXTRAORDINARY`) set by signed contribution and mapped to priors in a future model; (c) leave priors flat and let competing models (Article XII) express different stances.
- **Risk of (b):** whoever sets `prior_class` holds real power over outcomes (Articles X, XII). Must be contestable and visible in the trace.
- **Current spec:** option (a), recorded as a known gap; (b) listed as deferred in 09.

### P-5 — The ledger runs no model

- **Proposed text (addition to Article XIV):** *"The system itself shall perform no model inference. It is a deterministic framework, signed records, closed vocabularies, replayable projections, and versioned scoring, through which people and the AI agents they bring collaborate on a durable record of claims and the reasons for them. Every judgment that requires a model shall be made outside the system, by a person or by an agent acting for one, and shall enter it as an attributed contribution open to audit."*
- **Why:** Article XIV makes humans and AI contributors, not oracles, and Article VII makes every probability model-conditional and reproducible. A model running inside the ledger would be an unattributed, unreproducible contributor whose outputs could not be replayed, audited, or challenged like any other. Keeping every model outside, behind a signed contribution, is what makes "reproducible from the log" true.
- **Risk:** Some conveniences (drafting summaries, splitting text into claims, deduplicating requests) are worse without a model. Accepted: they run on deterministic stubs, or become tasks and tools for connected agents whose answers are signed.
- **Compatibility:** Implemented since the owner's instruction of 2026-09-19: the only `Llm::Adapter` is the stub; summaries cite graph ids only (04 §10); extraction, review, and deduplication are tasks or tools for connected assistants (Stages 14, 18, 21, and the review queues); the server's only outbound requests are Stage 17 source fetches. Recorded as Invariant 18 in `CLAUDE.md`.
