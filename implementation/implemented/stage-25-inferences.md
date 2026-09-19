# Stage 25 — Inferences: recorded reasoning steps

**Status:** implemented · tag `stage-25-inferences` · decisions recorded 2026-09-19

## Plan

**Tag:** `stage-25-inferences` · **Spec:** 09 §1 (inferences and premises tables,
deferred; `CREATE_INFERENCE` reserved), 09 §8 (higher-order argument graph), 02 §3.3
(`claim_edges`: pairwise, no propagation), 03 (scoring; propagation is not in v0.1),
Article III (evidence and interpretation are distinct), Article V (contradiction is
preserved), Article VII (probabilities are model-conditional), Article XVI
(disagreement should be localized)

Goal: record a step of reasoning as a first-class, signed, auditable object: "because
A, B, and C hold and D does not, E follows." Today Galedra cannot say this. A claim edge
relates two claims (`SUPPORTS`, `REQUIRES`, `DERIVED_FROM`, …) and nothing joins several
premises into one step, so the reader cannot see which premises an argument rests on,
which one is the weak link, or that two people reached E by different routes. An
inference makes the argument itself inspectable and challengeable, without letting it
count as evidence.

Asked for by the owner on 2026-09-19: "Is this system capable of registering an
inference like 'because A, B, and C are true and D is false this implies E is true'?"
It is not; this stage is the answer.

Why an inference is not evidence: Article III. Evidence is what a source says or a
measurement shows; an inference is what someone concludes from claims. So an inference
never carries weight in `ledger-default@0.1.0` or `ledger-strict@0.1.0`. It is
displayed, audited, and counted for task priority and the weaknesses page. A later
scoring model version may use inferences to propagate belief; that is the change 09 §1
defers until cycle handling and a dependency model exist, and it needs a new model
version, never a change to an existing one (Invariant 4).

Deliverables:

- `CREATE_INFERENCE`, epistemic, accepted on validation like `CREATE_CLAIM`. Payload:
  `conclusion_claim_id`; `premises`: two to twelve `{claim_id, polarity}` where
  polarity is `HOLDS` or `FAILS` ("D is false" is `{D, FAILS}`); `inference_type`, one
  of `DEDUCTIVE`, `INDUCTIVE`, `ABDUCTIVE`, `STATISTICAL`, `ANALOGICAL`, `CAUSAL`,
  `DEFINITIONAL`; `rule` (the stated warrant, at most 500 characters: "if a bill passed
  both houses and was signed it is law"), untrusted display text like a note;
  `strength`, one of `ENTAILS`, `STRONGLY_SUPPORTS`, `SUPPORTS`, `WEAKLY_SUPPORTS`,
  a self-assessment shown as such; `affirms_not_private_individual`. A premise and the
  conclusion must be distinct current claims; the same claim cannot appear twice; an
  inference whose conclusion is one of its own premises is refused. Cycles across
  inferences are allowed and recorded (they are information, Article V), never
  followed by the scorer.
- Projections `inferences` and `inference_premises`, in `PROJECTION_MODELS`, with
  validity windows; `Ledger::Ids.derive(contribution_id, "inference")`. `SUPERSEDE_
  INFERENCE` is not added: a corrected inference is a new one plus `INVALIDATE`.
- Each inference also yields one `DERIVED_FROM` claim edge from the conclusion to each
  premise in the same contribution, so `downstream_count`, task priority, and the
  existing edge display keep working without knowing about inferences.
- Claim page: an "Inferences" section in two lists, "Concluded from" (this claim as
  conclusion: each inference as one line, the premises with their current headline and
  polarity, the rule, the type, the self-assessed strength, the weakest premise marked)
  and "Used as a premise in". The weakest premise is the one whose current state is
  furthest from what the polarity needs (a `FAILS` premise that reads `SUPPORTED` is the
  weakest of all). No number is derived for the conclusion from the premises; the
  section says so in one fixed sentence.
- Tasks: `INFERENCE_REVIEW`, a new task type targeting an inference: outcomes `VALID`,
  `MISSING_PREMISE`, `NON_SEQUITUR`, `CANNOT_DETERMINE`; allowed ops `CREATE_CLAIM`
  (a missing premise), `CREATE_INFERENCE` (a corrected step), `CREATE_EVIDENCE` and
  `LINK_EVIDENCE` on a premise. Opened on every new inference. Listed in the packet
  spec and the scoring config's `task_type_cost`.
- Connector and API: `record_inference` tool and `inferences` in the
  `record_investigation` bundle (handles for premises and conclusion), `GET
  /api/v1/inferences/:id`, `get_claim` carries `inferences: {concluded_from: [...],
  premise_in: [...]}`, `explain` names the weakest premise of each inference. Skill: an
  inference is how to record "this follows from those", it is never evidence, and the
  premises must each be recorded claims with their own evidence.
- Weaknesses page (Article XXII): inferences whose conclusion reads `SUPPORTED` or
  `LEANS_SUPPORTED` while a premise reads the opposite of its polarity.

Acceptance:

1. `CREATE_INFERENCE` with premises {A HOLDS, B HOLDS, C HOLDS, D FAILS} and conclusion
   E projects one inference, four premise rows, and four `DERIVED_FROM` edges; the claim
   page for E lists it with the weakest premise marked; the page for D lists it under
   "Used as a premise in" with polarity `FAILS`.
2. A conclusion among its own premises, a duplicate premise, a single premise, thirteen
   premises, a superseded claim, and an unknown type or strength are each `SCHEMA_INVALID`
   naming the path; two inferences forming a cycle are both accepted and displayed.
3. Every score under both released models is byte-identical before and after adding an
   inference; the trace does not mention it; demo and Watchers goldens pass.
4. A new inference opens an `INFERENCE_REVIEW` task; a different principal answers
   `MISSING_PREMISE` with a new claim and a corrected inference; the result is accepted
   or pending under the existing rules; the original inference stays in the log.
5. Truncate and replay reproduce both projections byte for byte; `ledger:verify` passes;
   a `TAKEDOWN` nulls the rule text and the structure remains.

Owner decisions to record: the premise cap (12); whether `strength` should exist at all
(a self-assessment invites "this entails" on weak arguments; the alternative is no
strength field and only the type); whether `ENTAILS` deductive inferences should, in a
later model version, let a conclusion inherit the minimum of its premises' probabilities;
whether inference authorship should be visible on the claim headline (planned: no, only
on the inference line, like contributor reputation).

## Decision Log (2026-09-19)

- Built as planned. `CREATE_INFERENCE` is an epistemic action type with its applier;
  `inferences` and `inference_premises` are in `PROJECTION_MODELS`; the applier also
  records one `DERIVED_FROM` edge per premise in the same contribution (ids derive from
  the contribution and the premise index), so `downstream_count`, priority, and the
  edge display work unchanged. Cycles are recorded; no scorer follows edges.
- No score input: the spec asserts byte-identical traces before and after an inference,
  and that the trace never mentions it. `Inference::NOTE` travels with every rendering.
- `INFERENCE_REVIEW` targets an inference (`tasks.target_type` gains `INFERENCE`).
  Deviation from the plan: the released scoring configs are not edited to add its
  `task_type_cost` (a config change would be a new model version, Invariant 4);
  `Tasks::Priority` falls back to the type's own cost for a type the config predates.
  Results are auto-accepted like other object-adding results; a `MISSING_PREMISE` answer
  adds a claim and a corrected inference, and the original stays.
- `Inferences::View` ranks premise states (supported 0 … contradicted 4) against the
  polarity to mark the weakest premise; `strained` (conclusion supported, a premise
  reading the opposite of its polarity) feeds the weaknesses page above the claim lists.
- Connector: `record_inference`, `inferences` in `record_investigation` bundles and in
  task answers, `inferences` on `get_claim` and the claim JSON, `GET /api/v1/inferences/:id`.
  `explain` does not yet name the weakest premise; the claim page and `get_claim` do.
- Owner decisions still open: the premise cap (12); whether `strength` should exist;
  whether a later model version lets `ENTAILS` steps propagate; author visibility.
- Constitutional Test: interpretation added as a distinct object (Article III). 1 yes;
  2 n/a; 3 no; 4 no; 5 yes; 6 yes; 7 yes; 8 yes; 9 yes (a different principal reviews);
  10 yes. No blocker.
