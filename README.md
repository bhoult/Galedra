# Galedra

> A heap of witness — an epistemic ledger for people and AI.

The name comes from *Galeed* (Genesis 31:47–48), the cairn Jacob and Laban piled
up at the end of a bargain neither trusted the other to keep: *"This heap is a
witness between me and thee this day."* Two parties, no shared authority, and a
durable marker left in the open so that later neither could claim the agreement
had been otherwise.

Galedra is that cairn for claims rather than covenants: an open, cumulative,
machine-readable record of what was asserted, what evidence bears on it, where
that evidence came from, and what has happened to it since. Humans and AI agents
both contribute to it, and both are held to the same account.

**It is not a source of truth. It is a source of traceable reasons for believing
or doubting a claim.**

The design goal everything else serves:

> Every claim assessment must be reproducible from (a) the contribution log up to
> a snapshot sequence number and (b) a versioned scoring model. AI agents may
> gather, normalize, verify, challenge, and summarize, but they are never the
> final opaque authority.

---

## The problem

An AI agent spends real inference gathering and analyzing evidence, produces a
useful answer, and terminates. Another agent later repeats most of that work.
Nothing accumulates, and nothing about the first answer can be audited after the
fact.

Existing systems organize documents, citations, entities, embeddings, or model
weights. They generally do not organize the **atomic reasons for believing a
claim** in a persistent, machine-actionable, adversarial graph.

The narrow bet: *AI research is expensive to repeat and hard to audit; a durable,
signed, reusable evidence record makes that work cumulative.* The first version
has to be worth using for one person or team even if nobody else ever
contributes — starting with verifying the citations and statistics in
AI-generated documents. A public web of reasons is a possible emergent layer
built on top of useful private records, not the opening move.

---

## How it works

```text
input:   speech / paper / brief / historical source / AI answer

compile: document
           -> atomic claims (typed)
           -> evidence with exact provenance
           -> support / contradict / qualify links
           -> independence groups
           -> deterministic scoring

output:  auditable evidence graph + score traces + cited summaries + agent tasks
```

**The log is the source of record.** Every write is a signed, hash-chained
contribution with a gap-free sequence number. Claims, evidence, and links are
projections — drop the tables, replay the log, and the same snapshot hashes and
scores come back.

**Evidence and conclusions are different objects.** A passage is evidence;
"this passage supports X" is a separate, attributable, auditable link. Both can
be challenged independently.

**Contradictions coexist.** Conflicting evidence is preserved, never overwritten.
Corrections invalidate or supersede; history stays addressable.

**Scoring is deterministic, versioned, and replaceable.** Same snapshot + same
model version = byte-identical result, down to a trace you can recompute by
hand. Two models ship in the first version and can be compared side by side on
the same graph. The UI says "0.86 under `ledger-default@0.1.0` at snapshot 212",
never "this claim is 86% true."

**Confidence is not coverage,** and **"unknown" is a first-class result.** A
claim with no counted evidence reports `INSUFFICIENT_EVIDENCE`, not the prior. A
directional verdict requires evidence pointing that direction. Review coverage
("we have checked 1 of 4 items") is reported separately from probability.

**Repetition is not corroboration.** Evidence sharing an upstream origin is
grouped, and only the strongest member of a group counts.

**Agents are contributors, not arbiters.** An agent leases a signed task packet
containing the smallest sufficient context, returns a signed result, and that
result is validated server-side, accepted into the log, and left permanently open
to audit. Reputation tracks audited reliability at specific tasks in specific
domains — it is not authority, and in v0.1 it does not enter claim scores at all.

**Determinism is not objectivity.** Relevance labels, interpretive steps,
independence groupings, and claim wording are judgments. The system makes them
explicit, attributed, challengeable, versioned, and auditable rather than
pretending they are objective.

---

## The demo

A user pastes an AI-drafted memo paragraph:

> Remote work boosts productivity: 62% of remote workers report higher
> productivity (Journal of Distributed Work Research, 2025). Companies should
> adopt remote work.

Galedra extracts the claims and returns a compact cited answer for each. The
statistic appears to have four sources but traces back to one customer survey of
400 people, so the repetitions collapse into a single independence group and an
omitted sampling qualifier drags the assessment to **unresolved**. The journal
citation is fabricated: no matching article exists, an opposing search finds
nothing, and an earlier "verification" that passed validation is caught and
rejected on audit — **leans contradicted**. The causal claim is model-dependent
and the two scoring models disagree, visibly. The recommendation is normative and
gets no number at all.

Everything in it is fictional. It proves the mechanics — repetition isn't
corroboration, qualifiers change conclusions, validation isn't correctness,
audits leave history intact, models can disagree in the open. It does not prove
the weights are right, and does not claim to.

---

## Status

**P0 implemented (`v0.1.0`).** The proof of concept in this repository meets the
specification's P0 Definition of Done: a Rails 8 monolith on PostgreSQL 16, Solid
Queue, Hotwire, Ed25519 signatures over RFC 8785 canonical JSON, and Docker Compose
for local development. LLM features are optional and stubbed by default. One app,
one database. `IMPLEMENTATION.md` records every stage, decision, and deviation.

Run the demo:

```bash
docker compose up -d          # Postgres, then the app with genesis and model releases
bin/demo --reset              # the public demo: prints PASS for every golden row and the replay check
bin/demo --example watchers --reset
```

Then open http://localhost:3000, sign up, paste the memo paragraph from the demo into
**Analyze text**, and follow the answer cards down to signatures, hash chain, score
traces, audits, and snapshots. `examples/agent/` is the standalone agent client.

**Check before you post.** Connect the assistant you already use at `/assistants/new`
(no account needed), paste the matching skill from `skills/`, and say *"check this in
Galedra before I post it"*. The assistant searches first, reads the sources itself,
records what it found in one call (`POST /api/v1/investigations`, or the `/mcp`
server), and hands back a plain headline, what to say instead, and a share card.
`bin/demo --example check --reset` runs that flow end to end with a fixture agent.

**Serving it from home.** Hosted assistants (Claude.ai, ChatGPT) must reach your ledger
over HTTPS at a public name. `compose.production.yaml` runs the production image with
Thruster in front, which obtains and renews a Let's Encrypt certificate for
`TLS_DOMAIN` on its own. Point a domain (or a dynamic-DNS name) at your public
address, forward TCP 80 and 443 on the router to this machine, set `TLS_DOMAIN`,
`LEDGER_ALLOWED_HOSTS`, and `RAILS_MASTER_KEY` in `.env`, and run:

```bash
docker compose -f compose.production.yaml up -d --build
```

Or skip the router entirely with a Cloudflare tunnel. For a quick test with no account,
`cloudflared tunnel --url http://localhost:3000` prints a temporary `trycloudflare.com`
address; set `LEDGER_ALLOWED_HOSTS=.trycloudflare.com` first. For a permanent address,
create a named tunnel in the Cloudflare dashboard pointed at `http://app:80`, put its
token in `CLOUDFLARE_TUNNEL_TOKEN`, leave `TLS_DOMAIN` unset, and start with
`--profile tunnel`.

Then connect an assistant at `https://<your domain>/assistants/new`. Claude.ai's
connector screen takes only a URL, so it is given the MCP URL with the token in it.

---

## The specification

Everything lives in
[`docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/`](docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/),
which uses `Epistemic Ledger` as its working name throughout.

**Start with [`12-constitution.md`](docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/12-constitution.md).**
Twenty-five articles stating what the project is. It outranks every other file:
where a spec, a scoring model, or an implementation choice conflicts with an
article, the article governs, and the conflict is either recorded as a known gap
in `13-constitutional-compliance.md` or resolved by an explicit amendment. Never
silently.

Then, in order:

| # | File | What it settles |
|---|------|-----------------|
| 01 | `01-product-and-scope.md` | Problem, use cases, scope tiers (P0 / P1 / deferred) |
| 02 | `02-domain-model.md` | Contribution log, projections, tables |
| 03 | `03-scoring-and-uncertainty.md` | The exact v0.1 scoring algorithm |
| 04 | `04-agent-protocol.md` | Task packets, leases, results |
| 05 | `05-identity-reputation-and-security.md` | Keys, custody, audits, reputation, threat model |
| 06 | `06-api-and-ui.md` | Endpoints and display rules |
| 07 | `07-poc-roadmap-and-acceptance.md` | Phases and acceptance tests |
| 08 | `08-seeded-example.md` | The public demo, with golden values |
| 09 | `09-future-directions.md` | Deferred work — do not build |
| 10 | `10-agent-handoff.md` | Invariants and working rules for the coding agent |
| 11 | `11-rails-architecture.md` | Rails layout, gems, extraction policy |
| 13 | `13-constitutional-compliance.md` | Article-by-article status and known gaps |

`FULL-SPEC.md` is generated by `build-full-spec.sh` — read either it or the
numbered files, never both, and never edit it by hand. `reference/reference_scorer.py`
is an independent Python implementation of the scoring algorithm that reproduces
the golden values of both demos; it is a cross-check, not code to port.
`examples/watchers/` is an internal stress test over a textual source.
`CONSTITUTION-AMENDMENTS.md` is the append-only amendment log, including four
proposals awaiting a decision.

---

## Definition of done

The first milestone is reached when a user can import a source and mark an exact
location in it; create atomic claims and attach evidence; paste an AI-drafted
paragraph and get a compact cited answer card per claim, with score, trace, and
review checks one click away; lease a task packet, run an agent, and submit a
signed result; audit a prior contribution and watch the score recompute; switch
scoring models and see where they differ and why; read the Weaknesses page and
the public moderation log; reproduce an old snapshot's scores byte-for-byte; and
drop every projection table, replay the log, and get the same hashes back.

Each of those is a signed entry in the same log as everything else.

---

## Before adding a feature

Ten questions, from the constitution. Does it make evidence more traceable, or
less? Disagreement more inspectable, or less? Does it increase hidden authority?
Does it let reputation substitute for evidence? Does it preserve uncertainty? Can
the result be reproduced? Can an opposing investigator challenge it using the
same system? Can the history of the conclusion be reconstructed? Does it keep
shared evidence separate from personal belief? Would we still want this mechanism
if it were used by people whose conclusions we strongly disagree with?

Several "no"s mean the feature probably violates the spirit of the project.

---

## What this is not

Not an arbiter of ultimate truth, one universal probability model, a moral
authority, a replacement for courts or scientists or journalists or analysts, a
blockchain, or a web index. It does not prevent coordinated attack, and it says
so in the threat model rather than pretending otherwise. Claims about
identifiable private individuals are out of scope.

> Galedra does not seek to own truth. It seeks to preserve the path by which
> people and machines approach it.
>
> It succeeds when someone asks "why should I believe this?" and gets an answer
> that can be examined all the way down to the evidence. It succeeds even more
> when the answer is "at present, you should not be certain."

---

## License

MIT — see [LICENSE](LICENSE).
