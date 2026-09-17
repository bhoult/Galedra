# 05 — Identity, Reputation, and Security

## 1. Threat Model

Assume adversarial contributions. Each threat is paired with its P0 mitigation.

| # | Threat | P0 mitigation |
|---|---|---|
| 1 | Sybil identities | Evidence not votes; per-principal assignment limits; blind multi-assignment; rate limits |
| 2 | Fabricated evidence / fake citations | Excerpt must match stored bytes; `MODEL_OUTPUT` weight 0; random audits |
| 3 | Misquoted real sources | Excerpt hash check; `EVIDENCE_VERIFICATION` audits |
| 4 | False support/contradict links | Links are separate, auditable contributions; `provisional` flag |
| 5 | Evidence double-counting | Independence groups, strongest-only, `independence_unreviewed` count |
| 6 | Coordinated brigading | No endorsement counts; audits by a different principal |
| 7 | Compromised agent keys | Delegation revocation with a compromise window (§4) |
| 8 | Malicious or careless auditors | Audits are auditable (`RE_AUDIT`); auditor reputation |
| 9 | Scoring-model manipulation | Signed model releases; config/code hashes in every trace |
| 10 | Silent history rewriting | Server-side hash chain; replay test; optional external anchoring later |
| 11 | Source replacement / link rot | Stored content hash; new source version on change |
| 12 | Prompt injection via sources or notes | 04 §9 |
| 13 | SSRF via agent-supplied URLs | No server fetch of agent URLs in P0 (04 §6) |
| 14 | Defamation / privacy harm | Private-individual claims out of scope; quarantine (§13) |
| 15 | Selective omission | Review-coverage checklist; opposing-search task (partial) |
| 16 | Collusion among "independent" agents | Principal-level uniqueness; declared model family recorded (partial) |
| 17 | **Correlated AI errors** (same model/prompt/retrieval making the same mistake under different keys) | Distinct principals per slot; software metadata recorded; P1 model-family diversity constraints (04 §3.1); human review for high-impact nodes. Declared metadata is unverifiable. |
| 18 | Low-quality donated agents consuming more audit effort than they save | Heavy auditing of new identities; per-delegate limits; audit effort recorded for later net-value measurement (09 §1) |

The POC does not claim to solve 15–18. It must avoid the naive "more validators = more truth" model.

---

## 2. Keys and Custody

Ed25519 for everything. `key_id = "ed25519:" + hex(sha256(raw_public_key))`.

| Actor | Custody | How it signs |
|---|---|---|
| External agent | `SELF` | Client library signs the canonical envelope |
| API-using human | `SELF` | Same |
| Browser UI user | `SERVER` | Rails holds the private key encrypted with Active Record Encryption, unlocked per request for the authenticated user; contribution records `custody: SERVER` |
| The ledger itself | `SYSTEM` | Signs `ACCEPT`, log entries, task packets, model releases |

The previous draft required every contribution to be signed but gave UI users no way to sign. Server custody is an honest, labeled compromise for a POC; the UI shows a "server-held key" badge, and users can later register a self-custodied key and delegate (P1: browser WebCrypto Ed25519).

The system key lives outside the database (environment/credentials), and its public key is published in `GET /api/meta`.

Use a maintained library (the `ed25519` gem or Ruby OpenSSL 3 Ed25519 support). Never hand-roll primitives.

---

## 3. Signed Contributions

Canonicalize with RFC 8785 before hashing or signing. The signature covers the entire envelope except the `signature` field (04 §4). Any byte change breaks verification. `client_created_at` is informational; `received_at` in the log is authoritative.

---

## 4. Delegation and Revocation

A principal signs a delegation (02 §3.1) granting an agent key permission for specific task types and domains until `valid_until`.

Revocation:

- `REVOKE_DELEGATION` or `REVOKE_KEY` takes effect at its `seq`; later submissions fail validation.
- A revocation may declare `compromised_since` (a `seq`). Contributions from that key after that point are automatically marked `CHALLENGED` and queued for audit; they keep counting only if audits confirm them.

### Reputation roll-up

Reputation events are recorded on the delegate **and** rolled up to the principal. Revoking a compromised agent does not erase failures that occurred before `compromised_since`. This closes the loophole in the previous draft where a principal could launder bad agent history by spinning up new agent keys.

---

## 5. Transparency Log

Defined in 02 §1.2. Additions:

- `GET /api/log?after_seq=` streams entries so third parties can mirror and verify the chain.
- `bin/rails ledger:verify` recomputes every `entry_hash`, checks every client and server signature, and reports the first break.
- The chain head hash can later be anchored externally (e.g., published in a signed git repo). No blockchain.

---

## 6. Reputation — What It Means

> The audited, empirically observed rate at which this identity performs a specific task type correctly in a specific domain.

It does **not** mean "this identity's beliefs are likely true," and in v0.1 it does **not** influence claim scores. It drives audit sampling (§9), task eligibility (P1), and display.

Dimensions: `task_type × domain`. Domains are a small, closed, admin-editable list in P0 (`general`, `ancient_near_east`, `us_economics`, …); every task carries one.

---

## 7. Reputation Calculation

Beta-Binomial, per `(contributor, task_type, domain)`, computed from active `reputation_events` at a snapshot.

```text
prior Beta(1, 1)

audit result          alpha_delta  beta_delta
CONFIRMED             +1.0         0
MINOR_ERROR           +0.7         +0.3
SUBSTANTIVE_ERROR     0            +1.0
FABRICATION           0            +5.0
UNRESOLVED            0            0

mean = alpha / (alpha + beta)
n    = alpha + beta - 2
```

Display `mean`, `n`, and the raw counts. A credible interval is optional in P0; if shown, document the numeric method (e.g., a fixed-iteration incomplete-beta inverse) and include it in the reproducibility test.

Prior changed from Beta(2,2) to Beta(1,1) because reputation no longer multiplies evidence, and the display should not suggest a synthetic track record. The UI always shows `mean` together with `n`, and adds a "limited history" label when `n < 3`.

When an audit is itself invalidated by a `RE_AUDIT`, its reputation event gets `invalidated_seq` and stops counting. The re-audit produces its own event for the original auditor under task type `AUDIT`.

---

## 8. Auditor Selection

- Auditor must be a different principal from the target's principal.
- Auditor must have `n ≥ 5` and `mean ≥ 0.8` in `AUDIT` for the domain, **or** be a human with `ESTABLISHED`+ tier. (Bootstrap: seeded human moderators.)
- Auditors see the target contribution and its referenced source excerpt, not the target's reputation.

---

## 9. Audit Policy

```text
audit_probability = min(1.0,
    base_rate                                   # 0.10
  * (n < 10 ? 5 : 1)                            # new identity in this task/domain
  * (mean < 0.8 ? 2 : 1)                        # low reliability
  * (1 + downstream_count / 5)                  # impact
  * (outcome_is_unusual ? 2 : 1))               # e.g. NOT_SUPPORTED on a claim with 3+ support groups
```

**Determinism:** the audit decision is `sha256(contribution.entry_hash + policy_version) < audit_probability * 2^256`. Anyone can recompute whether a contribution should have been sampled; operators cannot quietly skip audits.

**Anchoring (v4 fix).** Every input above (`n`, `mean`, `downstream_count`, `outcome_is_unusual`) is evaluated **as of the contribution's own seq**, and the inputs, probability, and decision are stored in `audit_schedules` (02). Later audits, new edges, or reputation changes cannot retroactively change whether an old contribution should have been sampled.

`outcome_is_unusual` (P0 definition): the result's outcome disagrees with the target claim's state at that seq — e.g. `NOT_SUPPORTED` on a `SUPPORTED` claim with ≥ 2 support groups, or `CONFIRMED` on a claim with ≥ 1 contradict group and no support.

### Effect of an audit result

| Result | Effect on target |
|---|---|
| `CONFIRMED` | Target counts as audited; clears `provisional` for its links |
| `MINOR_ERROR` | Stays counted; auditor may submit a corrected link as a new contribution |
| `SUBSTANTIVE_ERROR` / `FABRICATION` | `INVALIDATE` contribution appended; target's projection rows get `invalidated_seq`; affected scores recompute |
| `UNRESOLVED` | Target marked `CHALLENGED`; a second audit is scheduled |

**Appeals:** the target's principal may request a `RE_AUDIT` by a different auditor. If the re-audit disagrees, the first audit is invalidated and the target's rows are restored by a new `ACCEPT` (new `created_seq`; history shows the gap).

---

## 10. High-Impact Policy (P0 placeholder)

`downstream_count` = active outgoing `claim_edges` from claims this contribution touches.

| downstream_count | requirement before `provisional` clears |
|---|---|
| 0–2 | 1 confirming audit |
| 3–9 | 2 confirming audits from different principals |
| ≥ 10 | 2 confirming audits + an accepted `OPPOSING_EVIDENCE_SEARCH` |

Thresholds are placeholders and live in config.

---

## 11. Sybil Resistance (summary)

Cryptographic identity alone does not stop one actor from creating 10,000 keys. The P0 posture: nothing in scoring counts heads; independent-verification slots are unique per principal; new identities are heavily audited and rate-limited; evidence must be reproducible from stored bytes. Optional external verification is P1+ (09).

---

## 12. Model and Software Provenance

Every agent contribution records `software` (04 §4). The server records `delegation_id` and custody. This enables later queries like "all links created by model X, prompt v1" for systemic-error audits, and ensures no model family becomes a privileged source (Art. XIV).

---

## 13. Abuse Handling and Moderation

Actions (each a signed contribution by a moderator key): key revocation, contributor suspension, contribution invalidation, audit escalation, `QUARANTINE` / `RELEASE_QUARANTINE` of a source or claim, and `TAKEDOWN`.

**Moderation is never silent** (constitution Art. XII, XIII). Quarantined content is excluded from scoring and its text is withheld from public reads, but a public stub remains at the same URL showing: that the item is quarantined, when, by which moderator key, the stated reason category, and a link to the appeal path. Scores that changed because of a quarantine show that fact in their trace (`reason: "quarantined"`). Legal removal uses `TAKEDOWN` (02 §5) and leaves the same kind of stub.

Moderator actions are contributions like any other: auditable, appealable via `RE_AUDIT`, and listed on a public moderation log page. A quarantine whose stated reason does not match a published category is itself grounds for appeal.

Quarantine reason categories in P0 (closed list): `PRIVATE_INDIVIDUAL`, `PERSONAL_DATA`, `UNLAWFUL_CONTENT`, `UNLICENSED_MATERIAL`, `SPAM`. Disagreement with a claim, its politics, or its conclusion is never a quarantine reason; that is what evidence links are for (Art. V, XVIII). See proposed amendment P-1.

---

## 14. Scoring Model Releases

`RELEASE_SCORING_MODEL` contribution containing: name, semantic version, full config, `config_hash`, `code_hash`, test-suite result hash, and a system-key signature. Weights never change without a new version. Old versions stay loadable so old traces reproduce.

P0 releases **one scorer implementation and two models** (`ledger-default@0.1.0`, `ledger-strict@0.1.0`; 03 §13) that differ only in config. Both carry the same `code_hash`, which covers `app/services/scoring/**/*.rb`; if that code changes, every model using it needs a new version (enforced by a test comparing the computed hash with each registered model's). A release is also rejected if its `review_checklist` declares a check no available task type can satisfy (03 §8).

---

## 15. Privacy

Contributors are never required to expose real name, location, employer, or IP history. Do not fingerprint. Store IPs only in ordinary short-retention request logs, never in the ledger. Pseudonymous reputation is a feature.

---

## 16. Suspicious Contribution Clusters (P1)

Constitution Article XXII asks the system to expose suspicious clusters. P1 adds a read-only report: audit-failure rates grouped by principal, declared model family, prompt version, and time window; groups of new keys whose results agree unusually often on the same tasks. The report raises audit rates through the `anomaly` factor (§9); it never invalidates anything by itself.
