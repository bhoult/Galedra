# Claim references — how often a claim is met

**Status:** implemented · decisions recorded 2026-09-19 · no tag (work between stages)

## Decision Log (2026-09-19)

Owner request: "record how many times a claim was referenced in order to eventually be
able to identify common misconceptions and make something like a 'top 10 common lies'."

- `claim_references`: one row per claim, kind, and day, with a count. Kinds: `CHECKED`
  (the claim was in a recorded investigation, new or attached), `LOOKED_UP` (`get_claim`,
  `fetch`, or `explain` over the connector), `VIEWED` (the claim page), `SHARED` (the
  claim's share card, or a check page or its image holding the claim, which is what a
  posted link produces). Counting is an upsert that never raises, so a failed count
  cannot break the read or write it rides on.
- Outside the log, like `investigations` and `feature_requests`: a count is not an
  epistemic fact, is not signed, is not replayed, and never reaches scoring (Invariant
  11 in spirit: attention is not evidence). The claim page says so in the same sentence
  as the numbers.
- Display: the claim page shows the four counts; the claims list and
  `GET /api/v1/claims` take `sort=references`, `kind=`, and `window=` (7d, 30d, 365d);
  the claim JSON and `get_claim` carry `references`. Spec 06 §4 rule 12 forbids ranking
  claims by how "wrong" they are and persuasive framing, so the order is by how often a
  claim was met and the wording is neutral. "The most-met claims whose evidence
  contradicts them" is the list the owner wants; it is the references order with the
  state filter set to `CONTRADICTED`, and it will never be titled "lies".
- Crawlers and link previews inflate `VIEWED` and `SHARED`. That is accepted for now;
  `CHECKED` and `LOOKED_UP` are the cleaner signals, and the filters let a reader pick.
- Not done: a dedicated "most met" page, per-topic breakdowns, and a rollup job to
  collapse old daily rows. All are cheap once the counts exist.
