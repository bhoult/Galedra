# Epistemic Ledger POC

> **Start with `12-constitution.md`.** It states what the project is and outranks every other file here. This README and files 01–11 describe how the POC realizes it; `13-constitutional-compliance.md` shows where that realization is complete, partial, or knowingly missing.

## Purpose

Build a small but credible proof of concept for an **open, cumulative, machine-readable evidence ledger** where humans and AI agents contribute atomic claims, evidence, provenance, audits, and structured reasoning.

The system is not a source of truth. It is a **source of traceable reasons for believing or doubting claims**.

Central design goal:

> Every claim assessment must be reproducible from (a) the contribution log up to a snapshot sequence number and (b) a versioned scoring model. AI agents may gather, normalize, verify, challenge, and summarize, but they are never the final opaque authority.

The POC prioritizes correctness, auditability, and simplicity over scale and breadth.

**Product bet (v4).** The POC does not bet on becoming a public truth network. It bets on something smaller: *AI agents increasingly do research that is expensive to repeat and hard to audit; a durable, signed, reusable evidence record makes that work cumulative.* P0 must be useful to one person or team with no other contributors — starting with verifying citations and statistics in AI-generated documents. A public evidence graph may grow out of that use later (01 §1.1).

---

## Core Principles (implementation summary — the constitution is authoritative)

1. **Store claims, not truth.** Nothing enters the system as an unquestioned fact.
2. **Evidence and conclusions are different objects.** A passage is evidence; "this passage supports X" is a separate, attributable link.
3. **Provenance is mandatory.** Every evidence item points to an exact source location and a signed contribution.
4. **Contradictions coexist.** Conflicting evidence is preserved, not overwritten.
5. **The log is the source of record.** All epistemic state is a projection of an append-only, hash-chained contribution log and can be rebuilt by replay (with explicit, visible exceptions for legally compelled redactions).
6. **Scoring is deterministic and replaceable.** Same implementation + snapshot + model version = byte-identical result; other implementations must match canonical outputs on shared fixtures. Models are interpretations; the log is durable.
7. **Confidence is not coverage.** "0.86 under model M" and "we have checked 1 of 4 review items" are separate outputs.
8. **"Unknown" is a first-class result.** Claims without counted evidence show `INSUFFICIENT_EVIDENCE`, not the prior.
9. **Agents are contributors, not arbiters.** AI output is attributable, reviewable, and never self-certified.
10. **Reputation measures audited task reliability, not authority.** It is task- and domain-specific and, in v0.1, does not enter claim scores at all.
11. **Identity does not substitute for evidence.**
12. **Append, do not erase.** Corrections invalidate or supersede; history stays addressable.
13. **Minimize task context.** Volunteer agents receive the smallest sufficient packet.
14. **Prefer boring infrastructure.** One Rails app, one PostgreSQL database.
15. **Determinism is not objectivity.** Relevance labels, interpretive steps, independence groupings, and claim wording are judgments. The system makes them explicit, attributed, challengeable, versioned, and auditable — it does not pretend they are objective.
16. **Answers first, graphs underneath.** Most users should see a compact, cited answer; the graph and the number are one click away.

---

## Stack (summary)

Rails 8.x monolith, PostgreSQL 16+, Solid Queue, Active Storage (local disk), Hotwire, REST/JSON, Ed25519 signatures, SHA-256 over RFC 8785 canonical JSON, Docker Compose for local development. LLM features are optional and stubbed by default.

Full rationale, gem choices, and the runtime/extraction policy live in **`11-rails-architecture.md`** and nowhere else.

---

## Reading Order

An AI coding agent should read these in order:

| # | File | What it settles |
|---|------|-----------------|
| 12 | `12-constitution.md` | **Read first.** Binding principles; precedence over all files |
| 01 | `01-product-and-scope.md` | Problem, use cases, **scope tiers (P0/P1/deferred)** |
| 02 | `02-domain-model.md` | Contribution log, projections, tables |
| 03 | `03-scoring-and-uncertainty.md` | The exact v0.1 scoring algorithm |
| 04 | `04-agent-protocol.md` | Task packets, leases, results |
| 05 | `05-identity-reputation-and-security.md` | Keys, custody, audits, reputation, threats |
| 06 | `06-api-and-ui.md` | Endpoints and display rules |
| 07 | `07-poc-roadmap-and-acceptance.md` | Phases, acceptance tests |
| 08 | `08-seeded-example.md` | **Public demo** (AI memo with a viral statistic and a fake citation) with golden values |
| 09 | `09-future-directions.md` | Deferred work (do not build) |
| 10 | `10-agent-handoff.md` | Invariants and working rules for the coding agent |
| 11 | `11-rails-architecture.md` | Rails layout, gems, extraction policy |
| 13 | `13-constitutional-compliance.md` | Article-by-article implementation status and known gaps |

`examples/watchers/README.md` is an internal stress test (textual source, interpretation, unusual hypothesis) with its own golden values. It is deliberately not the first thing outsiders see.

`scoring-config-v0.1.json` and `scoring-config-strict-v0.1.json` are the authoritative configs for the two P0 scoring models (03 §13).

`CONSTITUTION-AMENDMENTS.md` is the append-only amendment log, including four proposed amendments awaiting the project owner's decision.

`reference/reference_scorer.py` is an independent Python implementation of the 03 algorithm that reproduces the golden values of both demos (`python3 reference/reference_scorer.py`). It is a cross-check, not code to port.

`FULL-SPEC.md` is **generated** by `build-full-spec.sh`; never edit it by hand. Agents should read either the numbered files or `FULL-SPEC.md`, not both.

`REVIEW-NOTES.md` records why this revision differs from the previous draft. It is not needed for implementation.

---

## Conventions Used Across All Files

- **Names are canonical.** The score fields are `probability`, `assessment_state`, `review_coverage`, `stability`, `support_groups`, `contradict_groups`. Do not introduce synonyms (`truth_score`, `belief_probability`, etc.).
- **IDs.** Database primary keys are UUIDv7. Human-facing handles in examples (`C1`, `E4`, `SNAP-12`) are illustrative display handles only.
- **Snapshots** are identified by a log sequence number (`seq`), not a timestamp.
- **Enums** are UPPER_SNAKE_CASE strings, validated against a closed list.
- **No floats in signed payloads.** Use enums, integers, or decimal strings.

---

## POC Definition of Done (P0)

A user can:

1. import a source and mark an exact location;
2. create atomic claims and attach evidence with support/contradict/qualify links;
3. have every write recorded as a signed contribution in the hash-chained log;
4. paste an AI-drafted paragraph, see its claims extracted, and get a compact cited answer card for each — with the score, trace, and review checks one click away;
5. request a task packet, run the example agent, and submit a signed result;
6. audit a prior contribution and see it invalidated and the score recomputed;
7. switch between the two scoring models and see where and why they differ;
8. open the Weaknesses page and the public moderation log;
9. see task/domain reputation change and reproduce it from audit history;
10. view a short generated (or stubbed) summary whose every sentence cites graph IDs;
11. pick an old snapshot `seq` and reproduce its scores byte-for-byte;
12. **drop all projection tables, replay the log, and get the same snapshot hashes and scores.**

`bin/demo` must demonstrate all of these in under 10 minutes of reading, using the public demo (08).

After P0: run the five experiments in 07 ("First Experiments") before expanding scope.

---

## Working Name

`Epistemic Ledger`. Do not spend time on branding.
