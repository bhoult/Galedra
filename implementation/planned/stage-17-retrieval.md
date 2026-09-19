# Stage 17 — Source retrieval by a trusted job

**Status:** planned, not built · tag will be `stage-17-retrieval`

## Plan

**Tag:** `stage-17-retrieval` · **Spec:** 04 §6 step 9 (the server never fetches
agent-supplied URLs; a human or trusted job imports content later), 01 §7 (no page text
in the log), 02 §3.2–3.3, 13 (Article II row), Article II, Article XI

Goal: a source recorded by link, with the quoted excerpt as the only verifiable text, is
later checked by Galedra itself. A background job that Galedra controls fetches the
link under its own rules, hashes what it received, looks for each quoted excerpt in it,
and appends what it found as a system-signed entry. The reader's record is never
changed; the server's finding sits beside it. An assistant can never ask for this fetch
and never steers it: the only input is a link already in the log.

Why not fetch on request: an assistant's write must not make Galedra act on untrusted
input. A URL in a bundle could point into the network behind the tunnel, at something
enormous, or at a page that differs per visitor. Invariant 11 stays as it is. Since
Stage 17's predecessor change (2026-09-18, Decision Log "Testing with claude.ai"), a
page hash is optional on a source held by reference, because hosted assistants see a
rendering and not bytes; this stage is how such sources gain a hash and a confirmation
without anyone inventing anything.

Deliverables:

- `RETRIEVE_SOURCE`, a control contribution signed by the system key, payload:
  `source_id`, `fetched_at`, `outcome` (one of `FETCHED`, `NOT_FOUND`, `BLOCKED`,
  `TIMEOUT`, `TOO_LARGE`, `UNSUPPORTED`, `REFUSED`), `content_hash` and `content_length`
  when fetched, `media_type`, `final_url` after redirects, and `excerpts`: one row per
  `QUOTE` or `TRANSCRIPTION` location on the source with `location_id` and `found`
  (`VERBATIM`, `NORMALIZED` after whitespace and quote normalisation, or `NOT_FOUND`).
  Page text is never stored; only the hash, the size, and the excerpt findings.
- Projection `source_retrievals` (in `PROJECTION_MODELS`, so digests, replay, and
  `ledger:verify` cover it) and `retrieval_pending` cleared on the source when the
  outcome is `FETCHED`; the source keeps its own `content_hash` if the reader gave one,
  and the retrieval's hash is shown alongside as the server's, never overwriting it.
- `Sources::Retrieve`: a Solid Queue job keyed `(source_id, created_seq)`, idempotent,
  enqueued by the `CREATE_SOURCE` applier only for sources held by reference and outside
  a task. Rules: public hosts only, the address refused after DNS resolution when it is
  private, loopback, link-local, or a metadata range, and re-checked on every redirect;
  https or http only; at most five redirects; a byte cap (2 MB) and a timeout (10 s); a
  fixed identifying user agent; robots exclusions respected; one fetch per host per
  minute; no script execution, the served HTML is read as text after tag stripping for
  the excerpt check. `IMAGE` sources are hashed as bytes with no excerpt check
  (`TRANSCRIPTION` rows are reported `UNSUPPORTED`). A failed fetch is recorded once with
  its outcome and not retried by the job; a moderator or the owner may re-run it with
  `bin/rails sources:retrieve ID`.
- Display: the source page and the API show the retrieval (outcome, server hash, time,
  and each excerpt's finding); the claim card's review checks say "excerpt confirmed on
  the page at retrieval" or "excerpt not found on the page at retrieval". A `NOT_FOUND`
  excerpt adds a note to the claim's open `EVIDENCE_VERIFICATION` task rather than
  changing any score (Article XI: the retrieval is a fact for auditors, not a scoring
  input in v0.1).
- `LEDGER_RETRIEVAL` env: `off` (default in test), `on` (default in development and
  production); the demo runs with it off and its goldens are unchanged.

Acceptance:

1. A bundle records a source by link with two excerpts; the job fetches a local stub
   page, appends `RETRIEVE_SOURCE` with `FETCHED`, the server hash, and one `VERBATIM`
   and one `NOT_FOUND` finding; the source page and API show both; replay reproduces
   the projection and `ledger:verify` passes.
2. A link resolving to a private, loopback, or link-local address is recorded as
   `REFUSED` without a connection being opened; the same for a redirect that lands
   there.
3. A page over the byte cap is recorded `TOO_LARGE`, a slow page `TIMEOUT`, a 404
   `NOT_FOUND`, a 403 or a robots exclusion `BLOCKED`; none is retried automatically;
   `sources:retrieve` re-runs one on demand and appends a second entry.
4. Sources created inside a task are not enqueued; sources with stored content are not
   enqueued; the same source is never fetched twice for one `created_seq`.
5. A `NOT_FOUND` finding leaves every score and the reputation tables unchanged and
   appears on the claim's verification task; demo goldens and the Watchers goldens pass
   with retrieval on and off.

Owner decisions to record: whether a retrieval that finds every excerpt should count
toward the review checklist (the conservative reading, no, is what this stage plans);
whether to re-fetch periodically to detect changed or vanished pages; the byte cap and
timeout.

## Decision Log

Written when the stage is executed.
