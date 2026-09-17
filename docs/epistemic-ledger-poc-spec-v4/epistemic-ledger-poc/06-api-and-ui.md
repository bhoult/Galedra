# 06 — API and UI

## 1. API Principles

- REST/JSON, boring and inspectable. Versioned under `/api/v1`.
- **Reads** are public (except quarantined content). **Writes** require a valid signed envelope; UI writes go through the same service with server custody.
- There is exactly **one write path**: `POST /api/v1/contributions`. Resource-specific POST routes in the previous draft are removed; they duplicated validation and invited a second write path that bypasses the log.
- Rate limiting via Rails 8 `rate_limit`, keyed by `key_id`.
- Every score-bearing response includes `snapshot_seq`, `model`, and `assessment_state`.
- Errors: `{"errors": [{"code": "EXCERPT_HASH_MISMATCH", "path": "payload.ops[0]", "detail": "…"}]}`.

---

## 2. Endpoints (P0)

### Meta and log

```text
GET  /api/v1/meta                         system key, current seq, model list, schema URLs, constitution_hash + version
GET  /api/v1/log?after_seq=&limit=        raw log entries for mirroring
GET  /api/v1/contributions/:id            envelope, entry, status, audits
GET  /api/v1/contributions/:id/verify     {client_signature_ok, server_signature_ok, chain_ok}
POST /api/v1/contributions                the only write endpoint
```

### Graph reads

```text
GET  /api/v1/sources/:id
GET  /api/v1/sources/:id/locations
GET  /api/v1/claims?type=&state=&q=
GET  /api/v1/claims/:id                   ?snapshot_seq= (default: latest)
GET  /api/v1/claims/:id/evidence
GET  /api/v1/claims/:id/score             ?snapshot_seq=&model=
GET  /api/v1/claims/:id/trace             ?snapshot_seq=&model=
GET  /api/v1/claims/:id/summary           ?type=SHORT|STANDARD&snapshot_seq=
GET  /api/v1/claims/:id/why               deterministic "show me why" bundle (01 §6)
GET  /api/v1/claims/:id/compare           ?models=a,b&snapshot_seq= (03 §13)
GET  /api/v1/weaknesses                   ?kind=&limit= (§5 Weaknesses page)
GET  /api/v1/moderation                   public moderation log (05 §13)
GET  /api/v1/evidence/:id
GET  /api/v1/contributors/:id
GET  /api/v1/contributors/:id/reputation  ?snapshot_seq=
```

`/summary` and `/why` replace the previous draft's overlapping `/summary` and `/explanation?length=` routes: `/why` is the structured data, `/summary` is its prose rendering.

### Tasks

```text
POST /api/v1/tasks/next                   lease one task (04 §7)
GET  /api/v1/tasks/:id
POST /api/v1/tasks/:id/release            give the lease back
```

Results are submitted via `POST /api/v1/contributions` with `action_type: TASK_RESULT`.

### Snapshots and scoring

```text
GET  /api/v1/snapshots                    pinned snapshots
GET  /api/v1/snapshots/:seq               {seq, entry_hash, claim_score_digest}
GET  /api/v1/scoring-models
POST /api/v1/admin/snapshots              moderator-only: pin a label to a seq
POST /api/v1/admin/recompute              moderator-only: enqueue full recompute
```

`claim_score_digest` = sha256 over the sorted list of `(claim_id, trace_hash)` for all claims at that seq under the default model. Two installations with the same log must return the same digest.

P1: questions, hypotheses, export bundles.

---

## 3. Claim Response Example

```json
{
  "id": "0192…",
  "handle": "C2",
  "text": "62% of remote workers report higher productivity.",
  "type": "QUANTITATIVE",
  "truth_evaluable": true,
  "status": "ACTIVE",
  "card": {
    "headline": "Unresolved",
    "independent_lineages": 1,
    "review_checks": "3 of 4",
    "stability": "MEDIUM",
    "main_issue": {"kind": "QUALIFY_LINK", "cites": ["E6"],
                   "text": "The only data is a survey of Acme customers"},
    "related": [{"handle": "C3", "relation": "NARROWS", "headline": "Supported"}]
  },
  "assessment": {
    "snapshot_seq": 44,
    "model": "ledger-default@0.1.0",
    "assessment_state": "UNRESOLVED",
    "probability": "0.5247",
    "model_dependent": false,
    "stability": "MEDIUM",
    "review_coverage": "0.75",
    "support_groups": 1,
    "contradict_groups": 0,
    "independence_unreviewed": 0,
    "contested": false,
    "provisional": false,
    "not_applicable_reason": null
  },
  "evidence_counts": {"support": 5, "contradict": 0, "qualify": 1, "counted": 1, "suppressed": 4}
}
```

The UI renders `card` by default and `assessment` under **Show calculation**. API clients get both.

---

## 4. Display Rules (normative)

1. **Lead with the compact answer, not the graph and not the number** (v4). The default view of a claim is an answer card:

   ```text
   Leans supported · 2 independent evidence lineages · review checks 3 of 4 · stability medium
   Main unresolved issue: the only data is a customer-only survey [E6]
   [Why?]  [Show calculation]  [Model: ledger-default ▾]
   ```

   The probability, trace, and graph live behind **Show calculation** and **Why?**. Users read 0.73 as "73% true" no matter how it is labeled, so the number is available but never the headline.
2. **When the number is shown**, it always carries model and snapshot, and sits next to state, review checks, stability, and independent lineage count.
3. `INSUFFICIENT_EVIDENCE` and `NOT_APPLICABLE` show **no number at all**.
4. `provisional` shows "Not yet independently audited." `contested` shows "Evidence points both ways."
5. Low review coverage with a strong state renders as: "Evidence reviewed so far supports this claim, but only 1 of 4 review checks has been done." Review coverage is always shown as a count of checks, never as low/medium/high or a percentage, because a finished checklist does not mean most evidence was found (Art. VIII).
5a. **Main unresolved issue** on the answer card is chosen deterministically, first match wins: an invalidated or disputed audit; `independence_unreviewed` > 0; a `QUALIFY` link; `contested`; the first unmet review check; otherwise "none recorded."
6. Model-dependent types (`INTERPRETIVE`, `CAUSAL`) show "This assessment depends heavily on modeling choices."
7. Evidence counts show both raw and independent: "3 sources, 2 independent lineages."
8. Contributor reputation is shown only on contributor and contribution pages, never on claim headlines.
9. **Personal belief is never styled as an assessment** (Art. XV). P1 personal views appear in a separate, labeled panel ("Your view" / "Alice's view") with their lens stated, and never replace, average with, or sit in the headline position of the shared assessment.
10. `NOT_APPLICABLE` always shows its reason in plain words (e.g. "This is a value judgment; the system maps its premises but does not assign it a probability").
11. **A model selector** is always available next to the assessment. The default model is labeled as a default, not as "the" answer (Art. XIX).
12. **No persuasive framing.** No color-coding of claims as true/false, no "debunked"/"confirmed" badges, no ranking of claims by how "wrong" they are. States use neutral wording and neutral colors.

---

## 5. UI Pages (Hotwire, functional not polished)

**Home** — Analyze text · Browse claims · Task board · Recent audits · Log.

**Analyze text** — paste text → stub/LLM proposes claims → user edits, splits, types each (atomicity warnings inline; private-individual checkbox) → submit accepted claims → optional "create verification tasks."

**Claim page** — sections in order: Claim · Assessment (per §4) · Why (from `/why`) · Evidence for · Evidence against · Qualifications · Suppressed as dependent · Claim edges · Review checklist · Summary · Contribution history · Score trace (collapsible JSON) · Snapshot picker.

**Evidence page** — source, exact locator, excerpt, content hash, linked claims, creating contribution, audits.

**Contribution page** — envelope, signature/chain verification badges, custody badge, software metadata, status history, audits.

**Contributor page** — per task type × domain: audited count, mean, "limited history" label. No followers, likes, or aggregate prestige.

**Task board** — task, type, domain, priority, estimated cost, required assignments, audit requirement. "Hand this to my agent" copies a lease command for the example client (no in-browser agent in P0).

**Weaknesses page** (Art. XXII) — deterministic lists, each linked to the claims involved: claims with at most one satisfied review check but a scored state; `provisional` assessments; claims with `independence_unreviewed` > 0; `contested` claims; claims whose state differs between the two released models; claims with high `downstream_count` that are `INSUFFICIENT_EVIDENCE`; evidence links with unresolved or disputed audits. Each claim entry shows the "what would most change this" item from `/why`.

**Moderation log** — every quarantine, release, takedown, suspension, and revocation, with moderator key, reason category, and appeal status.

**Snapshot view** — pick a seq; claim pages render as of that seq; a diff link compares states between two seqs (P1 for full epistemic diff).

---

### Per-source answer card

For a source run through **Analyze text** (e.g. an AI draft), the source page shows one line per extracted claim using the answer card, plus a one-sentence roll-up (08 §9). This is the P0 form of "the graph powers answers."

### Distribution (P1+)

Adoption depends more on answers appearing where people already work than on graph views: document-editor and AI-writing-tool integrations, browser extensions, research assistants, internal knowledge tools. P1 adds `GET /api/v1/claims/:id/card` and `GET /api/v1/sources/:id/card` (compact JSON + HTML fragment) so such integrations need no graph logic.

---

## 6. Political Speech Rule (P1 view, rule applies now)

Never produce a speaker- or party-level truth score. A speech view shows descriptive counts by `assessment_state` over its extracted claims, with a note that counts depend on extraction granularity:

```text
168 extracted claims · 131 truth-evaluable
 74 SUPPORTED · 21 LEANS_SUPPORTED · 9 UNRESOLVED · 6 LEANS_CONTRADICTED · 5 CONTRADICTED
 16 INSUFFICIENT_EVIDENCE · 37 NOT_APPLICABLE
```

No ranking, no comparison across speakers.

---

## 7. Search

P0: PostgreSQL full-text search on claim text and evidence statements; `pg_trgm` for near-duplicate suggestions. Filters: type, state, source, contributor, status.

P1: pgvector for semantic neighbors. Similarity is used for discovery and deduplication only, **never** as evidence weight.

---

## 8. Export

P0: every GET is already JSON; `GET /api/v1/log` is the complete export.
P1: bundles (claim + evidence + trace), JSON-LD / W3C PROV mappings (09).
