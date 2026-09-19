# After Stage 14 — The write link

**Status:** implemented · decisions recorded 2026-09-18 · no tag (work between stages)

## Decision Log (2026-09-18)

- `GET /api/v1/investigations/record?token=&bundle=` records an investigation on a
  GET, with the bundle as base64url JSON in the query. This is deliberately
  non-standard: GET is meant to be safe, and a plain write link would be repeated by
  link-preview bots, prefetchers, and retries. It exists because the alternative for a
  browsing-only assistant is a copy-and-paste step that loses the very users this is
  for. The owner chose it knowingly.
- What makes it acceptable: the token is required, so only a connected assistant can
  write, and tokens are revocable, rate limited, and capped; the write is idempotent
  (`investigation_receipts`: the same token and bundle digest returns the first result
  with `replayed: true`), so repeats append nothing; `token` and `bundle` are filtered
  from logs. The POST endpoint shares the idempotency, so retried POSTs are safe too.
- Not fixed by this: hosted assistants must still be able to reach the hostname, which
  rules out quick-tunnel addresses for ChatGPT.
- Tokenless, by the owner's decision: the write link and `POST /api/v1/investigations`
  (and the MCP writing tools) accept requests with no token at all. The caller becomes
  an anonymous assistant keyed to its address for the day (`assistant_tokens.source_key`),
  minted on first use, so the work is still signed, delegated, capped per source per
  day, sampled at the anonymous rate, and labelled. Idempotency is keyed to that
  assistant. Raw custodied writes and token management still need a real token.


## Removed (2026-09-19)

The write link (`GET /api/v1/investigations/record`, with the bundle in the query or the
path) was removed on the owner's instruction: a state-changing GET that a link preview
or a crawler could trigger, needing no credential in its tokenless form, built for a
host whose browser refused long URLs and so never served it. Hosted assistants use OAuth
over MCP (Stage 16). What it shared with the POST door stays: idempotent recording
through `InvestigationReceipt`, and anonymous assistants keyed to their address for the
day. The spec that covered it now covers those over POST.
