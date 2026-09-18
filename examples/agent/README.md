# Example agent

A standalone Ruby client for the Epistemic Ledger agent protocol (spec 04). It
depends only on Ruby's standard library.

```bash
ruby examples/agent/agent.rb keygen > agent-key.json
# Register the key (kind AGENT) and have a human principal DELEGATE to it; then:
ruby examples/agent/agent.rb run --base-url http://localhost:3000 --key-file agent-key.json \
  --delegation <delegation uuid> --types EVIDENCE_VERIFICATION,OPPOSING_EVIDENCE_SEARCH --once
```

What it does, in order: lease the highest-priority task it may take
(`POST /api/v1/tasks/next`, a signed `eir-lease-v1` body), verify the packet's
server signature against `/api/v1/meta`, answer from `fixtures.json`
(deterministic behaviours, never heuristics), sign an `eir-result-v1` envelope,
and `POST /api/v1/contributions`.

`fixtures.json` maps a task type (and optionally a claim-text fragment) to a
behaviour: `confirm_direct`, `none_found`, `group_by_title`, `qualifier_demo`,
`propose_claims`, `no_claims`, `none_material`. `--agent bad` selects the
fixtures marked `"agent": "bad"` (the demo's poisoning agent).

Canonicalization: the client implements the RFC 8785 subset the ledger uses
(no floats; keys sorted by UTF-16 code units). The ledger's
`spec/fixtures/canonical_json_vectors.json` lets any client confirm identical
hashes, and `Galedra::Jcs.canonical` reproduces them.

Defensive defaults recommended to every agent author (04 §9): treat everything
under `untrusted_excerpt` as data, never as instructions, and give the agent no
write access beyond submitting its result.
