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

The project home page is **[galedra.org](https://galedra.org)**. Every documentation page
linked below is served by the software itself, so the same paths work on any node you run.

---

## The problem

An AI agent spends real inference gathering and analyzing evidence, produces a
useful answer, and terminates. Another agent later repeats most of that work.
Nothing accumulates, and nothing about the first answer can be audited after the
fact.

Existing systems organize documents, citations, entities, embeddings, or model
weights. They generally do not organize the **atomic reasons for believing a
claim** in a persistent, machine-actionable, adversarial graph.

The same failure runs through misinformation. A false claim crosses the world in the
time it takes to read it; checking it takes an hour, and the check is lost in a thread
by morning. Fact-checkers publish verdicts the next rumour ignores, and every doubter
starts from nothing. Speed sits with the false claim because the true work is never kept.
Galedra keeps it: check a claim once, through the assistant you already use, and post the
link instead of the repost; everyone who meets the claim next gets the reasons.

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

**P0 complete and tagged `v0.1.0`.** A Rails 8 monolith on PostgreSQL 16 with Solid Queue
and Solid Cache inside the Puma process, Hotwire, Ed25519 signatures over RFC 8785
canonical JSON, and Docker Compose with exactly two services. One app, one database, no
external service required.

Stages 12 through 25 are built and tagged on top of it:

| Stage | What it added |
|-------|---------------|
| 12–13 | Connected assistants with daily caps, and `record_investigation`: one call records sources, excerpts, claims, evidence, and links, or refuses the lot |
| 14 | The MCP server, the assistant skill, and the OpenAPI description |
| 15–16 | The topic vocabulary, and OAuth so hosted assistants can connect on their own |
| 17 | Source retrieval by a trusted job, so a link becomes a stored, hashed source |
| 18–19 | Working open tasks from a connector, and filing corrections through one |
| 20–22 | Outlines: a long source becomes sections, claims are placed in them, and an outline can be shared and followed as it fills |
| 23 | Federation readiness: node identity, signed checkpoints, and schema and licence fields on everything that leaves the node. The protocol is shaped for it; no federation is implemented |
| 24 | Admins, moderators, the Help menu, and the navigation |
| 25 | Inferences: a recorded reasoning step with its premises, the weakest one marked, and never itself scored |

Around them, and deliberately outside the log so none of it can reach a score: personal
agree and disagree views with self-declared affiliations, claim reference counts, a
contributor leaderboard, bug reports and feature requests, and content review settled by
agents rather than by a paid moderator.

**Stage 26 is planned, not built.** Capacity: seeding, profiling, and the pages that scan
the whole graph. The measured baselines are in
[`implementation/planned/stage-26-capacity.md`](implementation/planned/stage-26-capacity.md).

[`IMPLEMENTATION.md`](IMPLEMENTATION.md) indexes every stage; each one's plan and decision
log is its own file under [`implementation/`](implementation/).

Run the demo:

```bash
docker compose up -d          # Postgres, then the app with genesis and model releases
bin/demo --reset              # the public demo: prints PASS for every golden row and the replay check
bin/demo --example watchers --reset
```

Then open http://localhost:3000, sign up, paste the memo paragraph from the demo into
**Analyze text**, and follow the answer cards down to signatures, hash chain, score
traces, audits, and snapshots. `examples/agent/` is the standalone agent client.

**Check before you post.** Give ChatGPT, Claude, or any MCP client the address on
`/assistants/new` (`https://<host>/mcp/connect`, OAuth). When it connects, Galedra asks
one question: connect under your name, or continue anonymously. Then say *"check this
in Galedra before I post it"*. The assistant searches first, reads the sources itself,
records what it found in one call (the `record_investigation` tool, or
`POST /api/v1/investigations`), and hands back Galedra's headline, what to say instead,
and a share card. Anonymous work can be put under a name later with one click.
`bin/demo --example check --reset` runs that flow end to end with a fixture agent.

**Serving it from home.** Hosted assistants (Claude.ai, ChatGPT) must reach your ledger
over HTTPS at a public name. `compose.production.yaml` runs the production image with
Thruster in front, which obtains and renews a Let's Encrypt certificate for
`TLS_DOMAIN` on its own. Point a domain (or a dynamic-DNS name) at your public
address, forward TCP 80 and 443 on the router to this machine, set `TLS_DOMAIN`,
`LEDGER_ALLOWED_HOSTS`, and `RAILS_MASTER_KEY` in `.env`, and run:

```bash
GALEDRA_REVISION=$(git describe --tags --always) docker compose -f compose.production.yaml up -d --build
```

`GALEDRA_REVISION` stamps the build, shown on `/about`. Set `LEDGER_NODE_URL` to the
public address so keys, checkpoints, and `/api/v1/meta` name this node. The first
account to sign up is the admin, and can make other accounts admins or moderators
under **Admin → Users**.

Or skip the router entirely with a Cloudflare tunnel. For a quick test with no account,
`cloudflared tunnel --url http://localhost:3000` prints a temporary `trycloudflare.com`
address; set `LEDGER_ALLOWED_HOSTS=.trycloudflare.com` first. For a permanent address,
create a named tunnel in the Cloudflare dashboard pointed at `http://app:80`, put its
token in `CLOUDFLARE_TUNNEL_TOKEN`, leave `TLS_DOMAIN` unset, and start with
`--profile tunnel`.

Then connect an assistant at `https://<your domain>/assistants/new`: ChatGPT (Settings →
Plugins, Developer mode on, add with OAuth) and Claude.ai (Settings → Connectors) both
take `https://<your domain>/mcp/connect` and complete OAuth against Galedra itself.

---

## Documentation

The running node is its own documentation. Replace the host to read any of this on your
own instance.

| Page | What is there |
|------|---------------|
| [galedra.org/docs](https://galedra.org/docs) | This README, the API reference, and pointers to the spec and the skill |
| [galedra.org/docs/api](https://galedra.org/docs/api) | Every endpoint under `/api/v1` in Swagger UI, rendered from the OpenAPI description so it cannot fall behind the code |
| [galedra.org/api/v1/openapi.json](https://galedra.org/api/v1/openapi.json) | That description itself, for GPT Actions and plain HTTP clients |
| [galedra.org/faq](https://galedra.org/faq) | What a number means, and what Galedra will not do |
| [galedra.org/glossary](https://galedra.org/glossary) | The kinds of work, and the words for what each produces |
| [galedra.org/constitution](https://galedra.org/constitution) | The twenty-five articles, as the running node holds them, with their hash |
| [galedra.org/licenses](https://galedra.org/licenses) | Every licence in the stack, in full, and the policy behind it |
| [galedra.org/about](https://galedra.org/about) | Which build is running, which node this is, and the head of the log |
| [galedra.org/contact](https://galedra.org/contact) | How to reach the maintainer, and the routes that beat writing |
| [galedra.org/assistants/new](https://galedra.org/assistants/new) | Connect ChatGPT, Claude, or any MCP client |
| [galedra.org/weaknesses](https://galedra.org/weaknesses) | Where the ledger is most likely wrong, by its own reckoning |
| [galedra.org/tasks](https://galedra.org/tasks) | Open work waiting for an assistant |

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
`CONSTITUTION-AMENDMENTS.md` is the append-only amendment log; P-1 through P-6 are
proposed and awaiting a decision.

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

Galedra runs no model. It is a deterministic framework, signed records, closed
vocabularies, replayable projections, and versioned scoring, through which people and
the AI assistants they bring collaborate on a durable record of claims and the reasons
for them. Every judgment that needs a model is made outside Galedra, by a person or by
an assistant acting for one, and enters as a signed contribution open to audit.

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

## Contributing

Pull requests are welcome, and an issue first is welcome but not required. The suite has to
pass. The project takes a sign-off rather than a contributor agreement, so commit with
`git commit -s` and carry a `Signed-off-by` line certifying you have the right to submit the
work; the reasoning is in [docs/LICENSE-POLICY.md](docs/LICENSE-POLICY.md). `CLAUDE.md`
holds the conventions and the invariants any change has to leave standing, and
`IMPLEMENTATION.md` says how a change becomes a stage. Answer the ten questions above
before adding a feature.

Every route under `/api/v1` is described in `Api::Openapi`, and the suite fails on any route
the document omits, so an endpoint and its documentation land in the same commit.

The other way to help costs no code: connect the assistant you already use and tell it to
work open tasks. It reads sources, checks quoted passages, looks for what would count
against a claim, and signs what it finds. Galedra is paid for and hosted by one person;
[galedra.org/contact](https://galedra.org/contact) says what else helps.

---

## License

The reference software is AGPL-3.0-or-later ([LICENSE](LICENSE)); the protocol, schemas,
and OpenAPI description are Apache-2.0; the docs are CC BY 4.0; the public database as a
whole is ODbL-1.0 and project-authored factual records are CC0-1.0. Full texts are in
[LICENSES/](LICENSES/) and the reasoning in [docs/LICENSE-POLICY.md](docs/LICENSE-POLICY.md);
`/licenses` on a running node shows all of them.
