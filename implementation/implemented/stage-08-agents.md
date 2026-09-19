# Stage 8 — Tasks, leases, packets, and the example agent

**Status:** implemented · tag `stage-08-agents` · decisions recorded 2026-09-17

## Plan

**Tag:** `stage-08-agents` · **Spec:** 04 (all), 02 §3.4 (`tasks`, `task_assignments`), 06 §2 tasks endpoints, 10 "Required Artifacts" (schemas, examples/agent)

Goal: an external agent can lease a signed packet, return a signed result, and have it
validated server-side, logged, accepted, scheduled for audit, and scored.

Deliverables:

- Tables `tasks` and `task_assignments` per 02 §3.4, unique per `(task, contributor)` and
  per `(task, principal)`.
- `schemas/eir-task-v1.json` and `schemas/eir-result-v1.json`; validation with
  `json_schemer`; schema URLs in `/api/v1/meta`.
- `Tasks::BuildContext` (04 §5): deterministic, no LLM, per-type include/exclude table,
  token budget, excerpt cap, contributor notes never included. `Tasks::Lease` (04 §7):
  2-hour default, per-type configurable, priority ordering, delegation filtering,
  per-delegate daily limit, `ExpireLeasesJob`.
- Server-signed packets; `task_packet_hash` over the packet without `server_signature`.
- `Contributions::ValidateTaskResult`: the nine-step pipeline of 04 §6 returning 422 with
  the error list and creating no contribution on failure; ops with `ref` handles; max 20
  ops applied atomically; automated acceptance rules per task type (02 §1.1a);
  `EVIDENCE_VERIFICATION` evidence must reference the packet's location; new external
  sources stored metadata-only with `retrieval_pending`; no server-side URL fetching.
- Blind multi-assignment (04 §3.1): results hidden until all slots submit or expire.
- Task creation: `Tasks::Create` for the five P0 types, callable from the UI flow (Stage
  10) and from seeds; "create verification tasks" for a source's claims.
- Endpoints: `POST /api/v1/tasks/next?types=&domains=`, `GET /api/v1/tasks/:id`,
  `POST /api/v1/tasks/:id/release`.
- `examples/agent/`: single-file Ruby client with no Rails dependency (`lease_next`,
  `verify_packet!`, `submit`), `fixtures.json` mapping seeded tasks to deterministic
  answers, and a README. Canonicalization vector included so third-party clients can
  confirm identical hashing.

Acceptance (07 Phase 5):

1. The example client leases, verifies the packet signature, runs the fixture verifier,
   signs, submits, and a `TASK_RESULT` plus `ACCEPT` appear in the log (#1).
2. Expired lease, wrong packet hash, and disallowed op each return 422 and create nothing (#2).
3. Two agents under one principal cannot both hold slots on one task (#3).
4. Packets never contain contributor notes: seed a note with an injection string and
   assert absence (#4).
5. Same task inputs produce identical packet bytes excluding timestamps and signature (#5).
6. A `QUALIFIER_CHECK` result superseding another principal's links stays uncounted until
   a different principal accepts it (#6).
7. `opposing_search_done` and `qualifiers_reviewed` checklist items now flip from real
   accepted task results.
8. Constitutional Test answers recorded.

## Decision Log (2026-09-17)

- `tasks` and `task_assignments` per `02 §3.4` are operational tables, not projections:
  task creation is not an action in the closed list, so replay leaves them alone.
  Consequence for mirrors: `GET /log` alone does not carry task targets, so
  task-derived review checks need the task registry (`GET /tasks/:id` is public).
  Recorded for the owner as a gap in log self-containment.
- **One signed packet per task**, built by `Tasks::BuildContext` at creation and shared
  by every assignee, so blind multi-assignment (`04 §3.1`) means literally identical
  packets. `lease_expires_at` therefore lives on the assignment (returned beside the
  packet) rather than inside it, a deviation from the `04 §3` example that keeps one
  `task_packet_hash` per task. Packets are byte-identical apart from `task_id`,
  `issued_at`, and the signature; contributor notes never enter them; excerpts are
  labelled untrusted and capped at 2,000 characters. Qualifier packets carry up to five
  trigram-near claims as `candidate_claims` so an agent can propose a NARROWS edge
  without seeing the graph.
- Leasing (`04 §7`) and releasing are signed `eir-lease-v1` requests (same shape as
  admin requests). Selection: OPEN or partly leased tasks by priority, filtered by the
  delegation's task types and domains, never a task already held by the same
  contributor or principal (two unique indexes), per-delegate daily limits,
  per-type lease lengths from `Tasks::Types`. `ExpireLeasesJob` and every lease call
  expire stale leases. Task reads hide results until the task is closed: all slots
  submitted, or leases expired with none live; an unleased slot keeps it blind. The
  public log itself is not blind, which `04 §3.1` cannot fully achieve on a
  transparency log; recorded.
- `TASK_RESULT` arrives as `eir-result-v1` (`contributor_key_id` maps to the
  `signer_key_id` column), validated against `schemas/eir-result-v1.json` with
  json_schemer, then by the `04 §6` pipeline: task and lease, packet hash, delegation
  permits type and domain, outcome in the type's list, ops in `allowed_ops` and under
  `max_ops`, refs declared before use, and type-scope rules (verification evidence on
  the packet's location and linking the packet's claim; independence assignments only
  on the packet's counted evidence; qualifier links QUALIFY or CONTRADICT; supersessions
  only of the packet's counted links). **Per-op semantic checks run inside the append
  transaction after refs resolve**; a rejection rolls the whole append back, so
  nothing is logged and no seq is consumed. Rows get ids derived from the contribution
  and the op index.
- Agent sources inside a task are metadata-only (`retrieval_pending`, no content or
  content hash accepted), so the server never fetches an agent-supplied URL (`04 §6`
  step 9); CHAR_RANGE locations are refused on such sources until content is imported.
- Acceptance of results (`02 §1.1a`): verification, search, independence, and qualifier
  results that only add objects are accepted by the system; extraction results and any
  result that supersedes another principal's link or claim stay pending for a different
  principal, as one contribution. Per-claim acceptance of an extraction (04 §4.3 "each")
  would need row-level ACCEPT, which `02 §1.1a` does not define; acceptance is per result.
- `Tasks::Checks` now derives the three task-based review checks from accepted, not
  invalidated results (via `Contributions::Standing` over ACCEPT/INVALIDATE entries), and
  `Audits::Status` uses the opposing-search check for the highest-impact band. Audits of
  task results are bucketed by the task's type and domain.
- The example agent (`examples/agent/agent.rb`) is one file over Ruby's standard library
  with its own RFC 8785 subset canonicalizer (no floats, UTF-16 key order), key
  generation, registration, leasing, packet verification against `/meta`, fixture-driven
  behaviours, signing, and submission. The spec exercises it in-process through a Rack
  transport and checks its canonicalizer against the published vectors.
- The demo builders now run T0–T4 as leased tasks answered by result envelopes, and the
  end-to-end golden check compares every field: `DemoGraphs::DEFERRED_GOLDEN_FIELDS` is
  empty.
- Constitutional Test (agents as contributors): 1 yes, every result is signed, scoped,
  and attributed with software metadata; 2 unchanged; 3 no, packets are server-signed
  and validation is server-side; 4 no; 5 yes, NONE_FOUND and CANNOT_DETERMINE are valid
  outcomes; 6 yes, packets are deterministic; 7 yes; 8 yes; 9 n/a; 10 yes.
- Acceptance: 07 Phase 5 #1–#6 have specs in `spec/services/tasks/tasks_spec.rb`;
  `bundle exec rspec`, RuboCop, and Brakeman pass.
