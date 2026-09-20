# Stage 35 — Provenance is not corroboration

**Status:** implemented, golden, and default · `stage-35-provenance-is-not-corroboration`

**Tag:** `stage-35-provenance-is-not-corroboration` · **Spec:** 02 §3 (sources, locations,
evidence), 03 §3–§7 (weights, independence, states, and why a number needs its model and
snapshot), 04 §2 (task types), 06 §4 and §6 (display rules and counts), Articles V
(contradiction is preserved), XIX (transparency over persuasion), XXII (reveal our own
weaknesses), XXIII (re-examination), Invariants 4 (deterministic, versioned scores),
5 (unknown is explicit), 6 (no double counting), 7 (AI is never evidence by itself),
17 (determinism is not objectivity)

Goal: a claim taken out of a source must not be corroborated by that same source. Confirming
a transcript faithfully records what a speaker said establishes **provenance**. It says the
quotation is real. It says nothing whatever about whether the speaker was right.

## What is wrong now

Reported by an assistant, unprompted, against a claim it had itself just moved to
"Supported" (`docs/experiments/2026-09-19-live-connector-outline.md`, finding 20).

An `EVIDENCE_VERIFICATION` task on an outline hands the worker the very transcript sentence
the claim was extracted from. Confirming it is recorded as a `SUPPORT` link and weighed like
any other support. On the episode outlined in that run:

| | |
|---|---|
| A bare unsourced assertion by a podcast guest | `SUPPORTED`, probability **0.8281** |
| Its review coverage | **0.00** |
| Its supporting links | both `TRANSCRIPTION`, both from that episode |
| Claims in the outline reaching a directional state | 29 |
| **Of those, supported only by the episode itself** | **24** |

So a reader is shown *"Checks out so far"* on claims where nothing outside the podcast was
ever consulted. **Article XIX asks for transparency over persuasion, and this is persuasion
produced by accident.**

### The second fault, found while confirming the first

The same episode is recorded as **two `Source` rows with an identical `canonical_uri`**, and
across the node **3 URIs account for 7 rows** — the episode three times, a Wikipedia page and a magazine article twice each. Nothing in `CREATE_SOURCE` deduplicates, so
every recording of a URL mints another origin. Independence is grouped by evidence origin, so
two rows for one URL let the same origin count twice — the double counting Invariant 6
forbids, and the standing rule *"repetition is not corroboration"* states in words.

**Fix this first.** Independence cannot mean anything while one URL is several origins, and
some of the 24 may dissolve once it does.

## The design

### 1. One origin per source, without merging rows

`Source#lineage_key` already exists for this. On `CREATE_SOURCE`, when no lineage key is
given, derive one from the normalised `canonical_uri` — scheme and host lowercased, default
ports, trailing slash and tracking parameters dropped. Rows stay as they are, the log is
untouched, and nothing is mutated retrospectively: what changes is that **independence groups
by origin, not by row**.

Deriving rather than deduplicating matters. Two recordings of one URL are two honest
contributions by different people at different times, and collapsing them into one row would
throw away who recorded what. They are one *origin* and two *records*, and only the first of
those is a scoring question.

### 2. A claim's own origin cannot support it

A link is **self-referential** when the origin of its evidence is an origin the claim was
extracted from — that is, the source of any section the claim is placed in.

Both halves are already in the graph and derivable from the log, so this stays deterministic:
`ClaimPlacement → Section → source → origin` against `EvidenceClaimLink → EvidenceItem →
SourceLocation → source → origin`.

Such a link is scored through a new `provenance_factor`, keyed like the existing
`authenticity_factor` and `extraction_factor`:

```
"provenance_factor": { "SELF": "0.0", "INDEPENDENT": "1.0" }
```

At `0.0` the link weighs nothing, exactly as `MODEL_OUTPUT` already does under
`observation_weight` — the precedent for evidence that is recorded, shown, and moves no
probability. **The link is not discarded.** It is kept, displayed, and counted, because
knowing a quotation is faithful is worth knowing; it simply stops being mistaken for
corroboration.

### 3. Say so where the claim is read

A claim whose only support is its own origin must not read as checked. The card says what is
true of it: *"The quotation is faithful to the source. Nothing outside it has been checked."*
With no independent evidence in either direction, the state is `INSUFFICIENT_EVIDENCE`, which
Invariant 5 already reserves for exactly this and which carries no probability.

### 4. A new model version, because that is the rule

Invariant 4: the same seq and model give a byte-identical trace, so scorer changes require a
new version. This ships `ledger-default@0.2.0` and `ledger-strict@0.2.0`, with `0.1.0` left
released and unchanged. Every existing score stays reproducible under the model that produced
it, and `/claims/:id/compare` shows exactly where the two disagree — which on this corpus is
the most useful demonstration of model-dependence the project has yet had.

## What this stage must not do

- **Not delete or rewrite anything.** No source row is merged, no link is withdrawn, no score
  is edited in place. The old model keeps producing what it always produced.
- **Not silently restate old numbers.** A claim that read 0.83 under `0.1.0` still reads 0.83
  under `0.1.0`. The change is visible as a model, not applied as a correction.
- **Not treat a self-referential link as worthless.** It is the difference between a claim
  that misquotes its source and one that does not, and that is worth recording.

## Acceptance

1. Two `CREATE_SOURCE` contributions naming one URL produce two rows sharing one derived
   origin; an explicit `lineage_key` is honoured over the derivation.
2. Independence groups by origin: two pieces of evidence from one URL recorded as two rows
   count once, under `strongest_only_per_group_and_direction`.
3. The reported claim, under `0.2.0`, is `INSUFFICIENT_EVIDENCE` with no probability, and its
   self-referential links are still listed with their excerpts.
4. Under `0.1.0` that same claim still scores 0.8281 at the same seq, byte-identical.
5. Of the outline's 29 directional claims, the 24 supported only by their own origin are no
   longer directional under `0.2.0`; the 5 with outside evidence are unaffected.
6. A claim with one self-referential link and one independent supporting link is scored on
   the independent one alone.
7. The card for a self-referential-only claim says the quotation is faithful and nothing
   outside has been checked.
8. `reference_scorer.py` prints ALL PASS for both models, with new golden rows for `0.2.0`.

## Open questions for the owner

- **Which model is default after this.** Leaving `0.1.0` default means the node keeps showing
  the numbers this stage exists to correct; making `0.2.0` default changes what every visitor
  sees at once. The second is right and should be a deliberate, announced switch.
- **Whether `EVIDENCE_VERIFICATION` on an outline leaf should exist in its present form.** Its
  packet passage is the claim's own sentence, so the task can only ever establish provenance.
  It may deserve its own outcome vocabulary — faithful, misquoted, cannot determine — rather
  than `CONFIRMED`, which reads as agreement with the content.
- **Whether the 24 claims should be re-checked automatically.** Opening an
  `OPPOSING_EVIDENCE_SEARCH` on each would cost real work and is exactly the work that ought
  to happen; doing it without asking would spend the owner's cap on the owner's behalf.

## Decision Log

**`0.1.0` is byte-identical, checked two ways.** Forty trace hashes captured before the
change and compared after: identical, digest `30b8f47c` unchanged. The reference scorer
prints ALL PASS. Both new behaviours read from config keys `0.1.0` does not declare, so a
model that says nothing scores exactly as it always did.

**Grouping by origin alone was too broad, and a spec caught it.** The first cut keyed
ungrouped evidence by origin, which collapsed *every* passage of one document into a single
group and dropped a qualifier that a supporting line then outranked. A qualifier and a
supporting sentence from one report are not each other repeated. The group is now origin
**and passage** (`excerpt_hash`), so the same passage entered twice under duplicate source
rows counts once, while two genuine passages stay distinct.

**Origin is derived at read time, not written.** `Sources::Origin` normalises the address;
`lineage_key` wins when given. No migration, no contribution rewritten, no replay divergence.
Two recordings of one URL stay two honest records of one origin.

**The default model is now pinned.** `default_model` returned the newest released
`ledger-default`, so `ledger:release_models` silently made `0.2.0` what every visitor saw —
a switch this plan said must be deliberate. `LEDGER_DEFAULT_MODEL` pins it, set to
`ledger-default@0.1.0` in compose and `.env.example`. Unset, the old behaviour stands.

**A latent bug surfaced with the third model.** `/api/v1/claims/{id}/compare` with no
`models` parameter defaulted to *every* released model and then required exactly two, which
worked only while exactly two existed. It now compares the default with the strict model of
the same version.

### What it does to the corpus

Under `0.2.0`, on the outlined episode: directional claims fall from **43 to 7**, and the 7
are exactly those carrying evidence from outside the episode. The reported claim moves from
`SUPPORTED 0.8281` to `INSUFFICIENT_EVIDENCE` with no probability, while still reading
`0.8281` under `0.1.0` at the same seq.

### The goldens, and what generating them showed

**`0.2.0` scores every existing golden case exactly as `0.1.0` does.** All 20 cases across
both suites and both model families: 22 of 22 identical. That is not a coincidence to wave
at — the demo corpus contains no evidence drawn from a claim's own origin and no passage
entered twice, so the only two things this model changes never arise in it. The fixture now
carries `0.2.0` expectations for all 20, and the end-to-end suite recomputes them from the
graph, so a wrong value fails loudly rather than sitting there agreeing with itself.

**Which is also why those 20 prove nothing about the new rule**, so a provenance suite was
added to both implementations — `reference_scorer.py` and `spec/services/scoring/provenance_spec.rb`
— over the same inputs, with no code shared between them:

| | `0.1.0` | `0.2.0` |
|---|---|---|
| One supporting link from the claim's own origin | SUPPORTED 0.8581, 1 group | **INSUFFICIENT_EVIDENCE**, no probability, 0 groups |
| The same passage entered twice | SUPPORTED 0.9734, 2 groups, HIGH | **SUPPORTED 0.8581, 1 group, MEDIUM** |
| Two genuine passages of one document | — | SUPPORTED 0.9734, 2 groups (unchanged, deliberately) |

The expectations were reasoned before they were run: the prior for `OBSERVATIONAL` is 0.50,
so the log-odds start at zero and one `DIRECT` × `DIRECT_TEXT` link is 2.0 × 0.9 = 1.8,
giving sigmoid(1.8) = 0.8581. Seven of the eight predicted fields were right first time. The
eighth was wrong and the scorer was right: stability for the duplicate case under `0.1.0` is
HIGH, not MEDIUM, because two groups meet the minimum and one does not. That the confidence
falls along with the number when a duplicate collapses is correct — one passage read twice
is not two readings — and it was found by predicting rather than by reading the output.

**No golden value was altered.** `0.1.0`'s numbers are untouched; `0.2.0`'s were generated
and cross-checked.
- **Done.** `0.2.0` is the default (`LEDGER_DEFAULT_MODEL` in compose and `.env.example`), and
  a claim whose counted evidence is all self-referential now reads *"The quotation is faithful
  to the source. Nothing outside it has been checked."* The sentence is derived from the trace,
  which this model marks per link, so it cannot drift from what the number did. Specs pin the
  three cases where it must **not** appear: mixed evidence, no evidence at all, and a claim
  that reached a directional state.
- **Unexplained, and left visible.** `spec/services/cards/plain_spec.rb` changed: at one step
  the suggested sentence moves from a short contradiction to a narrower claim. `0.2.0` matches
  the precedence `Cards::Plain`'s own comment documents — a narrower claim that holds up comes
  before the strongest counted contradiction — so the expectation was updated, but the
  mechanism behind the difference was never traced. Both sentences are true of the claim and
  neither is invented, so no reader is misled; the precedence still deserves examining on its
  own rather than being settled by whichever model is default. The uncertainty is written into
  the spec rather than hidden behind a green suite.
- Six specs needed updating for the switch, and they split cleanly: four hardcoded a model
  name and now read it from the registry, so the next version bump will not break them; two
  were real, where outline claims supported only by the source they came from stopped being
  supported.
- Nothing re-checks the claims that lost a directional state. Opening an opposing-evidence
  search on each is the work that should happen and would spend the owner's cap unasked.
