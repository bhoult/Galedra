# Stage 12 — Connected assistants

**Status:** implemented · tag `stage-12-assistants` · decisions recorded 2026-09-18

## Plan

**Tag:** `stage-12-assistants` · **Spec:** 05 §2 (custody), 05 §4 (delegation), 04 §9
(agent defaults), 02 §3.1, Art. XI, XIV

Goal: a user, or nobody at all, can connect an assistant in under a minute, and every
write the assistant makes is a signed, delegated, attributable contribution.

Deliverables:

- `ANONYMOUS` added below `PSEUDONYMOUS` in the identity tiers. An anonymous contributor
  is a server-custodied key with no account; its contributor page says so.
- Assistant tokens. `POST /api/v1/assistants` mints a bearer token, registers a
  server-custodied `AGENT` key named for the assistant (`software.agent_name`,
  `model_provider`, `model_id`), and appends a `DELEGATE` from the principal: the
  signed-in user's key, or a freshly registered anonymous key when there is no account.
  Revoking a token appends `REVOKE_DELEGATION`. Tokens are shown once and stored hashed.
- `POST /api/v1/custodied/contributions` with `Authorization: Bearer`: the server builds,
  signs, and appends the envelope through `Ledger::Append` exactly as `Ui::Write` does,
  custody `SERVER`, with the token's delegation and software metadata. Every applier and
  rejection code is unchanged; the only new failure is `TOKEN_INVALID`.
- Weighting for anonymous and unaudited work, none of it in scores: a higher audit
  sampling probability for `ANONYMOUS` principals in `config/audit_policy.yml`; a
  per-token daily cap and rate limit; the `provisional` label reads "not yet audited;
  anonymous contributor" on cards; contributions from anonymous keys open verification
  tasks at raised priority (Stage 13).
- "Connect an assistant" page: pick the assistant, mint, copy. Works signed out.

Acceptance:

1. A token minted signed out yields an `ANONYMOUS` principal, an `AGENT` delegate, and a
   `DELEGATE` entry in the log; a token minted signed in delegates from the user's key.
2. A custodied write produces a contribution whose signature verifies against the agent
   key, whose `software` names the assistant, and which `ledger:verify` accepts.
3. A revoked token gets `TOKEN_INVALID`; its `REVOKE_DELEGATION` appears in the log.
4. The audit schedule samples an anonymous principal's contribution at the raised
   probability, and claim scores are byte-identical whether the same links came from an
   anonymous or an established contributor.
5. Rate limit and daily cap return 429 with a plain message.

Owner decisions to record: whether evidence from `ANONYMOUS` principals should be
held out of counting until audited (a counting rule, not a weight; conservative reading
is "counts, labelled provisional"); the daily cap.

## Decision Log (2026-09-18)

- `assistant_tokens` is operational, not a projection: like `custodied_keys` it survives
  replay, and the log holds the facts that matter (the agent's `REGISTER_KEY`, the
  principal's `DELEGATE`, and any `REVOKE_DELEGATION`). A token is usable only while
  its delegation is live, so revocation in the log always wins over the token row.
  Tokens are stored as SHA-256 digests and shown once.
- `custodied_keys.user_id` became nullable: anonymous principals and assistant agent
  keys are server-custodied with no account. `Crypto::Custody.signer_for_contributor`
  unlocks by contributor; callers authenticate first (a bearer token, or the session
  for the connect page).
- `ANONYMOUS` was added below `PSEUDONYMOUS`. The spec's tiers start at pseudonymous;
  this is an extension, recorded here. Anonymous work is weighted where the
  constitution allows: an `anonymous_factor` (3) in the audit policy, applied through a
  new `principal_tier` sampling input; a per-token daily cap (429 `DAILY_CAP`) and a
  per-token rate limit (429 `RATE_LIMITED`); and the provisional label on cards names
  the anonymous origin. Claim scores are byte-identical regardless of tier (acceptance
  #4 checks this directly).
- Direct work by a delegated agent stays `PENDING` under `02 §1.1a`, which would have
  left every assistant write uncounted. A delegation may now carry
  `permissions.direct_work: true`, and the default `auto_accept?` treats such an
  agent's direct work as the principal's own hand. The grant is a signed, visible,
  revocable contribution, and the work is still sampled for audit at the raised rate.
  Task results keep their own acceptance rules.
- Minting: the API mints anonymous tokens only; signed-in minting is on the connect
  page, so an account's key is never used without its session. The API token endpoint
  is rate limited by address. Rails fixes a limiter's cache store at class-load time,
  so limits go through `Assistants::RateLimitStore`, a delegator to `Rails.cache`,
  which lets a spec swap in a memory store and exercise the 429.
- Constitutional Test (identity and audit weighting change): 1 more traceable (the
  assistant is named in `software` and the delegation is logged); 2 more inspectable;
  3 no hidden authority (grants and revocations are public log entries); 4 no,
  reputation and tier never enter scores; 5 yes, provisional labels are stronger, not
  weaker; 6 yes, sampling inputs are stored and recomputable; 7 yes, an opposing
  investigator uses the same token flow; 8 yes; 9 yes, nothing personal is stored; 10
  yes.
- Reserved for the owner, as planned: whether anonymous evidence should be held out of
  counting until audited (the conservative reading, "counts, labelled provisional", is
  what shipped); the default daily cap (200).
