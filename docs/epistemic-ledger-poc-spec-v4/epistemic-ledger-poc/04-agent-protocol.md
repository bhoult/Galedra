# 04 — Agent Protocol

## 1. Goal

Let arbitrary external agents contribute useful work asynchronously with minimal context. Agents are ephemeral workers attached to a durable substrate; none needs the whole project.

The server cannot see or control an external agent's prompts. Every safety property in this file is therefore enforced **server-side** on what the agent returns.

---

## 2. Task Types

P0:

| Task type | Output ops allowed | Result `outcome` values |
|---|---|---|
| `CLAIM_EXTRACTION` | `CREATE_CLAIM` (unaccepted until reviewed; §4.3) | `CLAIMS_FOUND`, `NO_CLAIMS` |
| `EVIDENCE_VERIFICATION` | `LINK_EVIDENCE`, `CREATE_EVIDENCE` on the given location only | `CONFIRMED`, `PARTIAL`, `NOT_SUPPORTED`, `CANNOT_DETERMINE` |
| `OPPOSING_EVIDENCE_SEARCH` | `CREATE_SOURCE`, `CREATE_SOURCE_LOCATION`, `CREATE_EVIDENCE`, `LINK_EVIDENCE` | `FOUND`, `NONE_FOUND` |
| `SOURCE_INDEPENDENCE_CHECK` | `CREATE_INDEPENDENCE_GROUP`, `ASSIGN_INDEPENDENCE_GROUP` | `GROUPED`, `INDEPENDENT`, `CANNOT_DETERMINE` |
| `QUALIFIER_CHECK` | `CREATE_EVIDENCE`, `LINK_EVIDENCE` (QUALIFY or CONTRADICT), `CREATE_CLAIM`, `CREATE_CLAIM_EDGE`, `SUPERSEDE_LINK` | `QUALIFIERS_FOUND`, `NONE_MATERIAL`, `CANNOT_DETERMINE` |

`QUALIFIER_CHECK` looks for omitted time ranges, populations, denominators, baselines, sampling limits, jurisdictions, and translations. It is P0 (promoted in v4) because the public demo depends on it. A result that supersedes another principal's links is a proposal until a different principal accepts it (02 §1.1a).

`OPPOSING_EVIDENCE_SEARCH` replaces "contradiction search": it searches in the direction opposite to the claim's current lean (for `INSUFFICIENT_EVIDENCE`, it searches for support). The packet states the direction explicitly. A `NONE_FOUND` result still satisfies the `opposing_search_done` coverage item — a documented null search is information.

P1: `CLAIM_DEDUPLICATION` (output is candidate edges only, never merges), `SUMMARY_GENERATION` (external).
Deferred: causal review, statistical recalculation, legal precedent review, translation comparison, alternative-hypothesis search.

Audits are **not** a task type an arbitrary agent can pull; they are assigned (05 §9).

---

## 3. Task Packet (`eir-task-v1`)

Server-built, server-signed, canonical JSON.

```json
{
  "protocol": "eir-task-v1",
  "task_id": "0192…",
  "task_type": "EVIDENCE_VERIFICATION",
  "domain": "general",
  "issued_at": "2026-09-16T21:00:00Z",
  "lease_expires_at": "2026-09-16T23:00:00Z",
  "snapshot_seq": 9,
  "target": {
    "claim_id": "0192…",
    "claim_text": "The Journal of Distributed Work Research (2025) reports that 62% of remote workers report higher productivity.",
    "claim_type": "TEXTUAL"
  },
  "objective": "Decide whether the excerpt directly supports the claim. Do not infer beyond the excerpt.",
  "context": {
    "source_id": "0192…",
    "source_location_id": "0192…",
    "locator": {"type": "CHAR_RANGE", "start": 0, "end": 102},
    "untrusted_excerpt": "Acme press release: 62% of remote workers report higher productivity, according to Acme's 2026 survey.",
    "excerpt_hash": "sha256:…",
    "known_qualifiers": {}
  },
  "constraints": {
    "allowed_ops": ["LINK_EVIDENCE", "CREATE_EVIDENCE"],
    "max_ops": 3,
    "require_exact_location": true
  },
  "return_schema": "eir-result-v1",
  "server_key_id": "ed25519:…",
  "server_signature": "…"
}
```

`task_packet_hash = sha256(canonical packet without server_signature)`.

Context budget target: 500–2,500 tokens. Excerpts from a single source are capped (e.g. 2,000 characters) to limit copyright exposure and prompt-injection surface.

### 3.1 Blind independent verification

When `required_assignments > 1`, each assignee receives the same packet and **no information** about other assignees' results or identities. Results are revealed only after all slots are submitted or leases expire.

**Independence applies to verification processes, not just sources.** Two agents with different keys but the same model, prompt family, or retrieval path can repeat the same mistake. P0 enforces distinct principals per slot. P1 adds optional slot constraints for high-impact tasks: distinct declared `model_provider`/`model_id` family, distinct retrieval path, or at least one human. Declared model metadata is self-reported and unverifiable, so these constraints raise the cost of correlated error; they do not eliminate it.

---

## 4. Result Envelope (`eir-result-v1`)

```json
{
  "protocol": "eir-result-v1",
  "action_type": "TASK_RESULT",
  "task_id": "0192…",
  "task_packet_hash": "sha256:…",
  "contributor_key_id": "ed25519:…",
  "delegation_id": "0192…",
  "client_created_at": "2026-09-16T21:04:10Z",
  "software": {
    "agent_name": "example-agent",
    "version": "0.1.0",
    "model_provider": "stub",
    "model_id": "none",
    "prompt_version": "verify-v1"
  },
  "payload": {
    "outcome": "CONFIRMED",
    "ops": [
      {
        "op": "LINK_EVIDENCE",
        "evidence_item_id": "0192…",
        "claim_id": "0192…",
        "direction": "SUPPORT",
        "relevance_strength": "DIRECT",
        "interpretive_steps": 0,
        "note": "Release states the same figure."
      }
    ]
  },
  "payload_hash": "sha256:…",
  "signature": "…"
}
```

The signature covers the canonical envelope **minus** the `signature` field. That includes `task_packet_hash`, `payload_hash`, `client_created_at`, `software`, and `delegation_id`.

No floats appear. The previous draft's `extraction_confidence: 0.99` is removed: self-reported confidence is unverifiable, trivially gamed, and is not used by scoring.

### 4.1 Ops

Ops use the same shape as the corresponding contribution action payloads in 02 §3.6. New objects inside one result may be referenced by a client-chosen `ref` string (`"ref": "new-ev-1"`) that later ops in the same result can use in place of an ID.

### 4.2 Idempotency

`idempotency_key = sha256(signer_key_id | task_id | payload_hash)` (02 §3.1). A duplicate submission returns the original contribution (HTTP 200) and creates nothing.

### 4.3 Claim extraction is proposal-only

`CLAIM_EXTRACTION` results create claim rows with `accepted_seq = null`. A human (or an agent of a different principal whose delegation permits `ACCEPT`) must accept each before it can receive evidence links or appear in public lists. Extraction is where LLM hallucination most easily becomes durable structure.

---

## 5. Context Compiler

Deterministic function, no LLM:

```text
Tasks::BuildContext.call(task_type:, target_id:, snapshot_seq:, token_budget:) -> packet
```

Same inputs → same packet bytes (excluding timestamps and signature).

| Task type | Includes | Excludes |
|---|---|---|
| Evidence verification | claim text/type, one excerpt, locator, qualifiers | other agents' notes, current score |
| Opposing search | claim text/type, search direction, strongest counted evidence *statements* (not notes) on the current side, known source lineage keys to exclude | full traces, contributor identities |
| Independence check | the claim's counted evidence items: source titles, creators, dates, lineage keys, excerpts | scores |
| Claim extraction | the source excerpt(s), atomicity rules from 02 §4, claim type list | anything from the graph |

**Contributor `note` fields are never included in any packet.** They are free text from untrusted parties and are the easiest injection path between agents.

---

## 6. Server-Side Validation Pipeline

```text
POST result
  -> 1. schema valid (eir-result-v1) and enums closed
  -> 2. signature valid; key not revoked at receipt; delegation valid and permits task_type + domain
  -> 3. task exists; assignment leased to this contributor; lease not expired
  -> 4. task_packet_hash matches the stored packet
  -> 5. every op ∈ constraints.allowed_ops; count ≤ max_ops
  -> 6. every referenced ID exists and is active at receipt
  -> 7. for EVIDENCE_VERIFICATION: evidence refers to the packet's source_location_id
  -> 8. new CHAR_RANGE locations: excerpt equals stored slice; hash matches
  -> 9. no server-side fetching of agent-supplied URLs (SSRF); new external sources are stored as
        metadata-only with `retrieval_pending`, and a human or trusted job imports content later
  -> Ledger::Append (TASK_RESULT)      # state PENDING
  -> automated acceptance checks pass
  -> Ledger::Append (ACCEPT by system key)   # links become counted
  -> Audits::MaybeSchedule
  -> Scoring::RecomputeAffected
```

Failures at steps 1–9 return 422 with a machine-readable error list and create **no** contribution (nothing to log; nothing signed by us).

Passing validation proves the result is well-formed and attributable — not that it is correct. That is why accepted-but-unaudited work sets the `provisional` flag (03 §2).

---

## 7. Leases

```text
POST /api/v1/tasks/next?types=…&domains=…   -> leases one task (or 204)
```

- Lease length: 2 hours default, per-type configurable.
- One active lease per `(task, contributor)` and per `(task, principal)`.
- Expired leases release the slot; a late submission is rejected at step 3.
- Per-delegate hourly limit from `agent_delegations.max_tasks_per_hour`, counted over a rolling hour; per-key rate limits from Rails 8 `rate_limit`. Delegations signed before this field was renamed carry `max_tasks_per_day`, and the applier reads either, so replay reproduces them unchanged.
- Tasks are offered in descending `priority` (03 §14), filtered by delegation permissions.

---

## 8. Adversarial Roles

Roles map to task types and prompt templates in the example client:

| Role | Task type |
|---|---|
| Extractor | `CLAIM_EXTRACTION` |
| Verifier | `EVIDENCE_VERIFICATION` |
| Skeptic | `OPPOSING_EVIDENCE_SEARCH` |
| Independence analyst | `SOURCE_INDEPENDENCE_CHECK` |
| Auditor | assigned audits (05) |

**No self-certification:** a contribution cannot be audited, and a proposed claim cannot be accepted, by the same contributor **or any contributor under the same principal**.

---

## 9. Prompt Injection

The server's defenses (enforced):

- results are structured ops with closed enums; free text (`note`) is display-only, HTML-escaped, and excluded from scoring, packets, and summary inputs;
- excerpts in packets are labeled `untrusted_excerpt`;
- scoring never reads text.

The example client's defenses (recommended to all agent authors):

- wrap excerpts in explicit delimiters and instruct the model that content inside is data, not instructions;
- give research agents minimal tool permissions (no write access to anything but the result submission).

---

## 10. Summaries (server-side, P0 stub)

Summaries are derived caches, never evidence.

Input (deterministic): claim text/type, `assessment_state`, `probability`, `review_coverage` checklist, kept links with their evidence **statements** (not notes), suppressed-link count, model and snapshot.

Output (JSON, validated):

```json
{"sentences": [
  {"text": "The 62% figure comes from one Acme customer survey of 400 people.", "cites": ["E1"]},
  {"text": "The press release and three articles repeat it and are not independent.", "cites": ["G1"]},
  {"text": "No opposing-evidence search has been recorded yet.", "cites": ["coverage:C2"]}
]}
```

Validation: every sentence has ≥1 cite; every cite is in the input set; otherwise reject and fall back to the stub.

The P0 generator is a **template stub** (`stub-v0.1`) that fills sentences from the trace. An LLM generator (P1) must pass the same validator.

Types: `SHORT` (1–2 sentences), `STANDARD` (≤6). `DETAILED` is deferred.

---

## 11. Minimal Agent SDK

Ship `examples/agent/` (Ruby, single file, no Rails dependency) and optionally a Python equivalent:

```ruby
client = Ledger::Client.new(base_url:, key_file:, delegation_id:)
packet = client.lease_next(types: ["EVIDENCE_VERIFICATION"])
client.verify_packet!(packet)               # server signature
result = StubVerifier.run(packet)           # deterministic keyword check in P0
client.submit(result)                       # canonicalizes, hashes, signs
```

Include JSON Schemas (`schemas/eir-task-v1.json`, `schemas/eir-result-v1.json`) and a canonicalization test vector so third-party clients can confirm they hash identically.
