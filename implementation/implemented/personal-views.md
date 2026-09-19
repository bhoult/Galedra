# Personal views, affiliations, and content review

**Status:** implemented · decisions recorded 2026-09-19 · no tag (work between stages)

## Decision Log (2026-09-19)

Owner requests, in order: (0, on the whole) "we have no paid admins so the general goal
is to resolve non-deterministic issues without direct user intervention or maintenance";
(1) "a user should be able to identify their affiliations …
they should also be able to register what they personally agree with or disagree with
(thumbs up, thumbs down), the goal being to eventually be able to ask questions like how
different affiliations agree or disagree on a topic and why"; (2) "if an affiliation is
missing, the user can request one be added. An LLM task will be to dedupe the
affiliations"; (3) "any new information added should be added to the task list so that an
agent can review for offensive content. If such content is found the agent should redact
it."

### Personal views (spec 02 §3.6a, Article XV, 06 §4 rule 9)

- `personal_assessments` is the table the spec reserved, with its fields (`lens`,
  `personal_probability`, `cites`, `visibility`) present and empty, plus `stance`
  (`AGREE` or `DISAGREE`) and `rationale` (at most 500 characters): the thumbs and the
  "why". One row per person and claim; changing a view updates it; removing deletes it.
- Outside the log, never fed to `Ledger::Apply`, scoring, packets, or summaries. The
  claim page shows the person's own view in a dashed panel headed "Your view" and the
  aggregate in "Registered views", both below the assessment and both carrying the fixed
  sentence that views are personal belief, not evidence. The claim JSON does not carry
  views; `GET /api/v1/claims/:id/views` does, in aggregate only.
- `visibility` stays `PRIVATE`: a person's stance is never shown with their name. A later
  "Alice's view" (spec 02 §3.6a) needs the person to choose `PUBLIC`; not built.

### Affiliations

- `config/affiliations.yml`: closed groups (politics, religion or worldview, nationality,
  generation, education) of options; a person picks any number on `/account`. Private to
  the account and to admins reading the database; shown only as counts.
- `PersonalAssessments::Breakdown` splits a claim's registered views by affiliation and
  shows an affiliation only when at least `MIN_GROUP` (5) people holding it registered a
  view on that claim, so a small group can never expose anyone. Political neutrality
  (Article XVIII): the table says how groups split, never which group is right, and no
  group is ever scored.
- Special-category data (religion, politics) is self-declared, optional, deletable by
  the person, and used for nothing but these counts. The account page says so in plain
  words. An owner decision remains: whether to state a retention and export policy.

### Missing affiliations and deduplication

- `AffiliationRequest`: a person asks for a missing affiliation (five a day). The LLM
  boundary (`Llm::Adapter#resolve_affiliation`, stubbed by default like every LLM feature)
  maps it: `EXACT` (an existing slug or label), `ALIAS` (`config/affiliation_aliases.yml`:
  dem, gop, boomers, phd …), `SIMILAR` (pg_trgm similarity at or above 0.45), or `NONE`.
  `EXACT` and `ALIAS` are applied at once by `ResolveAffiliationRequestJob`; `SIMILAR`
  and `NONE` go to consensus review (below): assistants working `next_affiliation_review`
  answer `MERGE`, `ADD`, or `DECLINE` with `submit_affiliation_review`, and the agreed
  verdict settles every pending request for the same normalized text together. The admin
  page remains as an override.
- `CustomAffiliation` extends the vocabulary from the database under a curated group or
  "Other"; `Affiliations.groups` folds them in. A real LLM adapter must return the same
  `{slug, confidence}` shape and is never trusted beyond `EXACT` and `ALIAS` without a
  person.

### Content review

- `ContentReview`: every non-empty free-text field written outside the log (bug reports,
  feature requests, affiliation requests, the reason on a personal view) is queued when
  written. Log content is not queued: it has quarantine and takedown.
- Reviewers: named assistants through `next_content_review` and `submit_content_review`
  (one hundred a day), or an admin at `/admin/content_reviews` as an override. The rules
  are fixed text handed with every item: slurs, harassment or threats, sexual content,
  private personal data; never disagreement, criticism, or strong opinion. The text is
  marked untrusted against prompt injection.
- **Consensus, not admins** (`Reviews::Consensus`, shared with affiliation reviews): one
  verdict per principal per item, recorded in `review_verdicts`; the author of the text
  never votes on it (the same rule as 04 §3.1's distinct principals and Article XI's no
  self-certification); `REQUIRED` (2) agreeing verdicts settle an item at once; a single
  verdict nobody has contradicted settles it after `ALONE_AFTER` (48 hours), applied by
  `SettleLoneVerdictsJob` every hour, so a quiet queue drains with one honest reviewer.
  Disagreeing verdicts wait for a further one to make a pair. No leases: several
  principals may judge the same item at once, which is the point.
- `OFFENSIVE` replaces the field with `[redacted after review]` wherever it is shown and
  keeps the original on the review row, visible to admins only, who can restore it.
  `list_tasks` reports both pending counts and the skill's "work N open tasks" procedure
  includes both reviews when ledger tasks run out.
- Not a ledger task type: 04 §2 task types target claims and sources and their results
  are signed ops. Reviewing off-log text through the log would put moderation of bug
  reports into the epistemic record.

Owner decisions to record: `MIN_GROUP` (5); the similarity threshold (0.45);
`REQUIRED` (2) and `ALONE_AFTER` (48 hours); whether personal views should be
rate-limited or need an account age; whether reviewers' assistants should need a track
record, or a verdict should weigh by audited reliability, before their agreement settles
an item (planned: no, every named principal counts once); retention of affiliations.
