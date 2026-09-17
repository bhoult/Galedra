# 09 — Future Directions

**Nothing in this file is to be built during the POC.** It exists so the coding agent can avoid decisions that would block these later, and so deferred items from earlier drafts have a documented home.

---

## 1. Deferred from v0.1 (with the reason)

| Item | Why deferred | What to keep compatible |
|---|---|---|
| Claim-to-claim probability propagation | Needs cycle handling and a real dependency model | `claim_edges` already stored with validity windows |
| Inferences and premises tables | No P0 flow creates them | `CREATE_INFERENCE` reserved action name |
| Tests / test–hypothesis effects | Only meaningful with questions and hypotheses live | — |
| Entity resolution | Not needed for the demo | `qualifiers` JSONB can hold entity refs |
| Context/omission status (`CHERRY_PICKED`, …) | Must be backed by explicit claims; easy to abuse as an LLM label | model as claims + links later |
| Forecast ex-ante / ex-post scores | Requires resolution workflow | `FORECAST` type exists, unscored |
| Causal identification metadata | Requires a causal model | `CAUSAL` scored with lower prior + label |
| Diminishing-returns aggregation | Strongest-only is simpler and conservative | `independence_strategy` config key |
| Contributor-reliability weighting in scores | Couples scores to unrelated audit history | a future model version may add it explicitly |
| pgvector | pg_trgm suffices for the seed | similarity is never evidence weight |
| Task marketplace, cost accounting | Advisory only; not needed to prove the substrate | `task_type_cost` config |
| Net-value scheduling (expected epistemic value − expected audit cost − expected correction cost) | Needs measured audit multipliers first (07 First Experiments #3) | P0 already keeps what it needs: per-contribution software metadata, task type, audit results, `audits.effort_seconds`, invalidation history |
| Verification-process diversity constraints | P1 (04 §3.1) | `software` metadata on every contribution |
| `DETAILED` summaries | Hard to validate citation coverage at length | sentence-level citation validator |
| `prior_class` for extraordinary claims | Gives whoever sets it real power over outcomes; needs a governance decision first (constitution Art. XXIV; amendment P-4) | auditable claim qualifier; visible in trace |
| Person-to-person disagreement localization | Needs personal lenses (P1) | `/compare` diff format |
| Browser-side self-custody keys | Server custody is labeled and adequate for a POC | `custody` column |

---

## 2. Standards Compatibility

P1: documented export mappings — contributions → W3C PROV activities/agents/entities; claim + counted evidence + provenance → nanopublication-style assertion/provenance/publication-info graphs. P2+: JSON-LD, schema.org, DOI/OpenAlex identifiers, legal citation identifiers. The internal model never depends on any of them.

**ClaimReview needs care.** Its `reviewRating` expects a verdict ("False", "Mostly true"), which sits badly with the constitution's model-conditional, no-verdict display rules (Art. VII, XIX; 06 §4). If ClaimReview output is added, it must be opt-in per record by a named human publisher, carry the assessment state and model in `alternateName` text rather than a truth rating, and link to the full trace.

## 3. Scholarly Corpus Integration

OpenAlex, Crossref, PubMed, arXiv, Semantic Scholar, Internet Archive (where licensing permits), public-domain primary corpora. Store references and provenance; do not redistribute restricted full text. Server-side fetching needs an allow-listed, sandboxed fetcher (SSRF).

## 4. Specialized Scoring Models

`historical-source`, `scientific-replication`, `legal-preponderance-US`, `legal-beyond-reasonable-doubt`, `financial-assumption`, `forecast-calibration`, `textual-criticism`. All read the same log. Communities may publish competing models; the graph does not fork.

## 5. Calibration

Use resolved claims and forecasts to calibrate source-type weights, evidence weights, and priors; replace hand-tuned values where data supports it. Each calibrated set is a new model version.

## 6. Mirroring and Federation

Independent nodes mirror the log (`GET /log`), verify the chain, host source caches, run alternative models, and maintain private overlays. External anchoring of chain heads. The graph should not depend forever on one operator.

## 7. Privacy-Preserving Identity

Verifiable credentials, proof of unique personhood, institutional attestations, selective disclosure, zero-knowledge membership proofs — to improve Sybil resistance without public real names.

## 8. Higher-Order Argument Graph

Explicit logical forms, defeasible reasoning, argument schemes, burdens of proof, argument attacks, counterfactuals.

## 9. Automated Independence Inference

Agents propose independence clusters from citation graphs, text similarity, timing, press-release origin, shared datasets, and common witnesses. Proposals remain auditable contributions.

## 10. Omission and Framing Analysis

Denominator changes, window selection, baseline selection, cherry-picked subgroups, survivorship bias, missing comparison classes — each represented as explicit claims and evidence, never as a bare label.

## 11. Research Scheduler and Local-Agent Donations

Priority using expected discriminative value between hypotheses. Opt-in donations: "$1/day, verification + opposing search, local model, idle hours." The server issues compact tasks; agents return signed results.

## 12. Domain Interfaces on the Same Ledger

Speech analyzer · sermon analyzer · business-plan dependency reviewer · legal evidence mapper · scientific claim tracker (replication, retractions, effect sizes) · AI-answer auditor.

## 13. Epistemic Diff

```text
C812  0.81 -> 0.62   (seq 40211 -> 40987, model unchanged)
  + new contradicting dataset E994 (group G77)
  - E412 reassigned to G12 (dependent on E388); suppressed
```

The P0 snapshot design (validity windows + seq) already makes this a query, not a new subsystem.

## 14. Long-Term Vision

A persistent, inspectable record of what was asserted, what evidence exists, where it came from, who interpreted it, how reliable that interpreter has been, what contradicts it, what depends on it, how current assessments were computed, what remains unknown, and what observation would matter next.

> Organize reasons for belief the way the web organized documents.

## 15. Governance Questions (open)

Not needed for the POC, but they will arrive quickly: data license for the log (CC0 vs CC-BY), who holds the system key, who appoints and removes moderators, how scoring-model releases and constitutional amendments are approved, and whether proposed amendments P-1 to P-4 (`CONSTITUTION-AMENDMENTS.md`) are adopted. Article XII's capture resistance ultimately depends on these answers more than on any code.
