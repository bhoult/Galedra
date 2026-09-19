# Stage 9 — Why, summaries, answer cards, and weaknesses

**Status:** implemented · tag `stage-09-answers` · decisions recorded 2026-09-17

## Plan

**Tag:** `stage-09-answers` · **Spec:** 01 §6, 04 §10, 06 §2 (`/why`, `/summary`, `/weaknesses`), 06 §3 `card`, 06 §4 rule 5a, 06 §5 Weaknesses and per-source card

Goal: the deterministic answer layer over the graph, API-first, so Stage 10 renders and
Stage 11 prints it.

Deliverables:

- `Cards::MainIssue` (06 §4 rule 5a, first match wins), `Cards::ClaimCard`,
  `Cards::SourceCard` (per-source roll-up sentence, 08 §9). The `card` block joins claim
  responses.
- `GET /api/v1/claims/:id/why`: strongest counted support, strongest counted
  contradiction, suppressed dependents, review-coverage gaps, and the single hypothetical
  link addition that would move the score most under the current model (computed by
  re-running the scorer).
- `summaries` cache table keyed by `input_hash`; `Summaries::StubGenerator` (`stub-v0.1`,
  templates filled from the trace), `Summaries::Validator` (every sentence has at least
  one cite; every cite in the input set; otherwise reject and fall back), `SHORT` and
  `STANDARD` types, `GenerateSummaryJob`. `Llm::Adapter` interface with `Llm::StubAdapter`
  as the only implementation.
- `Weaknesses::Report` and `GET /api/v1/weaknesses?kind=&limit=` with the seven
  deterministic lists from 06 §5, each entry carrying its `/why` "what would most change
  this" item.
- Stub claim extractor for the Analyze-text flow: deterministic sentence split plus type
  guess, behind `Llm::Adapter`, producing `CLAIM_EXTRACTION` proposals.

Acceptance (07 Phase 6, API parts):

1. Summary sentences all cite IDs from the input set; a generator returning an unknown ID
   is rejected and the stub is served (#1).
2. Summary cache key changes when input changes; stale summaries are not served (#2).
3. The card for the 08 graph at S5 matches 08 §9 in state, main issue, and cites.
4. The Weaknesses report lists a claim whose state differs between the two models
   (07 scenario H).

## Decision Log (2026-09-17)

- `Cards::ClaimCard` renders the `06 §3` card: state in neutral words
  (`Cards::Headline`, never true/false/debunked/confirmed), `independent_lineages` as
  support plus contradiction groups, review checks as "N of M", stability, the main
  issue, related claims with their own headlines, and the `06 §4` labels
  (provisional, contested, model-dependent, low-coverage-with-strong-state, and the
  plain-words reason for NOT_APPLICABLE). The number is only in the assessment block.
- `Cards::MainIssue` follows `06 §4` rule 5a in order: an overturned or UNRESOLVED audit
  on a counted link, unreviewed independence, a QUALIFY link (cites the qualifying
  evidence), contested, the first unmet review check, else none recorded.
- `Cards::Why` (`01 §6`) reads the trace for the strongest counted support and
  contradiction and the suppressed dependents, lists review gaps, and finds the single
  addition that would move the score most by re-running the scorer with one
  hypothetical independent DIRECT MEASUREMENT link in each direction. Ties go to the
  contradicting addition, so the answer favours self-critique.
- Summaries (`04 §10`): `Summaries::Input` is the deterministic input (claim, state,
  checklist, kept links with evidence statements, never notes, qualifiers, suppressed
  items, related claims, audits on counted links); its hash is the cache key and its
  cite set is the only thing a sentence may cite (evidence, group, claim, task, and
  audit ids, plus `coverage:<claim>`). `Summaries::Validator` rejects any sentence
  without a cite or with a cite outside the set, and `Summaries::Generate` then serves
  `stub-v0.1`. A cached summary is served only while its input hash still matches;
  otherwise it is regenerated in place (no mutable stale flag). SHORT is two sentences,
  STANDARD six.
- `Llm::Adapter` is the optional LLM boundary; `Llm::StubAdapter` is the only P0
  implementation, selected by `LEDGER_LLM_ADAPTER=stub`. A real adapter must pass the
  same validator, which the specs prove by injecting adapters that cite unknown ids or
  nothing.
- `Cards::SourceCard` (`06 §5`) lists one card per claim created by a CLAIM_EXTRACTION
  result on the source, with a one-sentence roll-up in the shape of `08 §9`.
- `Weaknesses::Report` (`06 §5`, Art. XXII) computes the seven lists at a seq under the
  default model, each entry carrying the most-moving addition; "high downstream" is
  three or more counted outgoing edges.
- `Claims::Extract` is the stub extractor for Analyze text: sentence split on
  terminal punctuation, semicolons, and colons before capitals; type guess from cues
  (should/ought → NORMATIVE, causes/boosts → CAUSAL, will → FORECAST, numbers →
  QUANTITATIVE, reports/says → TEXTUAL, else OBSERVATIONAL); and a separate TEXTUAL
  claim for each parenthetical "(Name, YYYY)" citation. On the demo memo it proposes
  the four claims of `08 §5` (with "boosts" left as written; the seed's fixture agent
  proposes the spec's wording).
- **Tie-break found by the summary check.** `03 §4` Step 3 breaks equal magnitudes by
  the lowest evidence id, then link id, which assumes time-ordered ids. Projection ids
  here are hash-derived (Stage 2), so on the S5 supersessions a different tied link won
  and the summary cited an article instead of the survey (scores were identical either
  way). The scorer input now carries each row's `created_seq` and the scorer compares
  it first, then ids, which is the order UUIDv7 ids would have given and what the
  reference scorer's integer handles encode. Golden fixtures (no `created_seq`) are
  unaffected.
- Constitutional Test (visibility): 1 yes, every sentence cites the graph; 2 yes, the
  weaknesses page and why bundle expose where disagreement and doubt live; 3 no; 4 no;
  5 yes, unknown states get words, not numbers; 6 yes, all of it is deterministic; 7
  yes; 8 yes, cards and summaries are as of a seq; 9 n/a; 10 yes.
- Acceptance: 07 Phase 6 #1 and #2 (API parts), scenario E and scenario H (weaknesses)
  have specs in `spec/services/cards/answers_spec.rb`; the S5 cards match `08 §9` in
  state, main issue, and cites; `bundle exec rspec`, RuboCop, and Brakeman pass.
