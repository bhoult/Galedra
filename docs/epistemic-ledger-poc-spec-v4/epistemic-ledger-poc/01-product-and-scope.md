# 01 — Product and Scope

This file operationalizes `12-constitution.md`, which takes precedence over it.

## 1. Problem

Research and fact-checking are fragmented. An AI agent can spend significant inference gathering and analyzing evidence, produce a useful answer, and terminate. Another agent later repeats most of that work.

Existing systems organize documents, citations, entities, embeddings, or model weights. They generally do not organize the **atomic reasons for believing a claim** in a persistent, machine-actionable, adversarial graph.

The POC demonstrates a reusable substrate for cumulative investigation.

### 1.1 Product hypothesis (v4)

The narrow bet:

> AI agents increasingly perform research that is expensive to repeat and hard to audit. A durable, signed, reusable evidence record makes that work cumulative.

P0 must show that **one user or a small team gets enough value on day one to keep using the ledger even if nobody else ever contributes.** A public "web of reasons" is a possible *emergent* layer built from useful local records, not the initial product. Public argument-mapping systems have repeatedly stalled on contribution cost, moderation, cold start, and the fact that readers want answers rather than graphs; this design does not assume it will escape those forces.

Target early uses, in order:

1. citation and quotation verification for AI-generated research and documents (the public demo, 08);
2. private or team evidence ledgers for investigative and analytical work;
3. research groups tracking one literature question over time;
4. public shared claim graphs, only after 1–3 show durable value.

This is sequencing, not a data-model change. The same log, scoring, and constitution serve all four.

```text
AI draft → extracted claims and citations → verification tasks
        → reusable signed evidence records → audit trail → compact "why" answer
```

### 1.2 Relationship to prior art

Most primitives exist elsewhere: nanopublications and Micropublications (claim/evidence/provenance units), W3C PROV (provenance), ClaimReview (fact-check markup), Wikidata statements with qualifiers, Certificate Transparency (append-only logs), scite (support/contradiction classification), Rootclaim (public Bayesian claim assessment). The novelty here is the **combination**: signed agent work packets, atomic evidence records, explicit independence, audited task reputation, and versioned reproducible scoring.

Treat prior art as infrastructure: keep the P0 schema simple and relational (no RDF core), and plan documented export mappings (09 §2).

---

## 2. Primary Abstraction

An **argument compiler** that emits a persistent **Epistemic Intermediate Representation (EIR)**.

```text
input:     speech / sermon / paper / brief / business plan / historical source / AI answer

compile:   document
             -> atomic claims (typed)
             -> evidence with exact provenance
             -> support / contradict / qualify links
             -> independence groups
             -> competing hypotheses (P1)
             -> deterministic scoring

output:    auditable evidence graph + score traces + summaries + agent task packets
```

---

## 3. Use Cases (motivating, not all in POC)

| Use case | What the graph must represent | POC tier |
|---|---|---|
| General claim analysis | Atomic assertions, types, non-evaluable statements, evidence | P0 |
| Citation / statistic verification for AI drafts | Extracted claims, citations, origin tracing, qualifiers | **P0 (public demo)** |
| Textual / historical source | What a text says vs. how it is interpreted | P0 (internal stress test) |
| Competing hypotheses | Question containers, hypotheses, discriminating evidence | P1 |
| Political speech | Claim-level assessment only; never a speaker score | P1 (display rule in 06) |
| Sermon / theology | Textual, translation, historical, interpretive, metaphysical claims kept distinct | Deferred beyond types |
| Business plan | Dependency chains among assumptions | Deferred (needs propagation) |
| Legal dispute | Allegation, exhibit, testimony, rule, burden, posture | Deferred (needs legal model) |

Across all of them: do not force non-empirical claims into empirical scores, and do not collapse many claims into one ranking of a person.

---

## 4. Claim Types

```text
OBSERVATIONAL      QUANTITATIVE     HISTORICAL      TEXTUAL
COMPARATIVE        CAUSAL           FORECAST        LEGAL
INTERPRETIVE       DEFINITIONAL     ATTRIBUTED_BELIEF
NORMATIVE          RHETORICAL       METAPHYSICAL
```

`TEXTUAL` ("source S says X", "the narrative attributes X to Y") is added because the seeded demo, quote verification, and sermon/legal use cases all depend heavily on claims about what a text contains, which behave differently from claims about what happened.

Each claim has exactly **one** type. `truth_evaluable` defaults from the type (table below) and may be overridden only by a signed contribution.

| Default `truth_evaluable = true` | Default `false` |
|---|---|
| OBSERVATIONAL, QUANTITATIVE, HISTORICAL, TEXTUAL, COMPARATIVE, DEFINITIONAL, ATTRIBUTED_BELIEF, CAUSAL, INTERPRETIVE | NORMATIVE, RHETORICAL, METAPHYSICAL, FORECAST (until resolution; P1), LEGAL (deferred model) |

Whether a truth-evaluable type is actually *scored* is decided by the scoring model's `scored_types` list (see 03). A type outside that list gets `NOT_APPLICABLE`, never a number.

---

## 5. Scope Tiers

The previous draft asked a POC to do everything at once. Build strictly in this order.

### P0 — required for Definition of Done

- contribution log (signed, hash-chained, replayable) and projections
- sources, source locations, claims, evidence items, evidence–claim links, claim edges (stored and displayed, not propagated)
- independence groups
- deterministic scoring models `ledger-default@0.1.0` and `ledger-strict@0.1.0`, `/compare`, traces, review coverage, stability, assessment states with `not_applicable_reason`
- snapshots by `seq`
- contributor keys, server-custodied keys for UI users, agent delegation, revocation
- audits and task/domain reputation
- tasks with leases; task types `CLAIM_EXTRACTION`, `EVIDENCE_VERIFICATION`, `OPPOSING_EVIDENCE_SEARCH`, `SOURCE_INDEPENDENCE_CHECK`, `QUALIFIER_CHECK`
- claim identity handled by explicit relationships (`SAME_AS`, `NARROWS`, …) and explicit, reversible merges; no text-uniqueness constraint
- compact answer cards per claim and per analyzed source
- stubbed summary generation with citation validation
- public demo (mundane statistic + fabricated citation), Watchers stress test, `bin/demo`, example agent client
- minimal Hotwire UI, including model selector, Weaknesses page, and public moderation log
- constitution hash in `/meta`; `AMEND_CONSTITUTION`, `TAKEDOWN`, visible quarantine

### P1 — build only after P0 passes

- questions and hypotheses pages
- `CLAIM_DEDUPLICATION` producing candidate edges only (pg_trgm first, pgvector later)
- verification-process diversity constraints (04 §3.1)
- embeddable answer cards for external tools (06 §5)
- PROV / nanopublication export mappings
- real LLM adapter for extraction and summaries
- political-speech aggregate view
- JSON export bundles
- personal assessments / belief lenses (02 §3.6a; constitution Art. XV)
- question-level states `UNDERDETERMINED` and `INDISTINGUISHABLE` (13, Art. VI mapping)
- suspicious contribution-cluster report (05 §16)

### Deferred (documented in 09; do not build)

inferences/premises tables, tests and test–hypothesis effects, entity resolution, context/omission status, forecast dual scoring, causal-design metadata, `prior_class` for extraordinary claims (proposed amendment P-4), claim-to-claim score propagation, pgvector, marketplace UI, cost accounting, federation.

---

## 6. Core User Experiences (P0)

### Claim page

Claim text and type; assessment state; probability *with* model version and snapshot; review coverage with checklist; stability; counted and suppressed evidence by independence group; qualifying evidence; claim edges; summary; contribution history; score trace.

### "Show me why"

Deterministically selected: strongest counted support, strongest counted contradiction, suppressed dependents, review-coverage gaps, and the single evidence addition that would move the score most under the current model (computable by re-running the scorer with one hypothetical link).

### Volunteer agent contribution

A user authorizes an agent key. The server leases a signed task packet. The agent returns a signed result. The result is validated, accepted into the log, and remains subject to audit.

---

## 7. Non-Goals

Do not attempt to: determine ultimate truth; build one universal probability model or ontology; arbitrate moral values; replace courts, scientists, journalists, clergy, or analysts; prevent all coordinated attacks; build a blockchain; index the web; host copyrighted full text without permission.

**Out of scope for the POC: claims about identifiable private individuals.** A public ledger of scored assertions about private people is a defamation and privacy hazard. The claim-creation flow should require a checkbox affirmation, and moderators can quarantine violating claims (05 §13).

---

## 8. Terminology

- **Contribution** — a signed envelope recording one action; the unit of the log.
- **Log sequence (`seq`)** — server-assigned, gap-free, monotonically increasing integer for each accepted-into-log contribution.
- **Projection** — a normal table (claims, evidence links, …) derived from the log.
- **Snapshot** — a named `seq` plus the chain hash at that `seq`.
- **Claim** — one minimal proposition that could be independently assessed.
- **Source / Source location** — a stored artifact and an exact place inside it.
- **Evidence item** — a specific observation anchored to a source location.
- **Evidence link** — an attributable assertion that an evidence item supports, contradicts, qualifies, or is neutral to a claim.
- **Independence group** — a set of evidence items sharing an upstream origin.
- **Audit** — an independent evaluation of a prior contribution; itself a contribution and itself auditable.
- **Hypothesis / Question** (P1) — an explanatory claim and its container of alternatives.

---

## 9. Design Philosophy

Make disagreement cheap and hidden assumptions expensive.

One contributor may say "E supports C." Another may say "it does not, because qualifier Q was omitted." The log stores both; the scoring model resolves current weight by public, versioned rules.
