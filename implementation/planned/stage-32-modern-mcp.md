# Stage 32 — Speaking modern MCP as well as legacy

**Status:** planned · tag will be `stage-32-modern-mcp`

**Tag:** `stage-32-modern-mcp` · **Spec:** 04 §3 (agent protocol), 06 §2 (API), 11 §5
(layout), 14 §Stage 14 (MCP and the skill), Articles XIX (transparency over persuasion),
XXII (reveal our own weaknesses), Invariants 11 (untrusted text stays inert), 18 (the
ledger runs no model)

Goal: serve MCP revision `2026-07-28` alongside the `2025-06-18` handshake Galedra speaks
today, so a modern client gets a modern server and the connectors that exist now keep
working unchanged.

## Why this is a stage and not a version bump

It was first written down, in Stage 31, as "move to protocol `2026-07-28`, set `ttlMs: 0`
and `cacheScope: public`, declare `listChanged: true`; that costs little." That was wrong,
and the correction is the reason this file exists.

`2026-07-28` is not a newer revision of the same shape. The spec calls it a **modern**
revision and everything before `2025-11-25` **legacy**, and the difference is the handshake
itself:

| | Legacy (`2025-06-18`, what Galedra speaks) | Modern (`2026-07-28`) |
|---|---|---|
| Version agreed by | `initialize`, once per session | `_meta` on *every* request, plus an `MCP-Protocol-Version` header |
| Session | established by the handshake | none; every request stands alone |
| Discovery | `initialize` result | `server/discover`, which a server **MUST** implement |
| Results | `{ tools: [...] }` | `resultType: "complete"` on every result |
| Wrong version | negotiated down in the handshake | `UnsupportedProtocolVersionError` (-32022) listing supported versions |
| Notifications | over the transport's stream | `subscriptions/listen` with per-kind flags |
| List caching | unspecified | `ttlMs` and `cacheScope` **MUST** be present on complete list results |

So "bumping the version" would mean declaring a handshake-free protocol from a server built
entirely around a handshake. A modern client would send `_meta` and a header Galedra
ignores, get a legacy-shaped result with no `resultType`, and have no `server/discover` to
fall back on.

**Dual-era is the target, not migration.** claude.ai is a legacy client today, and the
compatibility matrix is explicit that a legacy client against a modern-only server simply
fails, with no fall-forward. The `initialize` path stays. The spec permits one endpoint to
serve both eras and says how a server chooses: a request carrying modern `_meta` is served
statelessly under this revision; an `initialize` request selects legacy semantics.

## What this stage does

1. **`Mcp::Era`** decides per request: modern if `_meta` carries
   `io.modelcontextprotocol/protocolVersion` or the `MCP-Protocol-Version` header names a
   modern revision; legacy if the method is `initialize`; legacy otherwise, as today.
2. **`SUPPORTED = ["2026-07-28", "2025-06-18"]`**, and `UnsupportedProtocolVersionError`
   with the list for anything else, rather than silently serving a shape the client did not
   ask for.
3. **`server/discover`**, naming the supported versions and this node.
4. **`resultType: "complete"`** on modern results only; legacy results keep their present
   shape byte for byte, because an existing connector must see no change at all.
5. **Caching hints stay as Stage 31 set them** — `ttlMs: 0`, `cacheScope: "public"` — which
   are already correct and already sent to both eras.
6. **Notifications are out of scope.** See below.

## `listChanged` stays false, deliberately

Advertising `listChanged: true` requires somewhere to push
`notifications/tools/list_changed`. `GET /mcp` returns `405` and the controller says why:
the server pushes nothing. Making it true means holding a stream per connected client,
which is a capacity question (Stage 26) before it is a protocol one, and this node runs
Solid Queue inside Puma.

It is also not worth much here. A notification's whole purpose is to invalidate a cache,
and Stage 31 already tells clients not to keep one (`ttlMs: 0`). The rules an assistant
works by ride on every tool result, where nothing caches them. A stale tool description
costs a little clarity; it no longer costs correctness. **Declaring a capability the server
cannot honour is worse than declaring none**: a client that trusts `listChanged: true` will
never re-fetch, because it believes it will be told.

## Acceptance

1. An `initialize` request produces a result identical to today's, field for field.
2. A request carrying modern `_meta` gets `resultType: "complete"` and is served without a
   session.
3. `server/discover` lists both supported versions.
4. A request naming an unsupported version gets -32022 with `supported` and `requested`.
5. `tools/list` carries `ttlMs` and `cacheScope` in both eras.
6. The existing MCP request specs pass unchanged, which is the real test: they are written
   against the legacy path.

## Open questions for the owner

- Whether to serve both eras on `/mcp` or give modern its own path. One endpoint is what
  the spec permits and what keeps the OAuth discovery hooks in one place.
- Whether `server/discover` should reveal anything about this node beyond versions and
  name. It is unauthenticated, like the rest of the read surface.
