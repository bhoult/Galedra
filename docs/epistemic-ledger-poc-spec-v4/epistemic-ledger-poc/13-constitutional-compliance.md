# 13 — Constitutional Compliance Map

How the POC spec realizes each Article of `12-constitution.md`. Update this file whenever a spec change touches an Article. A row marked **Gap** is a known, accepted shortfall — not permission to drift further.

Status: **P0** implemented in POC · **P1** planned after P0 · **Partial** P0 implements part · **Gap** not addressed in v0.1.

| Article | Where realized | Status | Notes |
|---|---|---|---|
| I Claims are not truth | 01 §2, 03 §3, 06 §4 | P0 | UI leads with model-conditional states; no "true/false" labels |
| II Evidence traceable | 02 §3.2–3.3, 04 §6 steps 6–8 | P0 | Exact locator + excerpt hash + creating contribution. Evidence from agent-supplied external sources is stored `retrieval_pending` until content is imported |
| III Evidence ≠ interpretation | 02 (evidence item vs. link vs. claim), `TEXTUAL` type, `interpretive_steps` | P0 | Inferences as explicit objects are deferred (09 §1) |
| IV Atomicity | 02 §4, 04 §4.3 | P0 | Heuristic warning + human confirmation. Claim identity: no text uniqueness; explicit, reversible merges (02 §3.3) |
| V Contradiction preserved | 02 `evidence_claim_links`, `claim_edges` (incl. `PREDICTS`, `EXPLAINS`, `ALTERNATIVE_TO`) | P0 | Edges stored and displayed; no propagation in v0.1 |
| VI Unknown is valid | 03 §4 states; mapping below | Partial | See mapping below; underdetermined/indistinguishable are hypothesis-level (P1) |
| VII Model-conditional probabilities | 03 §1, §10; 06 §4 | P0 | Trace names snapshot, model, config/code hashes, counted and suppressed evidence. v4: numbers sit behind Show calculation; directional states require matching evidence, so a prior can't masquerade as a finding |
| VIII Coverage ≠ confidence | 03 §8, 06 §4 rule 5 | Partial | Coverage is a review **checklist** (now fully executable in P0), an honest proxy; it cannot measure "most of the evidence that may exist," so it is shown only as "N of M checks", never as low/medium/high |
| IX Independence | 02 groups, 03 Step 3, 08 S1→S4 | P0 | Extended in v4 to verification processes (04 §3.1; diversity constraints P1). Automated independence inference deferred |
| X Reputation ≠ authority | 05 §6–8 | P0 | Stronger than required: reputation is not a scoring input in v0.1 |
| XI Identity ≠ evidence | 05 §2–3, `identity_tier` never affects scores | P0 | Pseudonymous reputation supported |
| XII Resist capture | 02 §1.2 chain, 05 §5, §9 deterministic sampling, §13 visible moderation, 03 §13 multiple models | P0 | Two scoring models ship in P0 so "alternative models over the same evidence" is exercised, not just promised. Governance of the system key is open (09 §15) |
| XIII Corrections keep history | 02 §1.3, §5; snapshot views | P0 | Legal removal via visible `TAKEDOWN`; replay reports `CHAIN_VERIFIED_WITH_REDACTIONS` rather than claiming completeness — see proposed amendment P-2 |
| XIV Contributors, not oracles | 03 §6 `MODEL_OUTPUT` = 0, 04 §6, 04 §8 no self-certification | P0 | Humans are audited by the same rules as agents |
| XV Shared vs. personal belief | 02 §3.6a reserved, 06 §4 rule 9 | P1 | P0 guarantees nothing personal writes to the shared log; personal lenses ship in P1 |
| XVI Localized disagreement | 06 `/compare` (model vs. model) | Partial | P0 shows *which links and config keys* explain a difference between two models. Localizing disagreement between people needs lenses (P1) |
| XVII Normative ≠ empirical | 01 §4, 03 §11 | P0 | `NOT_APPLICABLE` with a stated reason |
| XVIII Political neutrality | 06 §6 | P1 view, rule P0 | No speaker/party scores anywhere; same pipeline for all claims |
| XIX Transparency over persuasion | 06 §4, model selector | P0 | Users may choose any released model and see every trace |
| XX Evidence endures | 02 §1 (log is source of record), 03 §13 | P0 | Old model versions stay loadable |
| XXI Cumulative research | 04 | P0 | Small leased tasks; results become durable ops |
| XXII Reveal weaknesses | 06 §5 Weaknesses page, 01 §6 "what would most change this" | Partial | Suspicious contribution-cluster detection is P1 (05 §16) |
| XXIII Re-examination | Opposing-search tasks, `RE_AUDIT`, supersession | P0 | Challenges only move scores through evidence links; assertions alone do nothing |
| XXIV Efficient skepticism | 03 states distinguish `INSUFFICIENT_EVIDENCE` from `CONTRADICTED`; `support_groups`/`contradict_groups` shown separately | Partial / **Gap** | "Correspondingly strong evidence" for extraordinary claims is not modeled in v0.1 (flat priors). See proposed amendment P-4 |
| XXV Amendments explicit | `CONSTITUTION-AMENDMENTS.md`, `AMEND_CONSTITUTION` action, `constitution_hash` in `/meta` | P0 | |
| Constitutional Test | 10 "Constitutional Test" | P0 | Answers recorded in `IMPLEMENTATION.md` |

---

## Article VI mapping (states the constitution names → spec representation)

| Constitutional state | Spec representation | Tier |
|---|---|---|
| unknown / insufficient evidence | `INSUFFICIENT_EVIDENCE` | P0 |
| unresolved | `UNRESOLVED` (and `contested` flag when evidence points both ways) | P0 |
| dependent on disputed assumptions | `model_dependent` flag; differing results across models (`/compare`) | P0 |
| untestable with current methods | `NOT_APPLICABLE` + `not_evaluable_reason: UNTESTABLE_CURRENT_METHODS` | P0 |
| non-empirical (normative, metaphysical, rhetorical) | `NOT_APPLICABLE` + reason | P0 |
| not scored by this model | `NOT_APPLICABLE` + reason `NOT_SCORED_BY_MODEL` | P0 |
| underdetermined | question-level: no hypothesis has counted discriminating evidence | P1 |
| observationally indistinguishable from alternatives | question-level: hypotheses share all counted evidence with identical directions | P1 |

---

## Constitutional Test applied to this spec revision

| # | Question | Answer for v3/v4 |
|---|---|---|
| 1 | Traceability | Increased: excerpt hashes, `retrieval_pending`, reasons on non-evaluable claims |
| 2 | Disagreement inspectable | Increased: second model + `/compare` |
| 3 | Hidden authority | Reduced: moderation and takedowns are public stubs; audit sampling is recomputable. Remaining: system-key holder (open governance question) |
| 4 | Reputation substitutes for evidence | No: reputation is not a scoring input |
| 5 | Uncertainty preserved | Yes: null probabilities for non-assessments |
| 6 | Reproducible | Yes: replay and golden tests for both models and both demos; honest exceptions for legal redaction; cross-language claims narrowed to canonical outputs |
| 7 | Opponent can challenge | Yes: same contribution path, opposing-search tasks, re-audits, alternative models |
| 8 | History reconstructable | Yes, including for quarantined and taken-down items (as stubs) |
| 9 | Shared vs. personal kept separate | Yes in P0 by absence; enforced structurally in P1 (separate table, never in log) |
| 10 | Acceptable in opponents' hands | Main residual risk is moderation power; mitigated by visibility and appeals, not eliminated |
