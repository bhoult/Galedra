# After Stage 14 — Adoption

**Status:** implemented · decisions recorded 2026-09-18 · no tag (work between stages)

## Decision Log (2026-09-18)

- Anonymous work can be put under an account later, by the owner's request. `ADOPT_KEY`
  is a new control contribution: signed by the adopter's human key, carrying a
  counter-signature by the adopted key over `{"adopt": adopter, "key_id": adopted}`,
  so it proves control of both keys; the server holds both when the anonymous key is
  server-custodied. The applier sets the adopted key's tier to the adopter's and
  records `adopted_by` and `adopted_seq` in its metadata. The adopted key keeps its
  own rows and reputation buckets; contributor pages show the link both ways.
- Every anonymous assistant carries an adoption code (encrypted at rest, digest
  indexed). Recording responses for anonymous work include `attribution.adopt_url`;
  opening it signed in shows the work and one button. The skill and tool rules tell
  assistants to mention it as optional. After adoption the provisional label no longer
  names an anonymous contributor, because the principal no longer is one; audit
  schedules already computed keep their stored inputs.
- ChatGPT: personal accounts lost GPT creation on 2026-08-16 and GPTs retire on
  2026-12-11; the replacement, plugins, are MCP servers. Developer mode on Plus lets a
  user add `https://<host>/mcp` as a plugin with no authentication; it scanned all eight
  tools and both read and write calls landed. Two OpenAI-shaped tools, `search` and
  `fetch`, were added for hosts that only allow read-and-fetch connectors. Tool
  annotations mark reads read-only and writes idempotent; every tool has an
  `outputSchema`. ChatGPT's browser strips or refuses URLs beyond a few hundred
  characters, so the write link cannot serve a plain ChatGPT chat; it stays for hosts
  that carry URLs intact.
