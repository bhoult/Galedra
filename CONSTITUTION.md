# 12 — Constitutional Principles of the Epistemic Ledger

| | |
|---|---|
| Version | 1.0.0 (initial adoption) |
| Status | Adopted with the POC spec v3 |
| Amendment log | `CONSTITUTION-AMENDMENTS.md` |
| Implementation map | `13-constitutional-compliance.md` |
| Integrity | `sha256` of this file is published at `GET /api/v1/meta` as `constitution_hash` |

**Precedence.** This document outranks every other file in this repository. If a spec file, scoring model, or implementation choice conflicts with an Article, the Article governs and the conflict must be recorded in `13-constitutional-compliance.md` (as a known gap) or resolved by an explicit amendment under Article XXV. It is never resolved silently.

**Reading the language.** "Shall" and "must" state binding commitments. "Should" states a strong default that may be departed from only with a documented reason. Examples are illustrative, not exhaustive.

**Scope.** The Articles describe the project, not the POC. Some are only partly realized in v0.1; `13-constitutional-compliance.md` says which, and how.

## Preamble

The Epistemic Ledger exists to help people and machines reason more carefully about what is known, what is uncertain, what is disputed, and why.

Its purpose is not to declare an official truth, enforce consensus, reward conformity, or replace human judgment.

Its purpose is to preserve the structure of inquiry:

- what was asserted;
- what evidence bears on it;
- where that evidence came from;
- how claims relate to one another;
- what assumptions and inferences connect evidence to conclusions;
- how reliable contributors have been at specific tasks;
- what remains unresolved;
- and what new evidence would most improve understanding.

The system is intended to make knowledge cumulative, disagreement inspectable, correction normal, and uncertainty explicit.

These principles are constitutional: implementation choices, scoring models, interfaces, and governance may evolve, but changes that violate these principles should be treated as changes to the nature of the project itself.

---

## Article I — Claims Are Not Truth

The system shall store **claims**, not declarations of truth.

No claim becomes true because:

- the system contains it;
- many users endorse it;
- an AI generated it;
- a prestigious person submitted it;
- an institution supports it;
- it matches prevailing consensus;
- or a scoring model assigns it a high probability.

A claim is an object of evaluation.

The system's role is to preserve and expose the reasons for and against believing it.

---

## Article II — Evidence Must Be Traceable

Every material evidentiary contribution should be traceable to its provenance.

Where possible, the system shall preserve:

- the source;
- the exact location within the source;
- the relevant excerpt, measurement, or observation;
- the source version or content hash;
- the contributor who extracted or classified it;
- the process by which it entered the system;
- subsequent audits and corrections.

A conclusion that cannot be traced downward toward evidence or explicit assumptions must be visibly distinguished from one that can.

---

## Article III — Evidence and Interpretation Are Distinct

The system shall distinguish between:

- what a source says;
- what was observed or measured;
- what a contributor infers from it;
- and what broader conclusion depends upon that inference.

For example:

> "A source contains statement X"

is different from:

> "X is factually correct."

Likewise:

> "A dataset shows correlation Y"

is different from:

> "Y caused Z."

The system shall preserve these distinctions rather than collapsing them into a single truth label.

---

## Article IV — Atomicity

Claims should be decomposed into the smallest independently evaluable propositions practical for the domain.

Compound assertions should be split when their parts could differ in evidential support.

This enables:

- precise correction;
- evidence reuse;
- dependency analysis;
- localized disagreement;
- and efficient agent contribution.

The system should prefer many small reusable claims over large narrative assertions.

---

## Article V — Contradiction Is Preserved

Conflicting claims and evidence shall be allowed to coexist.

Disagreement shall not be resolved by deleting inconvenient evidence or suppressing minority hypotheses merely because they are unpopular.

Instead, contradictions should be represented explicitly through typed relationships such as:

- supports;
- contradicts;
- qualifies;
- requires;
- derives from;
- predicts;
- or provides an alternative explanation.

The system should make disagreement legible rather than hide it.

---

## Article VI — "Unknown" Is a Valid Conclusion

The system shall not force a conclusion where the evidence does not justify one.

Valid states include:

- unknown;
- unresolved;
- underdetermined;
- insufficient evidence;
- untestable with current methods;
- dependent on disputed assumptions;
- and observationally indistinguishable from alternatives.

The inability to reach a conclusion is not a system failure.

False certainty is.

---

## Article VII — Probabilities Are Model-Conditional

Any numerical assessment of a claim must be understood as conditional on an explicit scoring model, assumptions, priors, and available evidence.

The system shall not present a computed probability as an objective property of reality.

Every reproducible score should identify:

- the graph snapshot;
- the scoring model;
- the model version;
- the evidence included;
- evidence dependency handling;
- and the calculation trace.

Different scoring models may legitimately produce different results from the same evidence.

---

## Article VIII — Evidence Coverage Is Separate From Confidence

The system shall distinguish:

> "The evidence we have examined strongly supports this claim"

from:

> "We have examined most of the evidence that may exist."

A claim may have high modeled probability and low evidence coverage.

Both must remain visible.

---

## Article IX — Evidence Independence Matters

Repeated reporting of the same underlying source does not create independent confirmation.

The system shall attempt to identify common origin, shared datasets, citation chains, coordinated sources, and other dependencies.

Ten dependent repetitions must not be treated as ten independent observations.

Independent corroboration should be explicitly distinguished from repetition.

---

## Article X — Reputation Measures Reliability, Not Authority

Contributor reputation shall reflect demonstrated performance on specific tasks and, where useful, specific domains.

It shall not function as a social status score or universal measure of credibility.

A contributor may be:

- excellent at quotation verification;
- mediocre at causal inference;
- unknown in ancient languages;
- and highly reliable in financial calculations.

Reputation should be derived from auditable outcomes.

A contributor's worldview, ideology, religion, institutional affiliation, popularity, or conformity to consensus must not automatically confer epistemic authority.

---

## Article XI — Identity Does Not Replace Evidence

Cryptographic identity exists to create accountability and auditability, not hierarchy.

A signed contribution proves who or what submitted it and whether it has been altered.

It does not prove the contribution is correct.

Even high-reputation contributors must provide evidence where evidence is required.

Anonymous or pseudonymous contributors may earn trust through a durable record of accurate work.

---

## Article XII — The System Must Resist Capture

The project shall assume that powerful actors may eventually attempt to manipulate it for:

- political;
- commercial;
- ideological;
- institutional;
- religious;
- governmental;
- or personal advantage.

Defenses against capture should include:

- cryptographic attribution;
- append-only history;
- open scoring models;
- public calculation traces;
- independent audits;
- evidence provenance;
- independence analysis;
- reproducible snapshots;
- adversarial review;
- and the ability to run alternative scoring models over the same evidence.

No operator should be able to silently rewrite the epistemic history of the system.

---

## Article XIII — Corrections Do Not Erase History

Accepted contributions should not be silently rewritten or deleted merely because they were later found to be wrong.

Corrections should:

- challenge;
- invalidate;
- supersede;
- qualify;
- or replace the active role of a prior contribution

while preserving the historical record.

Users should be able to reconstruct:

> what the system believed at a given time and why.

Knowledge should evolve visibly.

---

## Article XIV — Humans and AI Are Contributors, Not Oracles

Neither humans nor AI systems shall be treated as intrinsically authoritative.

AI agents may:

- extract;
- search;
- verify;
- challenge;
- classify;
- calculate;
- summarize;
- and propose hypotheses.

Humans may do the same.

Both remain subject to provenance, audit, evidence requirements, and correction.

No model family should become a privileged source of truth.

---

## Article XV — Shared Evidence and Personal Belief Are Separate Layers

The system shall distinguish between:

### Shared epistemic state

- claims;
- evidence;
- provenance;
- relationships;
- audits;
- scoring models;
- uncertainty;
- and reproducible assessments.

### Personal belief

An individual may maintain a personal estimate, interpretation, or belief lens based on:

- different priors;
- different model preferences;
- personal experiences;
- moral values;
- additional private evidence;
- or subjective judgment.

Personal belief must not silently modify the shared evidence layer.

The system should help users explain:

> "This is what I believe, and this is why"

without presenting that belief as the system's statistical assessment.

---

## Article XVI — Disagreement Should Be Localized

When people reach different conclusions, the system should attempt to identify where the disagreement actually resides.

It may arise from:

- conflicting evidence;
- different priors;
- different definitions;
- different causal assumptions;
- different source-quality judgments;
- different values;
- or different standards of proof.

The system should prefer:

> "You disagree primarily about these three assumptions"

over:

> "One side is simply wrong."

The goal is not forced consensus.

The goal is intelligible disagreement.

---

## Article XVII — Normative Claims Must Not Be Disguised as Empirical Facts

Statements about what people **ought** to do are not equivalent to claims about what **is**.

The system may map:

- premises;
- consequences;
- factual assumptions;
- internal consistency;
- and competing values

behind normative arguments.

It must not assign fake empirical truth probabilities to moral or value judgments merely to create the appearance of precision.

---

## Article XVIII — Political Neutrality Is Structural

For political claims, the same epistemic procedures must apply regardless of:

- party;
- ideology;
- candidate;
- office;
- nationality;
- or institutional alignment.

The system should evaluate claims, not endorse political actors.

It should not produce aggregate political winner scores, preferred candidates, or ideological conformity measures.

Political neutrality should arise from consistent process rather than artificial equivalence between unequal evidence.

---

## Article XIX — Transparency Over Persuasion

The system should not be optimized to persuade users toward a predetermined conclusion.

Its primary responsibility is to expose:

- evidence;
- reasoning;
- uncertainty;
- assumptions;
- and disagreement.

A user should be free to reject the system's default assessment while still being able to inspect exactly how it was produced.

The project should seek understanding before persuasion.

---

## Article XX — Models May Change; Evidence Must Endure

Scoring algorithms, AI models, ontologies, and software architectures will change.

The durable asset is the evidence graph and its provenance.

The architecture should allow future systems to reinterpret old evidence without destroying or rewriting that evidence.

The repository should become more valuable as reasoning models improve.

---

## Article XXI — Research Should Be Cumulative

An agent should not need to rediscover work that another agent has already performed correctly.

Useful atomic contributions should become durable shared infrastructure.

Research tasks should be small enough that independent agents can:

- perform them asynchronously;
- verify them independently;
- and contribute without understanding the entire project.

The system should convert transient inference into persistent knowledge structure.

---

## Article XXII — The System Should Reveal Its Own Weaknesses

The project should actively expose:

- low-coverage claims;
- unstable probabilities;
- disputed source classifications;
- high-impact unsupported assumptions;
- suspicious contribution clusters;
- unverified evidence;
- and load-bearing claims.

The system should make it easy to ask:

> "What would most change this conclusion?"

and:

> "Where are we most likely to be wrong?"

Self-critique is a core function, not an optional feature.

---

## Article XXIII — No Conclusion Is Immune From Re-Examination

Consensus, age, prestige, or prior confidence shall not make a claim permanently unquestionable.

At the same time, reopening a question does not erase accumulated evidence.

Challenges should add to the graph and bear the same burden of provenance as other contributions.

The system must remain open to correction without becoming vulnerable to endless evidence-free denial.

---

## Article XXIV — Efficient Skepticism

Skepticism has value only when it can engage evidence.

The system should distinguish between:

> "This claim is unsupported"

and:

> "I refuse to accept any possible evidence for this claim."

It should likewise distinguish between:

> "This hypothesis is unconventional"

and:

> "This hypothesis is contradicted by evidence."

Unusual claims may be investigated.

Extraordinary conclusions should require correspondingly strong and well-audited evidence.

---

## Article XXV — The Constitution Itself Is Amendable, But Not Silently

These principles may evolve.

Any constitutional change should be:

- explicit;
- versioned;
- publicly documented;
- justified;
- reviewable;
- and preserved historically.

A constitutional amendment should describe:

1. what changed;
2. why it changed;
3. what problem motivated the change;
4. what risks the change introduces;
5. and whether it alters prior compatibility assumptions.

The project should never drift into a different epistemic philosophy through undocumented implementation choices.

---

# Constitutional Test

Before introducing a major feature, ask:

1. Does it make evidence more traceable or less?
2. Does it make disagreement more inspectable or less?
3. Does it increase hidden authority?
4. Does it allow reputation to substitute for evidence?
5. Does it preserve uncertainty?
6. Can the result be reproduced?
7. Can an opposing investigator challenge it using the same system?
8. Can the history of the conclusion be reconstructed?
9. Does it preserve the distinction between shared evidence and personal belief?
10. Would we still want this mechanism if it were used by people whose conclusions we strongly disagree with?

If a feature fails several of these questions, it likely violates the spirit of the project.

**Recording the test.** For any feature that changes scoring, identity, reputation, moderation, visibility, or history, the answers to these ten questions shall be written down (in `IMPLEMENTATION.md` during the POC, and in the change's review record afterward). Any "no" to questions 1, 5, 6, 7, 8, or 9, or any "yes" to 3 or 4, requires a written justification or a design change.

---

# Foundational Statement

The Epistemic Ledger does not seek to own truth.

It seeks to preserve the path by which people and machines approach it.

Its highest commitments are not consensus, authority, or certainty, but:

> **provenance, reproducibility, openness to correction, explicit uncertainty, inspectable disagreement, and intellectual honesty.**

The system succeeds when a person can ask:

> "Why should I believe this?"

and receive an answer that can be examined all the way down to the evidence.

It succeeds even more when the answer is:

> "At present, you should not be certain."
