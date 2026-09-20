# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

Galedra is an **epistemic ledger**: an append-only, signed, hash-chained log of claims,
evidence, provenance, audits, and deterministic scoring, contributed to by humans and AI
agents alike. It is a source of traceable reasons for believing or doubting a claim, not a
source of truth. The spec calls it **Epistemic Ledger**; same project, do not spend time
on branding.

**Status: P0 complete (`v0.1.0`, Stages 0–11 tagged); P1 Stages 12–16 tagged (connected assistants, record an investigation, MCP and the skill, topics, OAuth for connectors); Stages 18 and 19 tagged (work open tasks, corrections from a connector); Stages 23 and 24 tagged (federation readiness; admins, help, and navigation); Stage 17 tagged (source retrieval by a trusted job); Stages 20–22 tagged (sections and placements; large requests from a connector; sharing outlines); Stage 25 tagged (inferences); Stage 26 (capacity) is half built: `bench:seed`, `bench:report`, the profiling harness and the first pass at `/weaknesses` are in; the `claim_scores` prune, the contributor-tally index and the load test are not. Stage 30 (a section's whole text, readable, with the quoted anchor kept separate) is built. Stage 31 (the working rules served live from `Guidance`, on every MCP result and at `/api/v1/guidance`, with the skill thinned to a pointer) is built. Stage 32 (MCP revision 2026-07-28 served alongside the 2025-06-18 handshake; `Mcp::Era` decides per request) is built. Stage 34 (a person may work the routine checks on their own claims; recorded as self-performed, never raising review coverage) is built. Stages 27 (model provenance), 28 (export and import as verifiable JSON), 29 (fallacy notes) and 33 (a readable static copy of an outline) are planned and not started.** `IMPLEMENTATION.md` indexes the
stages; each stage's plan and Decision Log entry is one file under `implementation/`
(`planned/` or `implemented/`), built one stage per tag only when the owner asks. Read the
relevant spec sections and the stage file before changing anything.

## Layout

```
README.md                     public summary derived from the spec; keep it consistent
IMPLEMENTATION.md             index: how a stage is executed, the stage table, decision-log rules
implementation/planned/       one file per stage not yet built (its plan)
implementation/implemented/   one file per stage built (its plan, then its Decision Log entry)
docs/CONTEXT.md               how this project is actually worked on: the external-agent test
                              loop, what each record folder is for, graphify, and the mistakes
                              that have been made more than once. Read it before a long session.
docs/experiments/             one file per run against something real: what was tried, what the
                              database said, what it found, and what the watcher got wrong
docs/profiler/                one file per profiling run: conditions, numbers, findings
docs/security/                one file per security audit: findings, dismissals, what held up
                              (every finding in both carries a status; update it in place
                              when you fix one, or the log misleads the next reader)
docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/     ("SPEC" below)
  12-constitution.md          25 Articles + Constitutional Test. Outranks every other file.
  README.md                   purpose, principles, conventions, P0 Definition of Done
  01 … 11, 13                 scope, domain model, scoring, agent protocol, identity/security,
                              API/UI, roadmap/acceptance, public demo + goldens, deferred work,
                              agent handoff, Rails architecture, constitutional compliance map
  CONSTITUTION-AMENDMENTS.md  append-only amendment log; P-1..P-6 are proposed, not adopted
  REVIEW-NOTES.md             what changed across revisions and why (numbered entries)
  scoring-config-v0.1.json, scoring-config-strict-v0.1.json   authoritative model configs
  reference/reference_scorer.py   Python cross-check reproducing every golden value
  examples/watchers/README.md     internal stress test with its own goldens
  build-full-spec.sh          regenerates FULL-SPEC.md
  FULL-SPEC.md                GENERATED. Never edit by hand.
```

**Read `docs/CONTEXT.md` first for anything non-trivial.** It carries what this file
cannot: how defects are actually found here (connect a chat assistant over MCP, give it a
real job, watch the server side, and read what it files through `report_bug` and
`request_feature`), why every finding carries a status updated in place, and a list of
mistakes made more than once — instructions drifting from the behaviour they describe,
theorising instead of measuring, and filters narrow enough to discard the diagnostic.
**Keep it current in the same session:** add a practice once it has caught something real,
delete what has been superseded, and correct what turns out to be wrong. It is maintained,
not archived — a note that has quietly stopped being true is worse than no note, because it
is trusted.

## Reading order and precedence

1. `12-constitution.md`, then SPEC `README.md`, then `01` through `11`, then `13`.
2. Read **either** the numbered files **or** `FULL-SPEC.md`, never both.
3. The constitution outranks everything. Among spec files the more specific wins: `03`
   scoring, `02` schema, `04` agent protocol, `05` identity and audits, `06` API and
   display, `07` build order and acceptance, `11` stack. `09` is deferred: do not build it.
4. If following the spec would violate an Article, stop, record the conflict in the
   stage's file under `implementation/`, and take the reading that honors the Article.
   Never silently.

## Rules for editing the spec

- Never edit `12-constitution.md`. Propose changes under "Proposed" in
  `CONSTITUTION-AMENDMENTS.md` in Article XXV's five-part format.
- Never hand-edit `FULL-SPEC.md`. After changing any source file, run
  `build-full-spec.sh` and commit the result in the same commit.
- Never change a golden value in `08 §8` or `examples/watchers/README.md §7` to make
  something pass. Run the reference scorer, find which side is wrong, document it.
- After changing `03`, a scoring config, or a golden table, the reference scorer must
  print `ALL PASS`. Its expected tuples change only for a deliberate spec change.
- A change touching an Article updates `13-constitutional-compliance.md`. Substantive
  revisions get a new numbered entry in `REVIEW-NOTES.md`.
- Cross-references use the form `02 §1.3`. `11` is the only home for stack rationale.
  Outward-facing examples use the `08` demo, not Watchers.

## Canonical vocabulary

No synonyms anywhere: docs, code, API fields, UI copy.

- Score fields: `probability`, `assessment_state`, `review_coverage`, `review_checklist`,
  `stability`, `support_groups`, `contradict_groups`, `independence_unreviewed`,
  `contested`, `provisional`, `not_applicable_reason`, `model_dependent`, `trace`.
- States: `SUPPORTED`, `LEANS_SUPPORTED`, `UNRESOLVED`, `LEANS_CONTRADICTED`,
  `CONTRADICTED`, `INSUFFICIENT_EVIDENCE`, `NOT_APPLICABLE`.
- Models: `ledger-default@0.1.0` and `ledger-strict@0.1.0` (same code, different config).
- Enums are `UPPER_SNAKE_CASE` strings validated against a closed list, never Postgres
  enum types. Primary keys are UUIDv7; `C2`, `E1`, `L3` in the docs are display handles.
- Snapshots are identified by `seq`, never by timestamp.
- No floats in signed payloads or traces. Decimals are strings with fixed places;
  scoring uses `BigDecimal`, half-even rounding at 6 (weights), 4 (probability), 2 (coverage).
- Hashes are `sha256:` + hex over RFC 8785 canonical JSON, or raw bytes for blobs.
- Say "0.86 under `ledger-default@0.1.0` at snapshot 212", never "86% true". Never call
  a score objective.

## Invariants

Condensed from `10-agent-handoff.md`. They must hold in any code written here.

1. **Log first.** Every epistemic write is a signed contribution through `Ledger::Append`;
   `POST /api/v1/contributions` is the only write path.
2. **Projections are written only by `Ledger::Apply`** and are read-only elsewhere.
   Truncate, replay, and every row and snapshot digest comes back identical.
3. **Append-only.** Corrections are new contributions. The app's DB role cannot `DELETE`
   from `contributions` or `UPDATE` anything but `current_status`. The one exception is
   a signed, visible `TAKEDOWN`.
4. **Deterministic, versioned scores.** Same `seq` + same model = byte-identical trace.
   Scorer code changes require a new model version.
5. **Unknown is explicit.** `NOT_APPLICABLE` and `INSUFFICIENT_EVIDENCE` carry no
   probability. A directional state needs evidence in that direction; the prior alone
   never produces one.
6. **No double counting.** Strongest-only per independence group and direction, visible
   in the trace.
7. **AI is never evidence by itself.** `MODEL_OUTPUT` weighs 0. Agent results are
   closed-enum ops validated server-side and left open to audit.
8. **Reputation is audit-derived, task/domain-specific, and not a scoring input in v0.1.**
9. **No self-certification** by the same contributor or principal.
10. **Summaries only restate supplied graph content**; every sentence cites graph IDs.
11. **Untrusted text stays inert.** Notes and excerpts never reach scoring; notes never
    reach other agents' packets; the server never fetches agent-supplied URLs.
12. **Moderation is visible.** Quarantine and takedown leave public stubs and appear in
    the public moderation log.
13. **Shared and personal stay separate.** Personal assessments (P1) live outside the log.
14. **More than one model.** Scoring code never assumes a single model.
15. **No text-uniqueness for claims.** Similarity proposes; only an accepted, reversible
    `MERGE_CLAIMS` merges.
16. **Answers first, numbers on request.** The default claim view is the answer card.
17. **Determinism is not objectivity.**
18. **Galedra runs no model.** It is a deterministic framework through which people and the
    AI assistants they bring collaborate on a durable record. The only `Llm::Adapter` is the
    deterministic stub, and no adapter that calls a model is added to the server: a function
    that needs a model (extraction, summary, deduplication, review) becomes a task or a tool
    for a connected assistant, whose answer is a signed contribution open to audit. The
    server's only outbound requests are Stage 17 source fetches.

For any change touching scoring, identity, reputation, moderation, visibility, or
history, answer the ten Constitutional Test questions (end of `12-constitution.md`) in
the stage's file under `implementation/`. A "no" to 1, 5, 6, 7, 8, or 9, or a "yes" to 3 or 4, is a blocker
until justified in writing.

## Implementation rules

Stages, deliverables, and acceptance tests are one file per stage under `implementation/`,
indexed in `IMPLEMENTATION.md`; a stage's Decision Log entry lives in its own file. Rules
that apply to every stage:

- **Stack is decided; do not re-evaluate.** Latest stable Ruby and Rails (Ruby 4.0.7 and
  Rails 8.1.3.1 when planned on 2026-09-17; re-check at Stage 0), PostgreSQL 16+, Solid
  Queue, Solid Cache, Active Storage on local disk, Hotwire, REST/JSON under `/api/v1`,
  Ed25519 via a maintained library, RFC 8785 via an established gem, RSpec, Docker Compose
  with exactly two services.
- **Not in P0:** Redis, Sidekiq, pgvector, a JS framework, event-sourcing frameworks, any
  external service. LLM features are stubbed by default; the demo runs with no API key.
- **Every route under `/api/v1` is described in `Api::Openapi`.** Adding or changing an
  endpoint means editing `read_paths` or `write_paths` in the same commit;
  `spec/requests/api/v1/openapi_spec.rb` fails on any route the document omits and on any
  path it describes that is not routed. `/docs/api` renders that same document with Swagger
  UI, so the public API reference cannot drift either.
- Layout follows `11 §5`: thin controllers, service objects under `app/services/`, no
  epistemic logic in Active Record callbacks, a `Projection` concern for validity windows.
- `pg_advisory_xact_lock` around log appends. Background jobs are idempotent and keyed by
  `(target, seq)`.
- Test priority: security, log, and scoring tests before UI tests. Golden tests cover every
  row of `08 §8` and Watchers `§7` under both models.
- When uncertain, choose the simplest reversible option that preserves the invariants,
  record it in the stage's file under `implementation/`, and continue. Stop only when a requirement is
  impossible or two requirements cannot both hold.
- Success standard: `docker compose up -d && bin/demo` prints PASS for every golden row and
  the replay check, and exits 0.

## Commands

```bash
# Regenerate FULL-SPEC.md after editing any spec source file
bash docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/build-full-spec.sh

# Cross-check scoring spec and configs against the golden values (must print ALL PASS)
python3 docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/reference/reference_scorer.py
```

Also: `docker compose up -d`, `bundle exec rspec`, `bin/rails ledger:genesis`, `bin/rails ledger:release_models`,
`bin/rails ledger:verify`, `bin/rails ledger:replay`, `bin/demo --reset`, `bin/demo --example watchers --reset`,
`bin/demo --example check --reset`, `bin/rails skills:build` (after editing `skills/galedra.md`), `bin/rails admin:grant[email]`, `bin/rails bugs:report`, `bin/rails features:report`, `bin/rails sources:retrieve[ID]` (`LEDGER_RETRIEVAL` on/off).
Benchmarking and profiling (Stage 26, development and test only): `bin/rails 'bench:seed[n]'` (RESET=1),
`bench:report`, `bench:workloads`, `bench:cpu[name]` (MODE=cpu, RUNS=n), `bench:memory[name]`, `bench:rss[name]`,
`bench:boot`. **Write up a run that changed what we believe as a new `docs/profiler/YYYY-MM-DD-<subject>.md`**
and add it to that folder's index; a timing without the corpus and machine it was taken on is not evidence.
The gems are in the development bundle group only, so the production image never carries them;
`LEDGER_PROFILE=1` additionally turns on rack-mini-profiler in development. Seeding a corpus into the test
database breaks the suite until it is rebuilt (`db:drop db:create db:schema:load`), and seeding in development
needs RESET=1, which truncates the log: ask before doing that to someone's working data.
The first account to sign up is the admin; `/admin/users` grants admin and moderator. Personal views and affiliations
(`personal_assessments`, `user_affiliations`, `config/affiliations.yml`), claim reference counts, bug reports, and content
reviews live outside the log and never reach scoring; see `implementation/implemented/personal-views.md`. Reviews are settled
by `Reviews::Consensus` (two agreeing principals, or one uncontradicted after 48 hours), never by the author. `Ledger::Node` is this node's
identity (`LEDGER_NODE_URL`); `/about` and `/api/v1/meta` show the build (`GALEDRA_REVISION` at image build).
**An operational rule for an assistant goes in `app/services/guidance.rb`, never in `skills/galedra.md`.**
A skill is installed once and never re-read, so a rule written there is frozen until every user reinstalls,
which is not realistic in production. `Guidance` is served on every MCP tool result (nothing caches a result)
and at `GET /api/v1/guidance` for hosts that speak REST instead, so a change reaches a connected assistant on
its next call. Bump `Guidance::VERSION` when the words change. Tool descriptions and the `initialize`
instructions repeat some of it but are cached from the last connection and must never be the only home for a
rule; claude.ai is reported to discard `instructions` entirely. The skill keeps only what cannot arrive in a
result: what Galedra is, how to connect, the `galedra:` trigger, search first, and the two rules an assistant
could break before its first call. `spec/lib/skills_spec.rb` fails if an operational rule migrates back into it.
The topic vocabulary is `config/topics.yml`; tags are `TAG_CLAIM` contributions, never edited columns.
The signed-out home page and `/constitution` render `CONSTITUTION.md` through `Governance::Constitution`;
after adding a gem, run `docker compose exec app bundle install` and `docker compose restart app`.
`bin/demo` refuses a log that already holds contributions unless `--reset` is given (development only).
The suite pins RFC 8032 test vector 1 as the system key so its signatures are reproducible, whatever `.env`
carries; seq 0 of `galedra_test` registers it, so rebuild that database (`db:drop db:create db:schema:load`)
if the pinned key ever changes.

## Checking what is left of the usage limits

`claude -p "/usage"` prints them: the session window, the weekly all-model budget, and the
weekly budget for this model, each with its reset time. There is no local file to read and
nothing in `claude auth status`; ask the CLI. Worth doing before a multi-agent run, because
the breakdown it prints is consistently the same story: subagent-heavy sessions at large
context account for nearly all of it, and one `/code-review` at `max` or `ultra` costs more
than a long stretch of ordinary editing. A review that dies halfway leaves findings applied
but unverified, which is worse than not starting it.

## Git

Commit messages are one short imperative sentence in sentence case with no type prefix,
matching the existing history. Tags are annotated, `stage-NN-slug`, plus `v0.1.0` at the
P0 Definition of Done.

## Decisions reserved for the owner

Decided 2026-09-19: the licence stack in `docs/LICENSE-POLICY.md` is adopted (AGPL-3.0-or-later
code, Apache-2.0 protocol and schemas, CC BY 4.0 docs, ODbL-1.0 database, CC0-1.0 records; see
`NOTICE`).

Implement the conservative reading already in the spec and flag these when relevant:
adopting amendments P-1 through P-6 (P-5, the ledger runs no model, is Invariant 18; P-6, money buys no part of the record, is stated on /contact); both await adoption; who holds the system key and appoints moderators; whether `LEGAL` claims are scored before
a legal model exists; whether `TEXTUAL` stays a distinct claim type.
