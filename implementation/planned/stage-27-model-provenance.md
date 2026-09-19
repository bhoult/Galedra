# Stage 27 — Which model did this, and which work needs which model

**Status:** planned · tag will be `stage-27-model-provenance`

**Tag:** `stage-27-model-provenance` · **Spec:** 02 §1.1 (the envelope), 04 §2 and §7
(task types, packets, leases), 05 §5–§7 (identity and reputation), 06 §5 (contributor
display), Articles VII (attribution), X (reputation is not authority), XI (identity tiers
do not weigh evidence), XXII (the system reveals its own weaknesses), Invariant 7 (AI is
never evidence by itself), Invariant 8 (reputation is not a scoring input), Invariant 17
(determinism is not objectivity)

Goal: record which model did a piece of work, as provenance, and use it to route tasks to
the smallest model that can do them. A claim extraction over a long transcript needs a
frontier model with a large context window. Deciding whether one quoted sentence supports
one claim does not, and a 7B model on a local GPU with a 4k window can do it all day for
nothing. Today the ledger cannot tell the two apart, so it offers every task to everyone.

## Why this is not a scoring change

The dangerous reading of this stage is "work by a better model is better work". That is
exactly what the constitution forbids: Article XI says identity tiers do not weigh
evidence, Invariant 8 keeps reputation out of scores, and Invariant 7 says AI output is
never evidence by itself. A model name is a weaker signal than either, and it is
self-declared besides.

So the rule this stage is built on, and which every deliverable below is measured
against: **the model is provenance and routing. It never touches a score.** It may decide
who is offered a task and how often that work is audited. It may never change a
probability, a state, or a trace. The scoring configs do not learn the field exists.

The second rule: **a declared model is a claim about itself, not a fact.** An assistant
says what it is and nothing verifies it. The record therefore stores it as declared, shows
it as declared, and never treats it as proof. A local 7B that claims to be a frontier
model gets frontier tasks and fails its audits, which is what audits are for.

## What exists today

The envelope already has a `software` object (02 §1.1), and `Assistants::Connect` fills it
with `agent_name`, `version`, `model_provider`, `model_id`, `prompt_version`. So the field
is there. It is not usable:

- **It is mostly absent.** Of 600 contributions sampled on the development node, 173 carry
  `software` at all.
- **The model is usually junk when present.** `model_id` was `"oauth"` 93 times,
  `"unknown"` 37 times, `"none"` 5 times, and a real model identifier 26 times. The OAuth
  connect path writes `"oauth"` into the field that should hold a model.
- **Nothing validates it.** `schemas/eir-contribution-v1.json` types `software` as
  `["object", "null"]` and stops there.
- **Nothing reads it.** No projection, no index, no query, no page, no routing.

## Deliverables

- **A declared-model vocabulary.** `config/models.yml`: for each known model, its provider,
  its identifier, a context window in tokens, and a capability tier. Tiers are a closed
  enum in `UPPER_SNAKE_CASE` like every other enum here, and deliberately few:
  `FRONTIER`, `MID`, `SMALL`, `UNKNOWN`. Unknown is the default and is never an error; a
  model absent from the file is `UNKNOWN`, which is a fact about the file, not about the
  model. The file is data, like `config/topics.yml` and `config/affiliations.yml`, so
  adding a model is not a code change.

- **`software` gets a schema.** `model_provider` and `model_id` become required strings
  when `software` is present, with a length cap; `context_window` optional and an integer;
  everything else stays open. Rejecting a malformed `software` is an append-time schema
  error like any other, so it cannot enter the log wrong and need correcting later.

- **Fix the OAuth path.** `"oauth"` is a connection method, not a model. The connector
  learns the model at connect time where the provider exposes it, and writes `"unknown"`
  where it does not. An honest unknown is worth more than a wrong answer, which is the
  same rule the scoring model follows for `INSUFFICIENT_EVIDENCE`.

- **The model reaches every contribution an assistant signs.** `Assistants::Write` and the
  custodied write path attach the token's `software` to each envelope, so a contribution
  carries the model that made it rather than leaving it on the token. Human contributions
  carry no model, which is itself the information.

- **A projection to query it.** `contribution_software`, written only by `Ledger::Apply`
  like every projection (Invariant 2): contribution id, provider, model id, declared tier,
  declared context window, and the seq. Indexed on provider and model. Replay rebuilds it
  byte-identically from the envelopes, so nothing new is trusted to survive.

- **Task types declare what they need.** Each entry in `Tasks::Types::SPECS` gains
  `min_tier` and `min_context`, next to the `cost` it already carries. A first reading, to
  be argued in review rather than accepted here:

  | Task | Tier | Why |
  |---|---|---|
  | `CLAIM_EXTRACTION` | `FRONTIER` | Reads a whole excerpt and decides what propositions it asserts; the failure mode is a claim nobody made |
  | `INFERENCE_REVIEW` | `FRONTIER` | Judges whether a conclusion follows, which is the hardest thing asked here |
  | `OPPOSING_EVIDENCE_SEARCH` | `MID` | Needs search and judgement, but over one claim at a time |
  | `QUALIFIER_CHECK` | `MID` | A closed checklist over counted evidence |
  | `SOURCE_INDEPENDENCE_CHECK` | `SMALL` | Compares origins of items already gathered |
  | `EVIDENCE_VERIFICATION` | `SMALL` | One excerpt against one claim, no outside knowledge, small context |

  `SOURCE_INDEPENDENCE_CHECK` and `EVIDENCE_VERIFICATION` are the volume work, and they are
  the two a local GPU can take. That is the point of the stage.

- **Leasing respects it.** `Tasks::Lease.next` offers a task only when the caller's declared
  tier meets `min_tier` and its declared context window meets `min_context`. An `UNKNOWN`
  tier is offered `SMALL` work only: not a punishment, but the same conservative reading
  the ledger applies everywhere it does not know something. The packet already carries the
  smallest sufficient context (04 §3), so `min_context` is checked against the packet's
  actual size, not a guess.

- **Audit sampling may weigh it.** `Audits::Policy` may sample work from an `UNKNOWN` or
  `SMALL` declaration more often. That is a decision about where to spend attention, not
  about whether the work is right, and it is the one place a model name legitimately
  changes behaviour.

- **Shown, as declared.** The contribution page and `/api/v1/contributions/:id` name the
  model, with the word *declared* next to it. A task page says the tier it wants. The
  glossary gains an entry for the tiers. No page ranks contributors by model, and the
  leaderboard does not learn the field exists.

- **The weaknesses report gains a kind.** Article XXII asks the system to reveal where it
  is weak. A claim whose evidence rests entirely on work by one model, or entirely on
  `UNKNOWN` declarations, is a real weakness and belongs on that page under a new kind,
  `single_model_dependence`. This is the honest use of the field: not to discount the work,
  but to say plainly what it rests on.

## Acceptance

1. A contribution signed by a connected assistant carries `software.model_provider` and
   `software.model_id`, and the projection row matches the envelope after `ledger:replay`.
2. An envelope with a `software` object missing `model_id` is rejected at append with a
   schema error, and never reaches the log.
3. A token declaring a `SMALL` model is never leased a `CLAIM_EXTRACTION`, and is leased
   `EVIDENCE_VERIFICATION`. A token declaring nothing is treated as `UNKNOWN` and gets the
   same answer.
4. Scores are untouched: the demo goldens and the Watchers goldens are byte-identical
   before and after this stage, and no scoring config, trace, or `ClaimScore` row mentions
   a model tier.
5. `/weaknesses` lists a claim whose counted evidence comes only from one declared model,
   under `single_model_dependence`.
6. The contribution page says "declared" beside the model, and no page orders contributors
   by it.

## Constitutional Test

Answered per CLAUDE.md, because this touches identity and visibility.

1. **More traceable?** Yes. Who did the work is already recorded; this records what did it,
   which is the part that has been missing since assistants became contributors.
2. **Disagreement more inspectable?** Yes. "Both of these were extracted by the same model"
   is a reason to look harder, and the weaknesses page will say it.
3. **Hidden authority?** No, provided the rule at the top holds. A model tier that reached
   a score would be exactly that, which is why acceptance test 4 checks the goldens rather
   than trusting the reading.
4. **Reputation substituting for evidence?** No. Routing decides who is offered work.
   Whether the work is right is still decided by audit.
5. **Uncertainty preserved?** Yes. `UNKNOWN` is a first-class tier, it is the default, and
   it is never an error.
6. **Reproducible?** Yes. The projection is rebuilt from the envelopes by replay; nothing
   is recorded that the log does not already carry.
7. **Challengeable by an opponent?** Yes. A declaration is a claim about itself and can be
   contradicted by audit like anything else.
8. **History reconstructable?** Yes; the declaration is in the signed envelope at its seq.
9. **Shared evidence separate from personal belief?** Unchanged.
10. **Would we want this used by people we disagree with?** Yes. A record that says which
    machine produced a conclusion is more useful to a hostile reader than to a friendly one.

## Owner decisions

- The tier table above. `OPPOSING_EVIDENCE_SEARCH` at `MID` is the one worth arguing:
  the search is easy and the judgement of what counts as opposing is not.
- Whether an `UNKNOWN` declaration should be leased anything at all, or only `SMALL`.
- Whether a node should be able to refuse work from a declared model entirely, which is a
  moderation power and so wants Article XXV treatment before it is built.
- Whether `min_context` is checked against the packet's real token count, which needs a
  tokenizer the server does not have, or against its byte length with a stated ratio. The
  second is deterministic and needs no model, which is the reading Invariant 18 prefers.
