# 08 — Seeded Example (public/default demo)

## 1. Purpose

The default demo (`bin/demo`) shows the ledger doing something ordinary and useful: checking an AI-drafted paragraph that repeats a popular statistic with a fabricated citation. It is the first thing collaborators, contributors, and funders should see.

Everything is **fictional**: the company, survey, articles, and journal are invented for the demo. No real organization or publication is being assessed.

The earlier textual example is kept as an internal stress test in `examples/watchers/`.

It demonstrates, in order:

1. a claim that appears to have four sources but has one origin;
2. independence analysis collapsing them;
3. an omitted qualifier in the original source changing the assessment;
4. a narrow claim and a broad claim that look like duplicates but must not be merged;
5. a fabricated citation;
6. a false verification that passes validation and is caught by audit;
7. two scoring models disagreeing about a causal claim;
8. a normative claim with no number;
9. a compact "why" answer backed by the graph;
10. snapshot reproduction and log replay.

Handles (`C1`, `E1`, `L1`…) are display handles; real IDs are UUIDv7.

---

## 2. The Input

A user pastes this AI-drafted memo paragraph into **Analyze text**:

> Remote work boosts productivity: 62% of remote workers report higher productivity (Journal of Distributed Work Research, 2025). Companies should adopt remote work.

---

## 3. Contributors

| Handle | Kind | Principal | Custody | Role |
|---|---|---|---|---|
| `System` | SYSTEM | — | SYSTEM | genesis key; accepts; signs packets |
| `Curator` | HUMAN | self | SERVER | the user checking the memo |
| `Reviewer` | HUMAN, ESTABLISHED | self | SERVER | accepts proposals; audits |
| `Alice` | HUMAN | self | SELF | principal for `AgentVerifier` |
| `AgentVerifier` | AGENT | Alice | SELF | extraction |
| `Bob` | HUMAN | self | SELF | principal for `AgentChecker` |
| `AgentChecker` | AGENT | Bob | SELF | search, independence, qualifier tasks on what AgentVerifier extracted |
| `Mallory` | HUMAN | self | SELF | principal for `AgentBad` |
| `AgentBad` | AGENT | Mallory | SELF | submits a false verification |

Domain for all tasks: `general`.

---

## 4. Sources

| Handle | Type | Stored content (developer-written) |
|---|---|---|
| `SD` | OTHER | The AI-drafted paragraph in §2 |
| `SR` | DATASET | "Acme Remote Work Survey 2026. Respondents: 400 remote employees recruited from Acme customer accounts. Self-reported: 62% said their productivity was higher when working remotely." |
| `SP` | PRIMARY_TEXT | "Acme press release: 62% of remote workers report higher productivity, according to Acme's 2026 survey." |
| `SN1`, `SN2`, `SN3` | SECONDARY_TEXT | Three news articles, each stating "62% of remote workers report higher productivity" and citing Acme's press release |
| `SX` | WEBSITE | Snapshot of the (fictional) publisher's 2025 table of contents for the Journal of Distributed Work Research, containing no article on remote-work productivity |

Each has one `CHAR_RANGE` location covering the relevant passage.

---

## 5. Claims

| Handle | Text | Type | Origin |
|---|---|---|---|
| `C1` | The Acme press release states that 62% of remote workers report higher productivity. | TEXTUAL | Curator |
| `C2` | 62% of remote workers report higher productivity. | QUANTITATIVE | extracted from SD |
| `C3` | 62% of 400 remote employees of Acme customers surveyed by Acme in 2026 reported higher productivity. | QUANTITATIVE | Curator |
| `C4` | The Journal of Distributed Work Research (2025) reports that 62% of remote workers report higher productivity. | TEXTUAL | extracted from SD |
| `C5` | Companies should adopt remote work. | NORMATIVE | extracted from SD |
| `C6` | Remote work causes higher productivity. | CAUSAL | extracted from SD ("boosts") |

**Claim identity test.** `C2` and `C3` differ by a few words, and trigram search will suggest them as duplicates. They must **not** be merged: they need different evidence and end with different assessments. The correct relationship is the explicit edge `C3 NARROWS C2`.

---

## 6. Evidence, Groups, Links

| Handle | Source | Observation | Statement | Group |
|---|---|---|---|---|
| `E1` | SR | DATASET_RESULT | 62% of 400 surveyed respondents reported higher productivity | `G1` |
| `E2` | SP | DIRECT_TEXT | The release states the 62% figure, citing Acme's survey | `G1` |
| `E3`–`E5` | SN1–SN3 | DIRECT_TEXT | Article states the 62% figure, citing the release | none → `G1` at S4 |
| `E6` | SR | DATASET_RESULT | Respondents were recruited only from Acme customer accounts; answers are self-reported | `G1` |
| `E7` | SX | DIRECT_TEXT | The journal's 2025 contents list no article on remote-work productivity | `G2` |

`G1` = SAME_DATASET (Acme 2026 survey). `G2` = OTHER (publisher index).

| Link | Evidence → Claim | Direction | Relevance | Steps | Note |
|---|---|---|---|---|---|
| L1 | E2 → C1 | SUPPORT | DIRECT | 0 | |
| L2 | E1 → C3 | SUPPORT | DIRECT | 0 | |
| L3 | E1 → C2 | SUPPORT | STRONG | 1 | survey → population |
| L4–L7 | E2–E5 → C2 | SUPPORT | MODERATE | 1 | as first extracted |
| L8 | E7 → C4 | CONTRADICT | MODERATE | 0 | an index snapshot can be incomplete, so not STRONG |
| L9 | E1 → C6 | SUPPORT | WEAK | 2 | a satisfaction survey is not a causal design |
| L10 | E2 → C4 | SUPPORT | DIRECT | 0 | **AgentBad's false link** |
| L11–L15 | E1–E5 → C2 | SUPPORT | WEAK | 3 | supersede L3–L7 after the qualifier check (customer sample, self-report → all remote workers) |
| L16 | E6 → C2 | QUALIFY | DIRECT | 0 | |

---

## 7. Script (`db/seeds/demo.rb`, driven by `bin/demo`)

Every step is a contribution through the real write path.

```text
 1. Genesis: System key. REGISTER_KEY for Curator, Reviewer, Alice, Mallory, Bob,
    AgentVerifier, AgentBad, AgentChecker; delegations Alice→AgentVerifier,
    Mallory→AgentBad, Bob→AgentChecker
 2. Curator: SD source + location
 3. T0 CLAIM_EXTRACTION(SD) → AgentVerifier (fixture): records C2, C4, C5, C6
    System: ACCEPT after validation (02 §1.1a; the result only adds claims), and
    their verification tasks open with them. The claims are therefore Alice's,
    so AgentVerifier never checks them itself (04 §3.1, Article XI); the
    atomicity warning is shown in the UI
 4. Curator: SR, SP, SN1–3, SX + locations; C1, C3
 5. Curator: E1, E2, E3, E4, E5, E7; G1 (assign E1, E2); G2 (assign E7)
 6. Curator: L1, L2, L3, L4, L5, L6, L7, L8, L9   (System ACCEPTs each after validation)
 7. T1 OPPOSING_EVIDENCE_SEARCH(C4, direction SUPPORT) → AgentChecker: NONE_FOUND
 8. Reviewer: AUDIT CONFIRMED on T0, T1, and each Curator link contribution
 ── checkpoint S1 "as drafted"
 9. T2 EVIDENCE_VERIFICATION(C4, SP location) → AgentBad: CONFIRMED, op L10
 ── checkpoint S2 "poisoned"
10. Audit sampling for T2 (inputs evaluated at T2's seq, 05 §9): n=0 → ×5, mean 0.5 → ×2 → p = 1.0 → sampled
11. Reviewer: AUDIT SUBSTANTIVE_ERROR on T2 ("The press release is not the cited journal article.")
    → System INVALIDATE; L10 invalidated
 ── checkpoint S3 "audited"
12. T3 SOURCE_INDEPENDENCE_CHECK(C2) → AgentChecker: GROUPED; assign E3, E4, E5 → G1
13. Reviewer: AUDIT CONFIRMED on T3
 ── checkpoint S4 "grouped"
14. T4 QUALIFIER_CHECK(C2) → AgentChecker: ops CREATE_EVIDENCE E6; LINK L16;
        CREATE_CLAIM_EDGE C3 NARROWS C2; SUPERSEDE_LINK L3→L11 … L7→L15
    (supersessions are proposals on another contributor's links → pending)
15. Reviewer: ACCEPT T4; AUDIT CONFIRMED on T4
 ── checkpoint S5 "qualified"
16. Assert: no MERGE between C2 and C3 exists, although the duplicate-suggestion list contains the pair
17. Print golden tables (both models), /compare for C6, the "why" cards (§9), reputation, snapshot digests
18. Replay check: truncate projections, replay, compare S1–S5 digests
```

---

## 8. Golden Values

### `ledger-default@0.1.0`

`p` = probability; `cov` = review_coverage (checks satisfied ÷ 4); `sg`/`cg` = support/contradict groups; `unrev` = independence_unreviewed.

| Chk | Claim | State | p | Stability | cov | sg | cg | unrev | Flags / reason |
|---|---|---|---|---|---|---|---|---|---|
| S1 | C1 | SUPPORTED | 0.8581 | MEDIUM | 0.50 | 1 | 0 | 0 | |
| S1 | C2 | SUPPORTED | 0.9085 | MEDIUM | 0.25 | 4 | 0 | 3 | inflated by repetition |
| S1 | C3 | SUPPORTED | 0.8581 | MEDIUM | 0.50 | 1 | 0 | 0 | |
| S1 | C4 | LEANS_CONTRADICTED | 0.3682 | MEDIUM | 0.50 | 0 | 1 | 0 | |
| S1 | C5 | NOT_APPLICABLE | null | null | 0.00 | 0 | 0 | 0 | NORMATIVE_OR_VALUE |
| S1 | C6 | UNRESOLVED | 0.3792 | LOW | 0.50 | 1 | 0 | 0 | model-dependent |
| S2 | C4 | LEANS_SUPPORTED | 0.7790 | MEDIUM | 0.75 | 1 | 1 | 0 | contested, provisional |
| S3 | C4 | LEANS_CONTRADICTED | 0.3682 | MEDIUM | 0.50 | 0 | 1 | 0 | |
| S4 | C2 | LEANS_SUPPORTED | 0.7146 | MEDIUM | 0.50 | 1 | 0 | 0 | |
| S5 | C2 | UNRESOLVED | 0.5247 | MEDIUM | 0.75 | 1 | 0 | 0 | |
| S5 | C3 | SUPPORTED | 0.8581 | MEDIUM | 0.50 | 1 | 0 | 0 | |

### `ledger-strict@0.1.0`

Identical except:

| Chk | Claim | State | p | Stability | cov | sg | cg | unrev | Reason |
|---|---|---|---|---|---|---|---|---|---|
| S1 | C6 | NOT_APPLICABLE | null | null | 0.50 | 0 | 0 | 0 | NOT_SCORED_BY_MODEL |

### Derivations (prior log-odds 0 except CAUSAL = −0.619039)

- **C1, C3:** 2.0 × 0.9 = 1.8 → 0.8581; variants 0.7790 / 0.9121; one group → MEDIUM.
- **C2 @ S1:** G1 keeps L3 (1.2 × 0.9 × 0.85 = 0.918) and suppresses L4; E3–E5 are ungrouped and each count 0.6 × 0.9 × 0.85 = 0.459. Sum 2.295 → 0.9085 (variants 0.8329 / 0.9518, spread 0.1189 → MEDIUM). **Four "independent" groups, three of them unreviewed.**
- **C2 @ S4:** E3–E5 join G1 and are suppressed. Sum 0.918 → 0.7146.
- **C2 @ S5:** all five supports superseded to WEAK with 3 steps: 0.2 × 0.9 × 0.55 = 0.099 each; G1 keeps L11 (tie → lowest evidence ID). Sum 0.099 → 0.5247 → UNRESOLVED. Spread 0.0148 would be HIGH; one group caps it at MEDIUM. L16 (QUALIFY) counts 0 but satisfies the qualifier check.
- **C3 @ S5:** unchanged. The narrow claim the data actually supports stays SUPPORTED while the viral generalization becomes UNRESOLVED.
- **C4:** −(0.6 × 0.9) = −0.54 → 0.3682. At S2 L10 adds 1.8: sum 1.26 → 0.7790, contested and provisional; after invalidation it returns to 0.3682.
- **C6:** −0.619039 + 0.2 × 0.9 × 0.7 = −0.493039 → 0.3792. Under the v3 rule this would have read LEANS_CONTRADICTED although no evidence contradicts it; v4's rule (03 §4 Step 5) makes it UNRESOLVED. Strict does not score CAUSAL.

### Reputation at S5

| Contributor | Bucket | alpha | beta | mean | n |
|---|---|---|---|---|---|
| AgentBad | EVIDENCE_VERIFICATION × general | 1 | 2 | 0.3333 | 1 |
| AgentVerifier | CLAIM_EXTRACTION × general | 2 | 1 | 0.6667 | 1 |
| AgentChecker | OPPOSING_EVIDENCE_SEARCH, SOURCE_INDEPENDENCE_CHECK, QUALIFIER_CHECK × general | 2 | 1 | 0.6667 | 1 each |
| Curator | MANUAL × general | 10 | 1 | 0.9091 | 9 |

---

## 9. The Compact Answers (what most users see)

Generated by the stub generator at S5 from the trace; every clause cites graph IDs. The number is available under **Show calculation**.

**C2 — "62% of remote workers report higher productivity."**
> **Unresolved.** The figure comes from one Acme customer survey of 400 people [E1]. The press release and three news articles repeat it and are not independent evidence [G1]. The survey sampled only Acme customers and relied on self-reports, so it says little about remote workers in general [E6]. A narrower version of this claim is supported [C3]. Review checks: 3 of 4 [coverage:C2].

**C4 — the journal citation.**
> **Leans contradicted.** No article matching this citation appears in the journal's 2025 contents [E7], and a search for supporting sources found none [T1]. One earlier verification was rejected on audit [A-T2]. Treat this citation as unverified.

**Memo summary (per source `SD`).**
> 4 claims checked: 1 unresolved (the statistic, overgeneralized), 1 leans contradicted (the citation), 1 model-dependent causal claim, 1 value judgment not scored.

---

## 10. What the Demo Proves (and what it doesn't)

It proves the mechanics: repetition isn't corroboration, qualifiers change conclusions, near-duplicate claims stay distinct, validation isn't correctness, audits leave history intact, and models can disagree transparently.

It does not prove the weights are right. Every label in §6 (STRONG vs. MODERATE, the number of interpretive steps) is a judgment. The demo shows those judgments being made explicitly, attributed, challenged, and revised — which is the point (README principle 15).
