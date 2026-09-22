# 03 — Scoring and Uncertainty

## 1. Goal

> **Determinism is not objectivity.** The scorer makes reasoning *reproducible*. It does not make its inputs objective. Relevance labels, interpretive-step counts, independence groupings, claim wording, and observation types are judgment calls. The system's answer to that is not to hide them but to make every such judgment explicit, attributed, challengeable, versioned, auditable, and separate from the raw evidence it describes.

Produce **deterministic, versioned assessments**, not opaque LLM confidence. Every result is conditional on:

```text
snapshot seq  +  scoring model name@version  (config_hash, code_hash)
```

A probability is never displayed without both references visible.

---

## 2. Outputs

For every claim, `Scoring::Calculate` returns:

| Field | Type | Meaning |
|---|---|---|
| `assessment_state` | enum (§4 Step 5) | The primary, human-facing result |
| `probability` | decimal(4dp) or `null` | Posterior under this model; `null` unless the state is a scored state |
| `review_coverage` | decimal(2dp) 0..1 | Fraction of the review checklist completed (§8) |
| `review_checklist` | object | Which checklist items are satisfied, each with the contribution IDs that satisfy it |
| `stability` | `HIGH` / `MEDIUM` / `LOW` / `null` | Sensitivity to model variants (§9) |
| `support_groups` | int | Independent groups with counted support |
| `contradict_groups` | int | Independent groups with counted contradiction |
| `independence_unreviewed` | int | Counted items with no independence group |
| `contested` | bool | Both support and contradiction groups > 0 |
| `provisional` | bool | Any counted link comes from a contribution that has not yet been audited `CONFIRMED` |
| `not_applicable_reason` | enum or `null` | Why no assessment was made (constitution Art. VI; mapping in 13) |
| `model_dependent` | bool | Claim type is in `config.model_dependent_types` |
| `trace` | object (§10) | Everything needed to recompute the above by hand |

These names are canonical. No synonyms anywhere in the codebase or UI.

---

## 3. Warning About Probability

A deterministic score is not an objective frequency. Priors and weights in v0.1 are hand-set and uncalibrated. The UI says:

> 0.86 under `ledger-default@0.1.0` at snapshot 212

never:

> This claim is 86% true.

---

## 4. The v0.1 Algorithm (`ledger-default@0.1.0`)

The authoritative weights live in `scoring-config-v0.1.json`. The algorithm below is normative; implement it exactly.

### Step 0 — Applicability

If `claim.truth_evaluable == false` **or** `claim.claim_type ∉ config.scored_types` → return `assessment_state = NOT_APPLICABLE`, `probability = null`, `stability = null`, and `not_applicable_reason` = the claim's `not_evaluable_reason`, or `NOT_SCORED_BY_MODEL` when the claim is evaluable but this model does not score its type. Still compute `review_coverage` and list linked evidence in the trace.

### Step 1 — Select counted links

Links for the claim that are **counted at snapshot S** (02 §1.3), whose evidence item and source location are active at S, and whose evidence item is not `QUARANTINED`.

Contributor reputation is **not** an input. (The previous draft multiplied weights by contributor reliability. That made scores depend on audit history of unrelated work, let a Beta prior of 0.5 silently halve every new contributor's evidence, and trusted agent self-reported confidence. Reputation now drives audit policy only; see 05.)

### Step 2 — Weight each link

```text
relevance      = config.relevance_weight[link.relevance_strength]
observation    = config.observation_weight[evidence.observation_type]
interpretation = max(0, 1 - config.interpretive_step_penalty * link.interpretive_steps)
authenticity   = config.authenticity_factor[evidence.assessment.authenticity]   # default UNVERIFIED
extraction     = config.extraction_factor[evidence.assessment.extraction]       # default UNVERIFIED

magnitude = round6(relevance * observation * interpretation * authenticity * extraction)
sign      = +1 for SUPPORT, -1 for CONTRADICT, 0 for QUALIFY and NEUTRAL
```

`round6` = round half to even at 6 decimal places, using `BigDecimal` in Ruby. All config lookups must be exhaustive: a missing key is a config validation error at model release, not a runtime default.

`QUALIFY` and `NEUTRAL` links appear in the trace with `effective_weight: 0` and `reason: "non_directional"`.

### Step 3 — Independence (strongest-only)

```text
group_key = evidence.independence_group_id  ||  "solo:" + evidence.id
```

Within each `(group_key, sign)` pair, keep the single link with the largest `magnitude`; ties broken by lowest `evidence_item.id`, then lowest `link.id`. All others get `effective_weight: 0`, `reason: "dependent_strongest_only"`, and name the kept link.

Grouping is per direction: a group can contribute one support weight *and* one contradiction weight.

If every kept link has `magnitude == 0` → `assessment_state = INSUFFICIENT_EVIDENCE`, `probability = null`.

### Step 4 — Combine

```text
prior_log_odds = round6(ln(p0 / (1 - p0)))       where p0 = config.prior[claim_type]
evidence_sum   = Σ sign * magnitude over kept links, summed in ascending link.id order, round6
posterior      = prior_log_odds + evidence_sum
probability    = round4(1 / (1 + exp(-posterior)))
```

### Step 5 — Assessment state

Using `config.state_thresholds` (v0.1 values shown):

| Condition (first match wins) | State |
|---|---|
| Step 0 triggered | `NOT_APPLICABLE` |
| Step 3 empty | `INSUFFICIENT_EVIDENCE` |
| probability ≥ 0.80 **and** support_groups ≥ 1 | `SUPPORTED` |
| probability ≥ 0.60 **and** support_groups ≥ 1 | `LEANS_SUPPORTED` |
| probability ≤ 0.20 **and** contradict_groups ≥ 1 | `CONTRADICTED` |
| probability ≤ 0.40 **and** contradict_groups ≥ 1 | `LEANS_CONTRADICTED` |
| otherwise | `UNRESOLVED` |

**Directional states require matching evidence (v4 fix).** With a non-0.50 prior, the v3 rule could label a claim "leans contradicted" when every counted link *supports* it (the public demo's `C6`: prior 0.35 plus weak support = 0.3792). A state that says the evidence points somewhere must be backed by evidence pointing there. The prior alone can never produce a directional state.

`contested` and `provisional` are orthogonal flags displayed alongside the state.

Why `INSUFFICIENT_EVIDENCE` is not "0.50": the previous draft left an evidence-free claim at its prior, so "ancient people encountered AI" with no support would have displayed as a coin flip. Showing the prior as if it were an assessment violates principle 8.

---

## 5. Priors (v0.1)

All scored types use `p0 = 0.50` except `CAUSAL = 0.35` (a nudge against treating correlation as causation). These values are not philosophically privileged; v0.1 aims at reproducibility, not calibration. Calibration is deferred (09).

`scored_types` in v0.1: `OBSERVATIONAL, QUANTITATIVE, HISTORICAL, TEXTUAL, COMPARATIVE, DEFINITIONAL, ATTRIBUTED_BELIEF, CAUSAL, INTERPRETIVE`.

`INTERPRETIVE` and `CAUSAL` results are always shown with the label "model-dependent" and have stability capped at `LOW` (§9).

---

## 6. Weights (v0.1, illustrative but authoritative for this version)

```text
relevance_weight:     DIRECT 2.0 | STRONG 1.2 | MODERATE 0.6 | WEAK 0.2 | CONTEXT_ONLY 0.0
observation_weight:   MEASUREMENT 1.0 | DATASET_RESULT 0.9 | DIRECT_TEXT 0.9 | ARCHAEOLOGICAL 0.9
                      | CALCULATION 0.7 | EYEWITNESS 0.4 | EXPERT_ANALYSIS 0.3 | HEARSAY 0.1
                      | OTHER 0.1 | MODEL_OUTPUT 0.0
interpretive_step_penalty: 0.15
authenticity_factor:  VERIFIED 1.0 | UNVERIFIED 1.0 | DOUBTFUL 0.3
extraction_factor:    VERIFIED 1.0 | UNVERIFIED 1.0
```

`UNVERIFIED` factors are 1.0 in v0.1 on purpose: the `provisional` flag, not a hidden discount, communicates that work is unaudited. `MODEL_OUTPUT` = 0.0 means an AI assertion never counts as evidence on its own.

---

## 7. What v0.1 Deliberately Does Not Do

- No claim-to-claim propagation through `claim_edges`.
- No diminishing-returns aggregation within groups (strongest-only only).
- No contributor-reliability weighting.
- No separate forecast ex-ante/ex-post scores (FORECAST is not scored).
- No causal-identification metadata (CAUSAL is scored with a lower prior and a label only).

Each is a candidate for a later model version, not a patch to v0.1.

---

## 7a. Rules a later model declares

A model version may declare a rule that v0.1 does not have. Every such rule is **read from
the config**, so a model that does not declare it scores exactly as it always did and every
trace it produced stays reproducible byte for byte (Invariant 4). A declared rule also adds
its own field to each link in the trace, and only when declared, so the trace of an older
model is unchanged.

| Key | Declared by | What it does |
|---|---|---|
| `provenance_factor` | 0.2.0 | Evidence drawn from an origin the claim was extracted from shows the quotation is faithful, not that the speaker was right. `SELF` multiplies the magnitude by 0; `INDEPENDENT` by 1. Trace: `provenance`. |
| `independence_fallback: "origin"` | 0.2.0 | Ungrouped evidence falls back to a group keyed by origin **and passage**, so one URL recorded as two sources cannot count twice, while two different passages of one document stay distinct. |
| `edition_rule: "named_edition_only"` | 0.3.0 | A claim may name the edition of a source it is about, in `qualifiers.source_edition` (02 §3.3). A counted link whose evidence comes from a **different version in the same lineage** — by `previous_version_id` or a shared `lineage_key` — weighs nothing. The link is not removed and not hidden: it appears in the trace with `effective_weight` 0 and `reason: "other_edition"`. Trace: `edition`. |

**Why 0.3.0 exists.** A living web page is not one document. An announcement published on one
day, revised two days later and read ten days after that, produces evidence about the revised
text; counted against a claim about what it said when published, it contradicts something it
was never about. That happened on this project's own node, and the claim read `CONTRADICTED`
at 0.1419 on the strength of two readings of a page that had been edited, against one
contemporaneous account that supported it.

The rule is deliberately narrow. It fires only when a claim **says** which edition it means,
so it can never quietly discount evidence nobody asked it to; and it does nothing for a claim
where only the later version was ever recorded, because there is then no lineage to compare.
Whether a reading later than the claim's subject should be discounted on the date alone was
considered and rejected: a filing or a PDF read last week still says what it said, and a
scorer acting on a retrieval date would be discounting good evidence to catch bad.

`reference/reference_scorer.py` carries the case under "Editions (Stage 41)" and must print
`ALL PASS`.

---

## 8. Review Coverage

The previous draft defined coverage as "reviewed evidence surface / estimated evidence surface" — a quantity nobody can estimate — and listed components with no data source. v0.1 replaces it with a **checklist derived entirely from the log**, so it is deterministic and never invented.

| Item | Satisfied at S when… |
|---|---|
| `primary_source_reviewed` | a counted link (any direction) exists from evidence whose source is `PRIMARY_TEXT`, `DATASET`, `MEASUREMENT`, or `LEGAL_DOCUMENT` |
| `opposing_search_done` | an accepted `TASK_RESULT` for an `OPPOSING_EVIDENCE_SEARCH` task targeting this claim exists (even if it found nothing) |
| `independence_reviewed` | at least one item is counted and every counted evidence item has an independence group, **or** an accepted `SOURCE_INDEPENDENCE_CHECK` result targets this claim |
| `qualifiers_reviewed` | an accepted `QUALIFIER_CHECK` result targets this claim |

```text
review_coverage = satisfied_items / len(config.review_checklist)      (rounded to 2dp)
```

**The denominator comes from the model** (v4 fix). v3 divided by 4 while `QUALIFIER_CHECK` was a P1 task, so no P0 claim could ever exceed 0.75. v4 fixes this in two ways: the checklist is declared per model, and a model release is **rejected** if any declared check cannot be satisfied by a task type available in the same tier. `QUALIFIER_CHECK` is promoted to P0 because the public demo (08) depends on discovering an omitted qualifier, so both P0 models declare all four checks.

UI label: "Review checks: 2 of 4." Never "42% of evidence reviewed," and never "coverage: high" — a completed checklist means the listed checks were done, not that most existing evidence was found (constitution Art. VIII).

---

## 9. Stability

Recompute `evidence_sum` under two variants defined in config:

```text
conservative: every magnitude × 0.7
permissive:   every magnitude × 1.3
spread = max(p_default, p_conservative, p_permissive) − min(p_default, p_conservative, p_permissive)
```

| spread | stability |
|---|---|
| ≤ 0.10 | `HIGH` |
| ≤ 0.25 | `MEDIUM` |
| > 0.25 | `LOW` |

Caps (applied after): fewer than 2 total independent groups (support + contradict) → at most `MEDIUM`. Type `INTERPRETIVE` or `CAUSAL` → `LOW`.

Weak evidence near 0.5 produces a small spread; the group-count cap prevents that from reading as "highly stable."

---

## 10. Score Trace

Canonical JSON, hashed into `trace_hash`. Example (public demo claim C2 at checkpoint S4; values match 08 §8):

```json
{
  "claim": "C2",
  "snapshot_seq": 31,
  "model": "ledger-default@0.1.0",
  "config_hash": "sha256:…",
  "claim_type": "QUANTITATIVE",
  "prior": "0.50",
  "prior_log_odds": "0.000000",
  "links": [
    {"link": "L3", "evidence": "E1", "direction": "SUPPORT", "group": "G1",
     "relevance": "STRONG", "observation": "DATASET_RESULT", "interpretive_steps": 1,
     "magnitude": "0.918000", "effective_weight": "0.918000"},
    {"link": "L4", "evidence": "E2", "direction": "SUPPORT", "group": "G1",
     "relevance": "MODERATE", "observation": "DIRECT_TEXT", "interpretive_steps": 1,
     "magnitude": "0.459000", "effective_weight": "0.000000",
     "reason": "dependent_strongest_only", "kept": "L3"},
    {"link": "L5", "evidence": "E3", "direction": "SUPPORT", "group": "G1",
     "magnitude": "0.459000", "effective_weight": "0.000000",
     "reason": "dependent_strongest_only", "kept": "L3"},
    {"link": "L6", "evidence": "E4", "direction": "SUPPORT", "group": "G1",
     "magnitude": "0.459000", "effective_weight": "0.000000",
     "reason": "dependent_strongest_only", "kept": "L3"},
    {"link": "L7", "evidence": "E5", "direction": "SUPPORT", "group": "G1",
     "magnitude": "0.459000", "effective_weight": "0.000000",
     "reason": "dependent_strongest_only", "kept": "L3"}
  ],
  "evidence_sum": "0.918000",
  "posterior_log_odds": "0.918000",
  "probability": "0.7146",
  "rounding_boundary": false,
  "variants": {"conservative": "0.6553", "permissive": "0.7673", "spread": "0.1120"},
  "stability": "MEDIUM",
  "assessment_state": "LEANS_SUPPORTED",
  "support_groups": 1, "contradict_groups": 0, "independence_unreviewed": 0,
  "contested": false, "provisional": false, "model_dependent": false,
  "not_applicable_reason": null,
  "review_checklist": {
    "primary_source_reviewed": {"ok": true,  "by": ["L3"]},
    "opposing_search_done":    {"ok": false, "by": []},
    "independence_reviewed":   {"ok": true,  "by": ["T3"]},
    "qualifiers_reviewed":     {"ok": false, "by": []}
  },
  "review_coverage": "0.50"
}
```

(L5–L7 are abbreviated here; real traces list every field for every link.)

All decimals are serialized as strings with fixed places.

**What determinism is promised (narrowed in v4).**

- *Same implementation, same seq, same model* → byte-identical canonical trace. This is tested.
- *Different implementations* (Ruby, the Python reference, a future Go service) → must produce identical canonical traces on the golden fixtures and any shared regression corpus. Weights are exact decimals; only the log-odds prior and the sigmoid use transcendental functions, and their results are rounded (6 and 4 places).
- The spec does **not** claim that `exp`/`ln` are bit-identical across languages or libm builds. To keep rounding differences from flipping outputs silently, the trace records `rounding_boundary: true` when an unrounded value is within `config.rounding.boundary_guard` (1e-6) of a rounding boundary; cross-implementation comparisons treat flagged values as needing review rather than as failures.

---

## 11. Non-Scored Claims

`NORMATIVE`, `RHETORICAL`, `METAPHYSICAL` (and any non-evaluable claim) return `NOT_APPLICABLE`. They may still have linked premises and textual/historical support, which the claim page displays. The system assesses premises without pretending to settle non-empirical conclusions.

---

## 12. Extraordinary Claims (known gap)

Constitution Article XXIV asks that extraordinary conclusions require correspondingly strong, well-audited evidence. v0.1 delivers the *well-audited* half (`provisional`, high-impact audit policy in 05 §10) but uses flat priors, so it does not deliver the *correspondingly strong* half. This is recorded as a gap in 13 and as proposed amendment P-4. Do not patch it by hand-editing priors for particular claims; any fix must be an auditable, versioned model feature.

## 13. Multiple Models (P0)

Constitution Article XII requires the ability to run alternative scoring models over the same evidence. P0 therefore releases two models that share the §4 code and differ only in config:

| Model | Config | Stance |
|---|---|---|
| `ledger-default@0.1.0` | `scoring-config-v0.1.json` | As described above |
| `ledger-strict@0.1.0` | `scoring-config-strict-v0.1.json` | Scores only directly observable types (drops `INTERPRETIVE`, `CAUSAL`); `EXPERT_ANALYSIS` weight 0.0 |

`ledger-default` is the display default. Every score endpoint accepts `?model=`, and `GET /claims/:id/compare?models=a,b` returns both traces plus a diff: the links whose effective weights differ, the config keys responsible, and any state change. This is the P0 form of Article XVI's "localize the disagreement."

Both models appear in golden tests (08 §8; `examples/watchers` §7). Adding a model must never change another model's results.

## 14. Task Priority Heuristic

Used for the task board, not for scores:

```text
uncertainty     = 1 - |2p - 1|         (use 1.0 when probability is null)
impact          = 1 + ln(1 + downstream_count)      # active claim_edges pointing out of the claim
coverage_gap    = 1 - review_coverage
priority        = round4(uncertainty * impact * (0.5 + coverage_gap) / task_type_cost)
```

`task_type_cost` is a per-type constant in config (1 for verification, 3 for search). This is a heuristic, not expected information gain, and is labeled as such.
