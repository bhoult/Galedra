# Stage 16 — OAuth for connectors

**Status:** implemented · tag `stage-16-oauth` · decisions recorded 2026-09-18

## Plan

**Tag:** `stage-16-oauth` · **Spec:** 05 §2 (custody), 05 §4 (delegation), 06 §1,
MCP authorization (2025-06-18): OAuth 2.1, RFC 8414 metadata, RFC 9728 protected
resource metadata, RFC 7591 dynamic client registration, RFC 7636 PKCE, RFC 8707

Goal: a person connects Galedra inside ChatGPT or Claude.ai, signs in once on Galedra's
own consent page, and from then on every call from that assistant is attributed to
them, with no token to copy and nothing to paste. Anonymous use stays exactly as it is;
OAuth adds attribution, it never becomes a requirement.

Deliverables:

- Galedra is the authorization server for its own MCP endpoint, on the same host:
  `/.well-known/oauth-authorization-server` (RFC 8414) and
  `/.well-known/oauth-protected-resource` (RFC 9728, plus the `/mcp` path-suffixed
  form) describe it, and an unauthenticated `POST /mcp` that a client marks as wanting
  auth is answered with `WWW-Authenticate: Bearer resource_metadata=…`, the discovery
  hook connectors follow.
- `POST /oauth/register`: dynamic client registration for public clients with PKCE
  (`token_endpoint_auth_method: none`) and confidential ones with a secret; redirect
  URIs recorded and enforced exactly; rate limited by address.
- `GET /oauth/authorize`: requires sign-in (the person is returned here after), shows
  one consent page naming the client and what it will do, and on approval issues a
  single-use ten-minute code bound to the client, redirect URI, PKCE challenge (S256
  only), scope, and `resource`.
- `POST /oauth/token`: `authorization_code` with PKCE verification, and `refresh_token`
  with rotation (the whole family is revoked if a used refresh token is replayed).
  Access tokens live one hour, refresh tokens thirty days, both stored as digests.
  `POST /oauth/revoke` (RFC 7009) revokes either.
- One durable delegation per person per client: the first grant mints an
  `AssistantToken` for the user named after the client (`Assistants::Connect`), so the
  agent key, the logged `DELEGATE`, the daily cap, and the revocation path are the ones
  that already exist. Access tokens map onto that assistant token; `AssistantAuth`
  accepts them anywhere a bearer is accepted. Disconnecting on the connect page revokes
  the delegation and every OAuth token for it.
- The connect page's ChatGPT and Claude.ai instructions become "choose OAuth"; the skill
  files say the same; the write link and tokenless paths are unchanged.

Acceptance:

1. The two metadata documents validate: issuer, authorization, token, registration, and
   revocation endpoints, `code_challenge_methods_supported: [S256]`, and the protected
   resource names `/mcp` and its authorization server.
2. A client registers, sends a person to authorize, the person signs in and approves,
   and the code exchanges for tokens; the access token records through `/mcp` and
   `/api/v1/investigations` attributed to the person's key, not anonymously, under a
   delegation visible in the log.
3. A wrong verifier, a reused code, a mismatched redirect URI, an unknown client, and an
   expired access token are all refused with the RFC error codes.
4. Refresh rotates; replaying an old refresh token revokes the family.
5. Disconnecting the assistant on the connect page appends `REVOKE_DELEGATION` and every
   token for it stops working; `ledger:replay` and `ledger:verify` are unaffected.

Owner decisions to record: token lifetimes; whether a connector may request a scope
that limits it to reads (`galedra:read`) rather than the default read-and-write.

## Decision Log (2026-09-18)

- Galedra is the OAuth 2.1 authorization server for its own MCP endpoint, on the
  same host. `/.well-known/oauth-authorization-server` (RFC 8414) and
  `/.well-known/oauth-protected-resource` (RFC 9728, root and path-suffixed) describe
  it. Two MCP doors: `/mcp` stays anonymous-or-token; `/mcp/connect` answers 401 with
  `WWW-Authenticate: Bearer resource_metadata=…` until a bearer is presented, which is
  the discovery hook ChatGPT plugins and Claude.ai connectors follow. A presented but
  invalid credential is refused on either door rather than falling through to
  anonymous use, so clients refresh instead of writing anonymously by accident.
- Dynamic client registration (RFC 7591) for public clients with PKCE and for
  confidential clients with a secret shown once; redirect URIs must be https, loopback
  http, or a custom scheme, and match exactly. Codes are single-use, ten minutes, bound
  to client, redirect URI, S256 challenge, scope, and resource. Access tokens live an
  hour, refresh tokens thirty days, all stored as digests; refresh rotates and a
  replayed refresh token revokes its family. `POST /oauth/revoke` (RFC 7009).
- The durable fact stays in the log: the first grant for a person and client mints
  one `AssistantToken` through `Assistants::Connect` (agent key, `DELEGATE`, cap), and
  every access token maps onto it. `AssistantAuth` accepts `gat_` access tokens
  wherever a bearer is accepted, so REST and MCP writes under OAuth are attributed to
  the person's key. Disconnecting on the connect page appends `REVOKE_DELEGATION` and
  revokes every OAuth token for it.
- The consent page is the only new UI: one screen naming the client and what it can
  do, Allow or Cancel, after sign-in. Scopes: `galedra` (read and write, default) and
  `galedra:read`. Owner decisions (2026-09-18): tokens do not expire, and neither do
  connected-assistant delegations (100 years); revocation is the only end. A connector
  may ask for `galedra:read`, and that grant is enforced: writes over REST answer 403
  `INSUFFICIENT_SCOPE` with the RFC 6750 challenge, and MCP writing tools return a tool
  error naming the scope to reconnect with.
- Constitutional Test (identity): 1 more traceable (attributed, logged delegation);
  2 yes; 3 no hidden authority (the grant and its revocation are public entries); 4
  no; 5 yes; 6 yes; 7 yes; 8 yes; 9 yes, OAuth stores no profile data, only the link
  between a client and a key; 10 yes.
