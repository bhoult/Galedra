# Stage 5 — Deterministic scoring

**Status:** implemented · tag `stage-05-scoring` · decisions recorded 2026-09-17

## Plan

**Tag:** `stage-05-scoring` · **Spec:** 03 (all), 05 §14, 08 §8, examples/watchers §7, reference/reference_scorer.py, both scoring configs

Goal: `Scoring::Calculate` implements 03 §4 exactly for both released models and
reproduces every golden value as a pure function of serialized inputs. No cache, no
snapshots, no endpoints yet.

Deliverables:

- `config/scoring/ledger-default-0.1.0.json` and `config/scoring/ledger-strict-0.1.0.json`
  as byte-identical copies of the spec configs, with a test asserting equality.
- `scoring_models` table and `Scoring::Registry`: load configs, validate exhaustively (a
  missing enum key is a release error), compute `config_hash` and `code_hash` over
  `app/services/scoring/**/*.rb`, reject a model whose `review_checklist` names a check
  no P0 task type can satisfy.
- `RELEASE_SCORING_MODEL` control action and applier; `ledger:release_models` task that
  releases both P0 models signed by the system key.
- `Scoring::Calculate.call(input) -> trace` where `input` is the serializable structure in
  11 §12. Steps 0–5 of 03 §4 with `BigDecimal`, half-even rounding at 6/4/2 places,
  strongest-only per `(group_key, sign)` with the specified tie-break, directional states
  requiring matching groups, `INSUFFICIENT_EVIDENCE` and `NOT_APPLICABLE` with null
  probability and `not_applicable_reason`.
- `Scoring::Checklist` (03 §8), `Scoring::Stability` (03 §9), `Scoring::Trace` (03 §10
  shape, canonical JSON, `trace_hash`, `rounding_boundary` flag), `Scoring::Compare`
  (diff of two traces: differing effective weights, responsible config keys, state change).
- Golden fixtures: every row of 08 §8 and Watchers §7, for both models, expressed as
  scorer inputs (mirroring the Python reference's case tables) with expected outputs.
- Task priority heuristic `Tasks::Priority` (03 §14) as a pure function, tested.

Acceptance (07 Phase 3, the parts that do not need snapshots):

1. Every golden row reproduces exactly for both models (#1, pure-scorer form).
2. A config with a missing enum key is rejected at release (#3).
3. Changing scorer code without bumping the version fails the `code_hash` test (#4).
4. `NOT_APPLICABLE` and `INSUFFICIENT_EVIDENCE` never carry a probability (#5).
5. Strongest-only suppression is per group and direction and visible in the trace (#6).
6. Releasing `ledger-strict` changes no `ledger-default` trace (#7).
7. Every `NOT_APPLICABLE` result carries a `not_applicable_reason` (#8).
8. A claim with only supporting evidence never receives a contradicted state (#9).
9. A model declaring an unsatisfiable check is rejected (#10).
10. `rounding_boundary` is set when a value lies within the guard (#11, unit form).
11. Constitutional Test answers recorded.

## Decision Log (2026-09-17)

- `Scoring::Calculate` implements `03 §4` Steps 0–5, `03 §8` (checklist), `03 §9`
  (stability), and `03 §10` (trace) as a pure function of the `11 §12` input and a model
  config. `BigDecimal` throughout; half-even rounding at 6 (weights), 4 (probability),
  2 (coverage); decimals serialized as fixed-place strings; `ln` and `exp` via
  `BigMath` at 40 digits, then rounded.
- **Golden fixture generated from the spec's reference scorer.**
  `spec/fixtures/gen_scoring_golden.py` imports `reference/reference_scorer.py` and emits
  every row of `08 §8` and Watchers `§7` for both models (20 cases, 40 expectations) as
  scorer inputs with expected outputs, so the Ruby scorer is checked against an
  independent implementation. Fixture link ids are zero-padded (`L03`) so string order
  equals the reference's integer order; `contested` and `provisional` expectations come
  from the golden tables' flags, with the unaudited links (`L10`, Watchers `L2`, `L5`)
  marked `audit_confirmed: false` at the checkpoints where the tables say `provisional`.
- Input shape: `claim {id, type, truth_evaluable, not_evaluable_reason}`, `snapshot_seq`,
  `links [{id, evidence_id, direction, relevance_strength, interpretive_steps,
  audit_confirmed, evidence {observation_type, independence_group_id, source_type,
  assessment}}]`, `task_checks [{check, by}]`. Stage 6 builds it from the graph;
  Stage 7 supplies `audit_confirmed`; Stage 8 supplies task checks. `provisional` is
  true when any counted link's contribution lacks a confirming audit.
- `independence_unreviewed` counts distinct counted evidence items without a group;
  the reference counts links, and the two agree on every golden row.
- `rounding_boundary` applies the absolute guard (1e-6) to the 4-place probability and
  its two variants only. At 6 places an absolute 1e-6 guard equals a whole unit and
  would flag every value; the 6-place prior log-odds is a per-type constant every
  implementation can pin. Recorded as an interpretation of `03 §10`.
- The trace carries `code_hash` alongside `config_hash` (03 §1: a probability is never
  shown without both), plus per-link authenticity, extraction, source type, and audit
  state. Golden tests compare output fields, not trace hashes, so a scorer refactor
  changes `code_hash` without invalidating the goldens.
- `Scoring::Registry` validates configs exhaustively (`03 §4` Step 2: a missing enum
  key is a release error), requires every declared review check to be satisfiable by a
  P0 task type (`03 §8`), hashes `app/services/scoring/**/*.rb` for `code_hash`, and
  exposes `verify_code_hash!` so a code change without a new version fails.
  `RELEASE_SCORING_MODEL` is signed only by the system key and rejects a stale
  `code_hash`, a wrong `config_hash`, an invalid config, or a duplicate version.
  `bin/rails ledger:release_models` releases every `config/scoring/*.json` not yet
  released. `scoring_models` carries `released_seq` instead of the spec's `created_at`
  so replay reproduces it.
- `Scoring::Compare` reports the config-key paths that differ, the links whose
  effective weights differ with the responsible keys, and any state change; an
  applicability change names `scored_types` (07 scenario H).
- `Tasks::Priority` implements `03 §14` as a pure function with `BigDecimal`.
- Constitutional Test (scoring): 1 unchanged; 2 yes, two models and `/compare`
  localize disagreement to config keys; 3 no, the scorer is open code with published
  hashes; 4 no, reputation is not an input; 5 yes, null probabilities and directional
  states requiring evidence; 6 yes, byte-identical traces and cross-implementation
  goldens; 7 yes; 8 yes, traces cite snapshot and model; 9 n/a; 10 yes.
- Acceptance: 07 Phase 3 #1 (pure-scorer form), #3–#11 have specs in
  `spec/services/scoring/` and `spec/services/tasks/`; `bundle exec rspec`, RuboCop,
  and Brakeman pass; the reference scorer still prints ALL PASS.
