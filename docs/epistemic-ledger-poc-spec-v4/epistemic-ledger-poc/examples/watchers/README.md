# Watchers Stress Test (internal)

> **Internal stress test, not the public demo.** The public/default demo is `08-seeded-example.md`. This example stays because it exercises primary texts, interpretation, an unusual hypothesis, unsupported extrapolation, and a model disagreement (`C3`) in a small space. Load it with `bin/demo --example watchers`. Its golden values are checked by `reference/reference_scorer.py` and must pass in CI alongside the public demo.

## 1. Purpose

A small textual example that exercises every P0 behavior and produces **exact expected values** for tests. It is not intended to support any theological or historical conclusion.

All source text is developer-written paraphrase; no modern copyrighted translation is used.

Handles (`C1`, `E1`, `G1`, `L1`…) are display handles. Real IDs are UUIDv7.

---

## 2. Contributors

| Handle | Kind | Principal | Custody | Role |
|---|---|---|---|---|
| `System` | SYSTEM | — | SYSTEM | accepts, signs packets |
| `Curator` | HUMAN | self | SERVER | creates seed sources, claims, evidence |
| `Reviewer` | HUMAN, tier ESTABLISHED | self | SERVER | audits (different principal from everyone else) |
| `Alice` | HUMAN | self | SELF | principal for `AgentVerifier` |
| `AgentVerifier` | AGENT | Alice | SELF | runs verification and search tasks |
| `Mallory` | HUMAN | self | SELF | principal for `AgentBad` |
| `AgentBad` | AGENT | Mallory | SELF | submits a false verification |

Domain for all tasks: `ancient_near_east`.

---

## 3. Sources and Locations

| Handle | Type | Content (stored, hashed) |
|---|---|---|
| `SA` | PRIMARY_TEXT | "In the narrative, Azazel teaches humans the making of swords, knives, shields, and related metal implements." |
| `SB` | PRIMARY_TEXT | "A second retelling says Azazel showed people how to work metals and forge weapons of war." |
| `SC` | SECONDARY_TEXT | "An explainer article restates the second retelling: Azazel taught the forging of weapons." |
| `SD` | SECONDARY_TEXT | "A mock commentary: the passage can be read as a critique of transmitting specialized technical knowledge." |

Each has one `CHAR_RANGE` location covering its whole text: `SLA`, `SLB`, `SLC`, `SLD`.

`SC` is deliberately derivative of `SB` (it says so), which is what the independence check discovers.

---

## 4. Claims

| Handle | Text | Type |
|---|---|---|
| `C1` | The seeded Watcher narrative attributes metalworking instruction to Azazel. | TEXTUAL |
| `C2` | The seeded Watcher narrative associates Azazel's instruction with weapon manufacture. | TEXTUAL |
| `C3` | The narrative portrays specialized knowledge transmission as contributing to social corruption. | INTERPRETIVE |
| `C4` | The seeded narrative describes the Watchers as artificial or technological beings. | TEXTUAL |
| `C5` | The source explicitly identifies Azazel as a machine. | TEXTUAL |
| `C6` | Teaching people to make weapons is morally wrong. | NORMATIVE |

Changes from the previous draft: `C4` was "the narrative is evidence that ancient people encountered artificial intelligence," typed "HISTORICAL / INTERPRETIVE." A claim may have only one type, and that sentence bundles a textual claim with a historical inference. The textual part is `C4`; the historical inference is hypothesis `H3` (P1, §9). `C6` is added to exercise `NOT_APPLICABLE`.

---

## 5. Evidence Items and Groups

| Handle | Location | Observation | Statement | Group |
|---|---|---|---|---|
| `E1` | SLA | DIRECT_TEXT | Azazel teaches the making of swords, knives, shields, and metal implements. | `G1` |
| `E2` | SLD | EXPERT_ANALYSIS | Commentary reads the passage as a critique of transmitting technical knowledge. | none |
| `E3` | SLA | DIRECT_TEXT | The excerpt contains no description of the Watchers as artificial or technological. | `G1` |
| `E4` | SLB | DIRECT_TEXT | A second retelling says Azazel showed people how to work metals and forge weapons. | none → `G2` at S5 |
| `E5` | SLC | DIRECT_TEXT | An explainer restates that Azazel taught weapon forging. | none → `G2` at S5 |

`G1` = SAME_PRIMARY_TEXT (source SA). `G2` = SAME_PRIMARY_TEXT (lineage of SB; SC derives from it).

---

## 6. Script (`db/seeds/examples/watchers.rb`, driven by `bin/demo --example watchers`)

Every step is a contribution through the real write path. Checkpoints are pinned snapshots with labels.

```text
 1. System key; Curator, Reviewer, Alice, Mallory keys; Alice→AgentVerifier and Mallory→AgentBad delegations
 2. Curator: SA, SD sources + locations
 3. Curator: C1, C2, C3, C4, C6
 4. Curator: E1, E2, E3; G1; assign E1, E3 → G1
 5. Curator: L1 E1 SUPPORT C1 DIRECT (0 steps)
            L3 E2 SUPPORT C3 MODERATE (1 step)
            L4 E3 CONTRADICT C4 MODERATE (0 steps)
    (MODERATE, not STRONG: SA is a fragment of the narrative, so silence in it is only moderate evidence.)
 6. Reviewer: AUDIT CONFIRMED on L1, L3, L4 contributions
 7. Task T1 EVIDENCE_VERIFICATION (C2, SLA) → AgentVerifier:
        CONFIRMED, op L2 E1 SUPPORT C2 DIRECT
 8. Task T2 OPPOSING_EVIDENCE_SEARCH (C4, direction SUPPORT, scope: seeded sources) → AgentVerifier:
        NONE_FOUND, no ops
 ── checkpoint S1 "baseline"
 9. Curator: C5 (as if extracted from a fringe article); task T3 EVIDENCE_VERIFICATION (C5, SLA)
10. T3 → AgentBad: CONFIRMED, op L5 E1 SUPPORT C5 DIRECT
    (Passes validation: E1 and SLA are real. It is simply false.)
 ── checkpoint S2 "poisoned"
11. Audit sampling: AgentBad has n=0 and mean 0.5 → probability min(1, 0.1×5×2×1×1) = 1.0 → sampled
12. Reviewer: AUDIT SUBSTANTIVE_ERROR on T3 result ("No such statement appears in the cited passage.")
    → System: INVALIDATE; L5 gets invalidated_seq
13. Reviewer: AUDIT CONFIRMED on T1 result
 ── checkpoint S3 "audited"
14. Curator: SB, SC + locations; E4, E5 (no group);
            L6 E4 SUPPORT C1 STRONG; L7 E5 SUPPORT C1 MODERATE
15. Reviewer: AUDIT CONFIRMED on L6, L7 contributions
 ── checkpoint S4 "ungrouped"
16. Task T4 SOURCE_INDEPENDENCE_CHECK (C1) → AgentVerifier:
        GROUPED, ops: create G2; assign E4, E5 → G2
17. Reviewer: AUDIT CONFIRMED on T4 result
 ── checkpoint S5 "final"
18. Print golden tables (both models) with PASS/FAIL, the `/compare` diff for C3, reputation table, snapshot digests, and URLs
19. Print replay check: truncate projections, replay, compare S1–S5 digests
```

---

## 7. Golden Values (`ledger-default@0.1.0`)

`p` = probability string; `cov` = review_coverage; `sg`/`cg` = support/contradict groups; `unrev` = independence_unreviewed.

| Chk | Claim | State | p | Stability | cov | sg | cg | unrev | Flags |
|---|---|---|---|---|---|---|---|---|---|
| S1 | C1 | SUPPORTED | 0.8581 | MEDIUM | 0.50 | 1 | 0 | 0 | — |
| S1 | C2 | SUPPORTED | 0.8581 | MEDIUM | 0.50 | 1 | 0 | 0 | provisional |
| S1 | C3 | UNRESOLVED | 0.5382 | LOW | 0.00 | 1 | 0 | 1 | model-dependent |
| S1 | C4 | LEANS_CONTRADICTED | 0.3682 | MEDIUM | 0.75 | 0 | 1 | 0 | — |
| S1 | C6 | NOT_APPLICABLE | null | null | 0.00 | 0 | 0 | 0 | — |
| S2 | C5 | SUPPORTED | 0.8581 | MEDIUM | 0.50 | 1 | 0 | 0 | provisional |
| S3 | C2 | SUPPORTED | 0.8581 | MEDIUM | 0.50 | 1 | 0 | 0 | — |
| S3 | C5 | INSUFFICIENT_EVIDENCE | null | null | 0.00 | 0 | 0 | 0 | — |
| S4 | C1 | SUPPORTED | 0.9683 | HIGH | 0.25 | 3 | 0 | 2 | — |
| S5 | C1 | SUPPORTED | 0.9468 | HIGH | 0.50 | 2 | 0 | 0 | — |

Derivations (all priors 0.50, so prior log-odds 0):

- `C1@S1`, `C2`, `C5@S2`: 2.0 × 0.9 = 1.8 → σ(1.8) = 0.8581; variants σ(1.26)=0.7790, σ(2.34)=0.9121; spread 0.1331 → MEDIUM.
- `C3`: 0.6 × 0.3 × (1 − 0.15) = 0.153 → 0.5382; `INTERPRETIVE` caps stability at LOW. No primary source, E2 ungrouped → coverage 0.
- `C4`: −(0.6 × 0.9) = −0.54 → 0.3682; spread 0.0752 would be HIGH, but only one group → MEDIUM. Coverage: primary ✓, opposing search (T2) ✓, independence ✓ → 0.75.
- `C5@S3`: L5 invalidated, nothing counted → INSUFFICIENT_EVIDENCE; the independence item requires at least one counted item, so coverage 0.
- `C1@S4`: 1.8 + 1.08 + 0.54 = 3.42 → 0.9683 (inflated by double-counting SB and SC); E4, E5 ungrouped → independence item fails → 0.25.
- `C1@S5`: G2 keeps L6 (1.08), suppresses L7 → 2.88 → 0.9468; spread 0.0944 with 2 groups → HIGH; coverage 0.50.

### Under `ledger-strict@0.1.0`

Identical to the table above for `C1`, `C2`, `C4`, `C5`, `C6` at every checkpoint (none of their counted evidence is `EXPERT_ANALYSIS`, and their types are scored by both models). The only difference:

| Chk | Claim | State | p | Stability | cov | sg | cg | unrev | Reason |
|---|---|---|---|---|---|---|---|---|---|
| S1 | C3 | NOT_APPLICABLE | null | null | 0.00 | 0 | 0 | 1 | NOT_SCORED_BY_MODEL |

`C6` carries `not_applicable_reason: NORMATIVE_OR_VALUE` under both models.

`C1` at S4→S5 is the demo's key teaching moment: the probability goes **down** when an analyst discovers that two sources are one.

### Reputation at S5 (`EVIDENCE_VERIFICATION` × `ancient_near_east` unless noted)

| Contributor | alpha | beta | mean | n | Label |
|---|---|---|---|---|---|
| AgentVerifier | 2 | 1 | 0.6667 | 1 | limited history |
| AgentBad | 1 | 2 | 0.3333 | 1 | limited history |
| Mallory (roll-up) | 1 | 2 | 0.3333 | 1 | limited history |
| AgentVerifier (`SOURCE_INDEPENDENCE_CHECK`) | 2 | 1 | 0.6667 | 1 | limited history |
| Curator (`MANUAL` × `general`) | 6 | 1 | 0.8571 | 5 | — |

At S2, AgentBad is `1 / 1 / 0.5000 / 0`. The change must be visible on the contributor page.

---

## 8. Example Task Packets

T1 is shown in full in 04 §3. T3 is identical in shape with `C5`'s text. T2:

```json
{
  "task_type": "OPPOSING_EVIDENCE_SEARCH",
  "target": {"claim_text": "The seeded narrative describes the Watchers as artificial or technological beings.", "claim_type": "TEXTUAL"},
  "objective": "Search for evidence that SUPPORTS the claim. Report NONE_FOUND if none exists.",
  "context": {"search_direction": "SUPPORT", "scope": "seeded_sources_only",
              "current_counted_statements": ["The excerpt contains no description of the Watchers as artificial or technological."]}
}
```

The stub agents are deterministic fixtures, not heuristics: `AgentVerifier` reads its answer for each seeded task from `examples/agent/fixtures.json` (T1 → `CONFIRMED`, T2 → `NONE_FOUND`, T4 → `GROUPED`); `AgentBad` always returns `CONFIRMED` with a `DIRECT` support link. A keyword-matching stub would be flaky and would teach nothing.

Atomicity demo (UI, not a task): pasting "The Watchers descended, taught metallurgy, fathered giants, and caused corruption." triggers the atomicity warning, and the stub extractor proposes four claims.

---

## 9. Competing Hypotheses (P1)

| Handle | Hypothesis | Expected presentation |
|---|---|---|
| H1 | The narrative is primarily a literary/theological treatment of dangerous knowledge transmission. | Links to C3; shows textual support, model-dependent |
| H2 | The narrative preserves memory of an unusual historical encounter. | Underdetermined; no counted evidence |
| H3 | The narrative preserves memory specifically of artificial or nonhuman technological intelligence. | Depends on C4, which leans contradicted; no direct support |

No hypothesis is marked as the answer. The question page shows them side by side.

---

## 10. What the Demo Shows

Direct textual evidence · interpretation vs. observation · two models disagreeing about `C3`, with the reason shown · a normative claim with no number · "unknown" as a real state · a false contribution that passes validation · deterministic audit sampling · invalidation without erasure · reputation change · double-counting and its correction · snapshot reproduction · log replay.
