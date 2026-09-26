# 02 — Domain Model

## 1. The Log Is the Source of Record

The previous draft said both "normalized state is derived from accepted contributions" and gave projection tables mutable `status` and `invalidated_by` columns with no way to know *when* those changed. That makes historical snapshots unreproducible. This revision commits to a simple event-sourced design.

### 1.1 Two layers

```text
contributions   (append-only log; never updated except for cached columns rebuilt by replay)
     |
     v  Ledger::Apply (pure function of contribution + current projections)
projections     (claims, evidence_items, evidence_claim_links, audits, …)
```

Rules:

1. Every epistemic write is a contribution. There is no other write path.
2. Projections are written **only** by `Ledger::Apply`.
3. `bin/rails ledger:replay` truncates all projections and re-applies every contribution in `seq` order. The result must be identical (row content and snapshot hashes), except where a legally compelled `TAKEDOWN` has physically removed bytes (§5); replay then reports `CHAIN_VERIFIED_WITH_REDACTIONS` rather than claiming completeness.
4. Contribution *acceptance* and *invalidation* are themselves contributions (`ACCEPT`, `INVALIDATE`), signed by the server's system key or an authorized contributor. Nothing changes status silently.

### 1.1a Control vs. epistemic contributions

The previous draft left open whether an `ACCEPT` itself needed accepting. It does not.

| Class | Action types | Takes effect |
|---|---|---|
| **Control** | `REGISTER_KEY`, `DELEGATE`, `REVOKE_KEY`, `REVOKE_DELEGATION`, `ACCEPT`, `INVALIDATE`, `AUDIT`, `QUARANTINE`, `RELEASE_QUARANTINE`, `TAKEDOWN`, `RELEASE_SCORING_MODEL`, `AMEND_CONSTITUTION` | Immediately on append, **if** the signer is authorized for that action at that seq (checked during validation; an unauthorized control contribution is rejected, not logged) |
| **Epistemic** | `CREATE_*`, `LINK_EVIDENCE`, `ASSIGN_INDEPENDENCE_GROUP`, `SUPERSEDE_LINK`, `SUPERSEDE_CLAIM`, `MERGE_CLAIMS`, `SET_TRUTH_EVALUABLE`, `TASK_RESULT` | Projection rows are created on append with `accepted_seq = null` and do not count until an `ACCEPT` references the contribution |

Who may `ACCEPT`:

- **System key**, automatically, after validation for: sources, locations, evidence items, and links created by a contributor directly (not via a task), and `TASK_RESULT`s of `EVIDENCE_VERIFICATION`, `OPPOSING_EVIDENCE_SEARCH`, `SOURCE_INDEPENDENCE_CHECK`, and `QUALIFIER_CHECK` that only add objects;
- **a different principal** (human reviewer, or an agent whose delegation permits `ACCEPT`), required for: claims proposed by `CLAIM_EXTRACTION`; any `SUPERSEDE_LINK`, `SUPERSEDE_CLAIM`, or `MERGE_CLAIMS` that touches another principal's contribution; `SET_TRUTH_EVALUABLE`.

Claims created directly by a human are auto-accepted. There is no `PROPOSED` status; a proposal is simply a row with `accepted_seq = null`.

### 1.2 Sequence and hash chain

Clients sign their envelope asynchronously and cannot know the previous log entry. So the chain is built **server-side** around the client signature:

```text
entry_hash(n) = sha256( canonical_json({
  seq:            n,
  prev_hash:      entry_hash(n-1),     # seq 0 uses 64 zeros
  envelope_hash:  sha256(canonical client envelope incl. signature),
  received_at:    server timestamp (RFC 3339, UTC, microseconds)
}))
```

Appends are serialized with `pg_advisory_xact_lock` so `seq` is gap-free. The server signs `entry_hash` with its system key.

### 1.2a Genesis and key bootstrap

- **seq 0** is the genesis entry: a `REGISTER_KEY` for the system key, self-signed, whose public key is also pinned in deployment configuration. Replay verifies the pinned key matches seq 0.
- A `REGISTER_KEY` is **self-signed by the key being registered** and has `contributor_id = null`; `Ledger::Apply` creates the `contributors` row from it. For server-custodied users, the server generates the key and signs the registration with it.
- For every other contribution, `signer_key_id` is authoritative and `contributor_id` is resolved from it at validation time. A mismatch is rejected.

### 1.3 Validity windows on projections

Every projection row that can be withdrawn carries:

```text
created_seq      bigint not null
invalidated_seq  bigint null
```

A row is **active at snapshot S** iff `created_seq <= S AND (invalidated_seq IS NULL OR invalidated_seq > S)`.

Evidence links additionally carry `accepted_seq` (null until an `ACCEPT` contribution references the creating contribution). A link is **counted at S** iff active at S and `accepted_seq <= S`.

---

## 2. Rails Guidance

- Ordinary Active Record models and migrations; UUIDv7 primary keys.
- Service objects for anything crossing models (`Ledger::Append`, `Ledger::Apply`, `Scoring::Calculate`, …). No epistemic logic in callbacks.
- JSONB for qualifiers and evolving metadata.
- Enums are validated string columns, not Postgres enum types (they change too often during a POC).
- Projection models should be read-only outside `Ledger::Apply` (`def readonly? = !Ledger.applying?`).

---

## 3. Tables

### 3.1 Log and identity

#### `contributions`

```text
id                    uuid
seq                   bigint unique not null
signer_key_id         string   authoritative identity of the signer
contributor_id        uuid null -> contributors   (null only for REGISTER_KEY)
action_class          CONTROL | EPISTEMIC
action_type           string   (see 3.6)
payload               jsonb    (canonical form)
payload_hash          string   "sha256:…"
envelope              jsonb    (full signed client envelope, verbatim)
envelope_hash         string
signature             string   (base64url)
task_id               uuid null
task_packet_hash      string null
software              jsonb    {agent_name, version, model_provider, model_id, prompt_version} nullable
custody               string   SELF | SERVER | SYSTEM
redacted_by_seq       bigint null   (set by TAKEDOWN; payload/envelope bytes removed)
client_created_at     timestamptz   (claimed; informational only)
received_at           timestamptz   (authoritative)
prev_hash             string
entry_hash            string unique
server_signature      string
idempotency_key       string unique   sha256(signer_key_id | task_id | payload_hash)
```

Derived/cached (rebuildable): `current_status` in `PENDING | ACCEPTED | CHALLENGED | INVALIDATED | SUPERSEDED`.

#### `contributors`

```text
id
key_id              "ed25519:" + hex(sha256(public_key))
public_key          base64url
kind                HUMAN | AGENT | SYSTEM
display_name        nullable
identity_tier       PSEUDONYMOUS | ESTABLISHED | EXTERNALLY_VERIFIED | INSTITUTIONAL
encrypted_private_key  nullable (server-custodied human keys only; Active Record Encryption)
user_id             nullable -> users (Rails auth)
created_seq
revoked_seq         nullable
metadata            jsonb
```

There is no `UNSIGNED` tier: every contribution is signed. `identity_tier` never affects scores.

#### `agent_delegations`

```text
id
principal_contributor_id
delegate_contributor_id
permissions           jsonb   {allowed_task_types: [...], domains: [...]}
max_tasks_per_hour    int null
valid_from, valid_until
delegation_signature  (principal signs canonical delegation)
created_seq
revoked_seq           nullable
```

### 3.2 Sources

#### `sources`

```text
id
source_type        PRIMARY_TEXT | SECONDARY_TEXT | DATASET | MEASUREMENT | VIDEO | AUDIO
                   | WEBSITE | LEGAL_DOCUMENT | TESTIMONY | ARTIFACT | OTHER
title, creator, publisher nullable, publication_date nullable
canonical_uri      nullable
external_ids       jsonb
content_hash       "sha256:…" not null for stored content
retrieved_at       nullable
license            nullable
previous_version_id nullable -> sources    (content changed upstream)
lineage_key        nullable string  (suggested independence origin, e.g. "press-release:acme-2026-03-01")
metadata           jsonb
created_seq, invalidated_seq
```

Blob stored via Active Storage; `content_hash` is independent of the storage backend.

#### `source_locations`

```text
id
source_id
locator_type       CHAR_RANGE | PAGE | SECTION | LINE_RANGE | TIME_RANGE | OTHER
locator            jsonb    e.g. {"start": 0, "end": 104} or {"page": 12, "line_start": 3, "line_end": 7}
excerpt            text nullable
excerpt_hash       nullable
created_seq, invalidated_seq
```

Validation: for `CHAR_RANGE` on stored text, `excerpt` must equal the stored slice and `excerpt_hash` must match.

### 3.3 Claims and evidence

#### `claims`

```text
id
canonical_text     short, atomic
claim_type         one of 01 §4
truth_evaluable    boolean
not_evaluable_reason  nullable: NORMATIVE_OR_VALUE | METAPHYSICAL | RHETORICAL
                      | UNTESTABLE_CURRENT_METHODS | UNRESOLVED_FORECAST | NO_LEGAL_MODEL
                      (required when truth_evaluable is false; set by type default or by an
                       auditable SET_TRUTH_EVALUABLE contribution — constitution Art. VI)
qualifiers         jsonb   (time_range, location, population, denominator, source_edition, translation, …)
status             ACTIVE | SUPERSEDED | MERGED | RETIRED | QUARANTINED
superseded_by_id   nullable
merged_into_id     nullable
created_seq, invalidated_seq, accepted_seq
```

**Claim identity.** There is deliberately **no** uniqueness constraint on `canonical_text` (normalized or not). The same proposition can be phrased many ways, and small wording changes (a population, a date, a denominator) can change what evidence applies. Similarity search produces *candidate* relationships (`SAME_AS`, `NARROWS`, `BROADENS`, `QUALIFIES`) shown to a human; it never merges. `MERGE_CLAIMS` is an explicit, attributed, accepted contribution, and it is reversed by `INVALIDATE`ing that contribution. In v0.1 evidence does not flow across `SAME_AS` or `NARROWS` edges (no propagation); the claim page lists related claims and their assessments side by side.

`DISPUTED` is removed as a status: disputation is a score property (`contested`), not a lifecycle state.

#### `claim_edges`

```text
id, from_claim_id, to_claim_id
relationship_type   SUPPORTS | CONTRADICTS | QUALIFIES | REQUIRES | DERIVED_FROM | SAME_AS
                    | NARROWS | BROADENS | ALTERNATIVE_TO | PREDICTS | EXPLAINS
created_seq, invalidated_seq, accepted_seq
```

v0.1 stores and displays edges and uses them to compute `downstream_count` for task priority and audit policy. **Edges do not propagate probability in v0.1** (propagation needs cycle handling and a real model; see 09).

#### `independence_groups`

```text
id, group_type, description, created_seq, invalidated_seq, accepted_seq
```

`group_type`: `SAME_PRIMARY_TEXT | SAME_PRESS_RELEASE | SAME_DATASET | SAME_EXPERIMENT | SAME_WITNESS_CHAIN | SAME_PAPER_FAMILY | OTHER`.

#### `evidence_items`

```text
id
source_location_id
observation_type      DIRECT_TEXT | MEASUREMENT | DATASET_RESULT | ARCHAEOLOGICAL | EYEWITNESS
                      | HEARSAY | CALCULATION | EXPERT_ANALYSIS | MODEL_OUTPUT | OTHER
statement             text   (what is observed, in one sentence)
structured_value      jsonb nullable
independence_group_id nullable
assessment            jsonb   {"authenticity": "VERIFIED|UNVERIFIED|DOUBTFUL", "extraction": "VERIFIED|UNVERIFIED"}
created_seq, invalidated_seq
```

Independence group assignment is its own contribution type (`ASSIGN_INDEPENDENCE_GROUP`) so it can be audited separately. Evidence with no group is treated as its own singleton group **and** is counted in the trace as `independence_unreviewed`.

#### `evidence_claim_links`

```text
id, evidence_item_id, claim_id
direction           SUPPORT | CONTRADICT | QUALIFY | NEUTRAL
relevance_strength  DIRECT | STRONG | MODERATE | WEAK | CONTEXT_ONLY
interpretive_steps  smallint 0..5
note                text nullable  (display only; never fed to scoring or to other agents' prompts)
created_seq, invalidated_seq, accepted_seq
```

### 3.4 Audits, reputation, tasks

#### `audits`

```text
id
target_contribution_id
auditor_contributor_id
audit_type          SOURCE_CHECK | SCHEMA_CHECK | INDEPENDENCE_CHECK | RE_AUDIT
result              CONFIRMED | MINOR_ERROR | SUBSTANTIVE_ERROR | FABRICATION | UNRESOLVED
effort_seconds      int null      (self-reported by auditor; used only for audit-cost reporting, 09 §1)
task_type, domain   (copied from the target's task for reputation bucketing;
                     contributions made outside a task use task_type MANUAL and domain general)
created_seq, invalidated_seq
```

An audit may target another audit's contribution (`RE_AUDIT`). The latest active audit on a target governs its effect.

#### `audit_schedules`

```text
id
contribution_id          unique
evaluated_at_seq         the target contribution's own seq
policy_version
inputs                   jsonb  {n, mean, downstream_count, outcome_is_unusual, …} as of evaluated_at_seq
audit_probability        decimal string
sampled                  boolean
```

Written when a contribution is appended. The inputs are a function of the log at `evaluated_at_seq` only, so they can be recomputed and checked, but storing them makes the decision inspectable without replay and immune to later graph changes.

#### `reputation_events`

```text
id, contributor_id, principal_contributor_id nullable
task_type, domain
audit_id
alpha_delta  numeric(6,2)
beta_delta   numeric(6,2)
created_seq, invalidated_seq
```

Current reputation is computed from active events at a snapshot; nothing stores a mutable total.

#### `tasks`

```text
id
task_type
target_type, target_id
domain
priority            numeric (cached; see 04 §7)
required_assignments  int default 1   (independent verifications)
status              OPEN | LEASED | COMPLETE | EXPIRED | CANCELLED
packet              jsonb    (canonical packet, server-signed)
packet_hash
issued_seq
```

#### `task_assignments`

```text
id, task_id, contributor_id
lease_expires_at
result_contribution_id nullable
status   LEASED | SUBMITTED | EXPIRED | RELEASED
```

Unique on `(task_id, contributor_id)`; also unique per `(task_id, principal)` so one principal cannot fill every independent slot with its own agents.

### 3.5 Scoring and snapshots

#### `scoring_models`

```text
id, name, semantic_version
config            jsonb   (exactly the contents of scoring-config-vX.json)
config_hash
code_hash         (sha256 of the scorer source files, computed at release)
release_signature
created_at
```

#### `graph_snapshots`

```text
id, seq, entry_hash, label nullable, created_at
```

A snapshot is just a pinned `(seq, entry_hash)`. Merkle trees are unnecessary: the chain head commits to the whole prefix.

#### `claim_scores` (cache only — delete freely)

```text
claim_id, snapshot_seq, scoring_model_id
assessment_state, probability numeric(5,4) null, review_coverage numeric(3,2)
stability, support_groups, contradict_groups, contested, provisional
trace jsonb, trace_hash
computed_at
unique (claim_id, snapshot_seq, scoring_model_id)
```

#### `summaries` (cache only)

```text
id, claim_id, snapshot_seq, summary_type SHORT|STANDARD
input_hash, generator ("stub-v0.1" or provider/model), sentences jsonb, created_at
```

A summary is stale when a newer snapshot changes its `input_hash`; no mutable `stale` flag.

### 3.6a Personal assessments (P1 — reserved, do not build in P0)

Constitution Article XV separates shared epistemic state from personal belief. Personal lenses therefore live **outside** the contribution log and never feed `Ledger::Apply`, scoring, packets, or summaries.

```text
personal_assessments
  id, user_id, claim_id
  lens            jsonb   {"model": "ledger-default@0.1.0", "prior_override": "0.20", "excluded_links": [...]}
  personal_probability  string nullable   (computed by the scorer with the lens, or entered by hand)
  rationale       text
  cites           jsonb   (graph IDs)
  visibility      PRIVATE | PUBLIC
  created_at, updated_at
```

A PUBLIC personal assessment is displayed as "Alice's view," never merged into or averaged with shared assessments, and never counted as evidence.

### 3.6 Contribution action types (P0)

```text
CREATE_SOURCE              CREATE_SOURCE_LOCATION
CREATE_CLAIM               SUPERSEDE_CLAIM          SET_TRUTH_EVALUABLE
CREATE_EVIDENCE            LINK_EVIDENCE            CREATE_CLAIM_EDGE
CREATE_INDEPENDENCE_GROUP  ASSIGN_INDEPENDENCE_GROUP
SUPERSEDE_LINK             MERGE_CLAIMS
TASK_RESULT                (payload contains one of the above as ops; see 04 §4)
ACCEPT                     INVALIDATE               AUDIT
REGISTER_KEY               DELEGATE                 REVOKE_KEY          REVOKE_DELEGATION
QUARANTINE                 RELEASE_QUARANTINE       TAKEDOWN
RELEASE_SCORING_MODEL      AMEND_CONSTITUTION
```

One contribution = one action type. `TASK_RESULT` may carry an ordered list of ops (max 20) applied atomically.

---

## 4. Claim Atomicity

Reject or split claims containing multiple independently evaluable propositions.

Bad:

> Acme's survey shows remote workers are more productive and happier and save two hours a day, so companies should adopt remote work.

Better:

- Acme's 2026 survey reports that 62% of respondents said their productivity was higher when remote. (`TEXTUAL`)
- Acme's 2026 survey reports that respondents said they were happier when remote. (`TEXTUAL`)
- Acme's 2026 survey reports that respondents saved an average of two hours a day when remote. (`TEXTUAL`)
- Remote work causes higher productivity. (`CAUSAL`)
- Companies should adopt remote work. (`NORMATIVE`)

Note what the split exposes: "the survey shows" becomes three textual claims about the survey, the causal link is a separate claim with its own (much weaker) evidence, and the recommendation is a value judgment.

(The Watchers stress test contains a second, textual example of atomicity.)

POC validation is heuristic (warn on coordinating conjunctions joining verb phrases, multiple finite verbs, >25 words) plus human confirmation in the UI. It is a warning, not a hard block.

---

## 5. Append-Only Semantics

- Never hard-delete contributions. The only exception is a legally compelled removal, performed by a signed `TAKEDOWN` contribution stating its date, legal basis, and a **redaction manifest** (which fields of which projection rows are removed).
- The target's `payload`, `envelope`, and any blob are physically deleted; `payload_hash`, `envelope_hash`, `entry_hash`, and `server_signature` remain, so the **chain** still verifies. The target's client signature can no longer be checked, because the signed bytes are gone.
- `ledger:verify` then reports `CHAIN_VERIFIED_WITH_REDACTIONS` and lists redacted seqs.
- `ledger:replay` applies redacted entries from their redaction manifest, producing rows with the removed fields nulled. Replay equivalence is checked against the redacted projection. Score traces for snapshots before the takedown are reproduced where they depended only on unredacted fields (traces use enums and IDs, so this is the common case); any that cannot be reproduced are reported as `UNREPRODUCIBLE_REDACTED`, never silently changed.
- The removal itself stays publicly visible (constitution Art. XII, XIII).
- Corrections are new contributions (`INVALIDATE`, `SUPERSEDE_CLAIM`, a new `LINK_EVIDENCE`).
- A database role used by the app has no `DELETE`/`UPDATE` grant on `contributions` except for the cached `current_status` column.

---

## 6. Content Addressing

SHA-256, prefixed `sha256:`, over RFC 8785 (JCS) canonical JSON for structured data and raw bytes for blobs. Hash: source content, excerpts, task packets, client envelopes, log entries, scoring configs, scorer code, score traces.
