# After Stage 14 — Serving from home

**Status:** implemented · decisions recorded 2026-09-18 · no tag (work between stages)

## Decision Log (2026-09-18)

- `LEDGER_ALLOWED_HOSTS` (comma-separated) extends `config.hosts` in development and
  production, with `/up` excluded from host authorization for the container health
  check. Rails would otherwise answer 403 at any name but localhost.
- `compose.production.yaml`: the production image behind Thruster, which provisions
  a Let's Encrypt certificate for `TLS_DOMAIN` and stores it in a volume; ports 80
  and 443 published; `db:prepare`, genesis, and model releases run before Puma.
- The MCP token may travel in the URL (`/mcp/<token>`), because Claude.ai's connector
  screen accepts only a URL and no headers. The URL is then the secret; tokens stay
  revocable from the connect page, and the header form remains for clients that can
  send one. OAuth for connectors is left for later.
