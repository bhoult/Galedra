# 11 — Rails Architecture and Low-Cost Scaling

This is the **single home** for the stack rationale and the runtime/extraction policy. Other files refer here instead of repeating it.

## 1. Decision

Build the POC as a Rails 8.x monolith.

Not because Ruby is fast, but because the epistemic domain model will change repeatedly as real evidence graphs expose weaknesses, and the founder has deep Rails experience. AI can generate code in any language; familiarity still decides how quickly bad abstractions, broken migrations, and subtle bugs get noticed.

---

## 2. Topology

```text
            Browser / agents
                   |
                Rails 8.x
     +-------------+-------------+
     |             |             |
  Hotwire     REST /api/v1   Solid Queue
     |             |             |
     +-------------+-------------+
                   |
             PostgreSQL 16+
      (app data, Solid Queue, Solid Cache)
                   |
             Active Storage
            (local disk in POC)
```

Two containers in development: `app` (web + `bin/jobs` via Procfile or a second service) and `db`. Nothing else.

---

## 3. Distributed Research, Centralized Coordination

```text
                 Ledger (Rails)
                       |
             server-signed task packet
                       |
      +----------------+----------------+
      |                |                |
 local-model agent  API-funded agent  volunteer agent
      |                |                |
      +----------------+----------------+
                       |
             client-signed result
                       |
        validation → log → projections → scores
```

Inference runs on contributors' hardware or accounts. The server does cheap, deterministic work: validation, hashing, signature checks, projection, scoring, serving pages. Target growth pattern: research throughput grows fast; central cost grows slowly.

---

## 4. Service Objects, Not Callbacks

Avoid:

```ruby
class EvidenceClaimLink < ApplicationRecord
  after_save :recompute_everything
end
```

Prefer:

```ruby
entry = Ledger::Append.call(envelope)        # verify, lock, seq, hash, persist
Ledger::Apply.call(entry)                    # projections only
Scoring::RecomputeAffectedJob.perform_later(entry.seq)
Summaries::InvalidateAffected.call(entry)    # no-op in practice: summaries are keyed by input_hash
```

Explicit, testable, replayable, and extractable.

---

## 5. Layout

```text
app/models/
  contribution.rb  contributor.rb  agent_delegation.rb
  source.rb  source_location.rb  claim.rb  claim_edge.rb
  evidence_item.rb  evidence_claim_link.rb  independence_group.rb
  audit.rb  reputation_event.rb
  task.rb  task_assignment.rb
  scoring_model.rb  graph_snapshot.rb  claim_score.rb  summary.rb
  concerns/projection.rb          # validity windows, active_at(seq), readonly outside Apply

app/services/
  crypto/          canonical_json.rb  hashing.rb  ed25519.rb  custody.rb
  ledger/          append.rb  apply.rb  appliers/*.rb  replay.rb  verify.rb
  contributions/   validate_envelope.rb  validate_task_result.rb
  scoring/         calculate.rb  checklist.rb  stability.rb  trace.rb  registry.rb  compare.rb
  audits/          sample.rb  apply_result.rb  eligibility.rb
  reputation/      calculate.rb
  tasks/           build_context.rb  lease.rb  priority.rb
  snapshots/       create.rb  digest.rb
  summaries/       stub_generator.rb  validator.rb
  weaknesses/      report.rb
  cards/           claim_card.rb  source_card.rb  main_issue.rb
  governance/      constitution.rb (hash, version)  moderation_log.rb
  llm/             adapter.rb  stub_adapter.rb

app/jobs/
  recompute_affected_scores_job.rb  schedule_audit_job.rb
  generate_summary_job.rb  expire_leases_job.rb  create_snapshot_job.rb

app/controllers/api/v1/…            thin; delegate to services
lib/tasks/ledger.rake               ledger:verify, ledger:replay
examples/agent/                     standalone client, no Rails dependency
```

`Projection` concern (sketch):

```ruby
module Projection
  extend ActiveSupport::Concern
  included do
    scope :active_at, ->(seq) {
      where(created_seq: ..seq).where("invalidated_seq IS NULL OR invalidated_seq > ?", seq)
    }
  end
  def readonly? = !Ledger.applying? || super
end
```

---

## 6. PostgreSQL

No graph database. Recursive CTEs, indexed edge tables, JSONB, full-text search, and `pg_trgm` are enough for the POC and likely well beyond.

Indexes to create up front:

```text
contributions(seq) unique, contributions(entry_hash) unique, contributions(idempotency_key) unique
contributions(contributor_id, seq)
<every projection>(created_seq), (invalidated_seq)
evidence_claim_links(claim_id, created_seq), (evidence_item_id)
claim_edges(from_claim_id), (to_claim_id)
audits(target_contribution_id)
reputation_events(contributor_id, task_type, domain)
tasks(status, priority desc)
task_assignments(task_id, contributor_id) unique
claim_scores(claim_id, snapshot_seq, scoring_model_id) unique
claims using gin (to_tsvector('english', canonical_text))
```

Add pgvector (and its index) only in P1, and only if trigram dedup proves inadequate.

---

## 7. Background Jobs

Solid Queue (Postgres-backed). Jobs are idempotent and keyed by `(target_id, seq)` so a retry or a replay never double-applies. Recompute is incremental: only claims whose counted links, evidence, or groups changed at that seq.

## 8. Active Storage

Local disk in POC; S3-compatible later. `sources.content_hash` is the identity of the content; the blob key is not. Moving storage providers must not change any hash.

## 9. Caching

Solid Cache or memory store. The real caches are explicit rows (`claim_scores`, `summaries`) that can be deleted at any time and regenerated. No Redis.

## 10. Suggested Gems (verify current versions; record in IMPLEMENTATION.md)

| Need | Candidate |
|---|---|
| Ed25519 | `ed25519` (or OpenSSL 3 via Ruby `openssl`) |
| RFC 8785 canonical JSON | `json-canonicalization` |
| JSON Schema validation | `json_schemer` |
| UUIDv7 | Postgres function or a small gem; document choice |
| Auth | Rails 8 authentication generator |
| Rate limiting | Rails 8 `rate_limit` |

Avoid pulling in event-sourcing frameworks; the log here is small enough to own.

---

## 11. Performance Boundaries (likely future hotspots)

- Scoring and recompute fan-out — first candidate for extraction.
- Bulk source ingestion — Go or Rust worker if ever needed.
- Semantic dedup — likely stays in Postgres.
- Signature verification — Ruby is fine until contribution volume is very high.
- Task scheduling — stays in Rails until measured otherwise.

## 12. Extraction Contract and Policy

Scoring's boundary is already serializable:

```text
input:
{"claim": {"id": "…", "type": "TEXTUAL", "truth_evaluable": true},
 "snapshot_seq": 212, "model": "ledger-default@0.1.0",
 "links": [ … counted links with evidence observation, group, source type … ],
 "task_checks": ["opposing_search_done"]}
output: the trace object in 03 §10
```

A Go (or any) implementation must produce identical canonical traces on the golden fixtures and shared regression corpus, with `rounding_boundary` flags handled as in 03 §10. `reference/reference_scorer.py` shows this is achievable with decimal weights and fixed rounding; bit-identical transcendental math across languages is not assumed.

**Do not extract** because compiled languages feel serious, the project might be big someday, AI makes rewrites cheap, or microservices are fashionable.

**Consider extraction only when profiling shows** sustained CPU saturation, unacceptable recompute latency, memory pressure, verification throughput limits, or ingestion bottlenecks — and the hosting or latency savings exceed the cost of running another service. Benchmark the replacement against the golden and replay tests before switching.

## 13. Go vs. Rust (if ever)

- **Go:** scoring and recompute workers, task scheduling, batch signature verification, bulk JSON — service-shaped, concurrent, database-heavy work.
- **Rust:** CPU-bound or untrusted binary parsing where memory safety and throughput justify the complexity.

There is no requirement that either is ever introduced.

## 14. Operational Goal

One modest VM plus PostgreSQL (managed or local) should serve the early hosted system. Grow by pushing research compute outward before scaling anything central.
