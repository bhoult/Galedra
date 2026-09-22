# IMPLEMENTATION.md

Staged implementation plan for the Galedra POC, plus the running decision log the spec
requires (`10-agent-handoff.md`, "Required Artifacts"). The plan is fixed; the decision
log grows as stages are executed.

Spec paths below are relative to `docs/epistemic-ledger-poc-spec-v4/epistemic-ledger-poc/`.
The stages follow the phase order in `07-poc-roadmap-and-acceptance.md` exactly, with the
larger phases split so each stage is a bounded unit of work that ends in a git tag.

## Layout

```text
IMPLEMENTATION.md                 this index: how a stage is executed, the stage table, decision-log rules
implementation/planned/           one file per stage not yet built: its plan
implementation/implemented/       one file per stage built: its plan, then its Decision Log entry;
                                  plus dated entries for work done between stages
```

A stage file is the unit of reading: open the one for the stage in hand, not the folder.

## How a stage is executed

1. Re-read the spec sections listed for the stage before writing code.
2. Implement the deliverables. Do not pull work forward from a later stage.
3. Every acceptance item for the stage has an automated test. All tests pass locally and in CI.
4. Write this stage's Decision Log section in the stage's own file: versions, choices
   made, assumptions, any deviation from the spec with its reason. For a stage that
   touches scoring, identity, reputation, moderation, visibility, or history, also record
   the answers to the ten Constitutional Test questions (`12-constitution.md`). Then move
   the file from `implementation/planned/` to `implementation/implemented/`, set its
   status line, and update the table below.
5. Commit on `master` (one or more commits), then tag and push:

   ```bash
   git tag -a stage-NN-slug -m "Stage NN: <title>"
   git push origin master --tags
   ```

   Tag names are zero-padded so they sort: `stage-00-skeleton` … `stage-11-demo`.
   Stage 11 additionally gets `v0.1.0`, marking the P0 Definition of Done. P1 stages
   continue the numbering (`stage-12-assistants` …).
6. A stage is not done until its tag exists. The next stage does not start until asked.

**Ruby and Rails: always the latest stable release.** At planning time that is Ruby 4.0.7
and Rails 8.1.3.1 (checked against ruby-lang.org and rubygems.org on 2026-09-17). Stage 0
re-checks both, installs whatever is latest then, and pins them. If Rails does not yet
support the newest Ruby line, use the newest Ruby the Rails release supports and record
that in the Decision Log.

Environment on the development machine at planning time: Ruby 3.4.5 via asdf (the asdf
ruby plugin is stale and lists nothing newer than 3.4.5), Bundler 2.6.9, Docker 29.1.3
without the compose plugin, no local PostgreSQL, Node 22, Python 3.14. Rails is not
installed. Stage 0 records the exact versions it ends up using.

## Stages

| Stage | Title | Status | File |
|---|---|---|---|
| 0 | Skeleton | implemented | [implementation/implemented/stage-00-skeleton.md](implementation/implemented/stage-00-skeleton.md) |
| 1 | Canonicalization, hashing, and keys | implemented | [implementation/implemented/stage-01-crypto.md](implementation/implemented/stage-01-crypto.md) |
| 2 | The contribution log | implemented | [implementation/implemented/stage-02-log.md](implementation/implemented/stage-02-log.md) |
| 3 | Evidence graph projections | implemented | [implementation/implemented/stage-03-projections.md](implementation/implemented/stage-03-projections.md) |
| 4 | Quarantine, takedown, and the moderation log | implemented | [implementation/implemented/stage-04-moderation.md](implementation/implemented/stage-04-moderation.md) |
| 5 | Deterministic scoring | implemented | [implementation/implemented/stage-05-scoring.md](implementation/implemented/stage-05-scoring.md) |
| 6 | Snapshots, score cache, and score endpoints | implemented | [implementation/implemented/stage-06-snapshots.md](implementation/implemented/stage-06-snapshots.md) |
| 7 | Audits and reputation | implemented | [implementation/implemented/stage-07-audits.md](implementation/implemented/stage-07-audits.md) |
| 8 | Tasks, leases, packets, and the example agent | implemented | [implementation/implemented/stage-08-agents.md](implementation/implemented/stage-08-agents.md) |
| 9 | Why, summaries, answer cards, and weaknesses | implemented | [implementation/implemented/stage-09-answers.md](implementation/implemented/stage-09-answers.md) |
| 10 | Hotwire UI | implemented | [implementation/implemented/stage-10-ui.md](implementation/implemented/stage-10-ui.md) |
| 11 | Seeded demos and P0 Definition of Done | implemented | [implementation/implemented/stage-11-demo.md](implementation/implemented/stage-11-demo.md) |
| — | P1 — Assistants as contributors (rules for Stages 12+) | context | [implementation/implemented/p1-assistants.md](implementation/implemented/p1-assistants.md) |
| 12 | Connected assistants | implemented | [implementation/implemented/stage-12-assistants.md](implementation/implemented/stage-12-assistants.md) |
| 13 | Record an investigation | implemented | [implementation/implemented/stage-13-investigate.md](implementation/implemented/stage-13-investigate.md) |
| 14 | MCP, OpenAPI, and the skill | implemented | [implementation/implemented/stage-14-mcp.md](implementation/implemented/stage-14-mcp.md) |
| 15 | Topics | implemented | [implementation/implemented/stage-15-topics.md](implementation/implemented/stage-15-topics.md) |
| 16 | OAuth for connectors | implemented | [implementation/implemented/stage-16-oauth.md](implementation/implemented/stage-16-oauth.md) |
| 17 | Source retrieval by a trusted job | implemented | [implementation/implemented/stage-17-retrieval.md](implementation/implemented/stage-17-retrieval.md) |
| 18 | Work open tasks from a connector | implemented | [implementation/implemented/stage-18-work-tasks.md](implementation/implemented/stage-18-work-tasks.md) |
| 19 | Correct what is recorded, from a connector | implemented | [implementation/implemented/stage-19-corrections.md](implementation/implemented/stage-19-corrections.md) |
| — | Stages 20–22 — Large sources: outlines (shared goal and vocabulary) | context | [implementation/implemented/stages-20-22-outlines.md](implementation/implemented/stages-20-22-outlines.md) |
| 20 | Sections and placements in the log | implemented | [implementation/implemented/stage-20-sections.md](implementation/implemented/stage-20-sections.md) |
| 21 | Large requests from a connector | implemented | [implementation/implemented/stage-21-large-requests.md](implementation/implemented/stage-21-large-requests.md) |
| 22 | Sharing and following an outline | implemented | [implementation/implemented/stage-22-outline-share.md](implementation/implemented/stage-22-outline-share.md) |
| 23 | Federation readiness | implemented | [implementation/implemented/stage-23-federation-ready.md](implementation/implemented/stage-23-federation-ready.md) |
| 24 | Admins, help, and navigation | implemented | [implementation/implemented/stage-24-admin-nav.md](implementation/implemented/stage-24-admin-nav.md) |
| 25 | Inferences: recorded reasoning steps | implemented | [implementation/implemented/stage-25-inferences.md](implementation/implemented/stage-25-inferences.md) |
| 26 | Capacity: seeding, profiling, and the pages that scan | planned | [implementation/planned/stage-26-capacity.md](implementation/planned/stage-26-capacity.md) |
| 27 | Which model did this, and which work needs which model | planned | [implementation/planned/stage-27-model-provenance.md](implementation/planned/stage-27-model-provenance.md) |
| 28 | Export and import a claim, a topic, or an outline | planned | [implementation/planned/stage-28-export-import.md](implementation/planned/stage-28-export-import.md) |
| 29 | Noting a logical fallacy | planned | [implementation/planned/stage-29-fallacy-notes.md](implementation/planned/stage-29-fallacy-notes.md) |
| 30 | The whole text, readable in Galedra | implemented | [implementation/implemented/stage-30-section-text.md](implementation/implemented/stage-30-section-text.md) |
| 31 | The rules on the wire, not in the skill | implemented | [implementation/implemented/stage-31-guidance-on-the-wire.md](implementation/implemented/stage-31-guidance-on-the-wire.md) |
| 32 | Speaking modern MCP as well as legacy | implemented | [implementation/implemented/stage-32-modern-mcp.md](implementation/implemented/stage-32-modern-mcp.md) |
| 33 | Take an outline away as a file you can read | planned | [implementation/planned/stage-33-static-export.md](implementation/planned/stage-33-static-export.md) |
| 34 | A person can finish their own investigation | implemented | [implementation/implemented/stage-34-first-pass-self-check.md](implementation/implemented/stage-34-first-pass-self-check.md) |
| 35 | Provenance is not corroboration | implemented | [implementation/implemented/stage-35-provenance-is-not-corroboration.md](implementation/implemented/stage-35-provenance-is-not-corroboration.md) |
| 36 | A quotation interrupted by markup is not one that is missing | planned | [implementation/planned/stage-36-interrupted-quotes.md](implementation/planned/stage-36-interrupted-quotes.md) |
| 37 | A thread on a determination | implemented | [implementation/implemented/stage-37-threads-on-determinations.md](implementation/implemented/stage-37-threads-on-determinations.md) |
| 38 | A score that has not changed should not be recomputed | built | [implementation/implemented/stage-38-score-cache-keying.md](implementation/implemented/stage-38-score-cache-keying.md) |
| 39 | The read paths ask one row at a time | built | [implementation/implemented/stage-39-read-paths-one-row-at-a-time.md](implementation/implemented/stage-39-read-paths-one-row-at-a-time.md) |
| 40 | The node records how long it took, and how often it was asked | built | [implementation/implemented/stage-40-request-timings.md](implementation/implemented/stage-40-request-timings.md) |
| 41 | What a worker finds and cannot record | mostly built; one owner decision | [implementation/planned/stage-41-what-a-worker-cannot-record.md](implementation/planned/stage-41-what-a-worker-cannot-record.md) |
| 42 | Meet the caller where the decision is made | planned | [implementation/planned/stage-42-meet-the-caller-where-the-decision-is.md](implementation/planned/stage-42-meet-the-caller-where-the-decision-is.md) |

Work done between stages, each with its own dated entry:

- [After P0 — Landing page and visual design](implementation/implemented/after-p0-landing-page-and-visual-design.md) (2026-09-18)
- [After Stage 14 — Serving from home](implementation/implemented/after-stage-14-serving-from-home.md) (2026-09-18)
- [After Stage 14 — The paste flow](implementation/implemented/after-stage-14-the-paste-flow.md) (2026-09-18)
- [After Stage 14 — The write link](implementation/implemented/after-stage-14-the-write-link.md) (2026-09-18)
- [After Stage 14 — Adoption](implementation/implemented/after-stage-14-adoption.md) (2026-09-18)
- [Claim references — how often a claim is met](implementation/implemented/claim-references.md) (2026-09-19)
- [Personal views, affiliations, and content review](implementation/implemented/personal-views.md) (2026-09-19)
- [Work done per contributor, and the contributors list](implementation/implemented/contributors-tally.md) (2026-09-19)

## Decision Log

Append-only. One dated entry per stage, added when the stage is executed. Each entry
records: exact versions, choices and their alternatives, assumptions, deviations from the
spec with reasons, and Constitutional Test answers where the stage requires them.

Entries live in the stage files listed above. The one entry that precedes every stage:

### Planning (2026-09-17)

- Test framework: RSpec, matching the owner's other Rails projects (`07` Phase 0 leaves
  the choice open).
- Tag scheme: annotated tags `stage-NN-slug`, plus `v0.1.0` at Stage 11.
- Work happens on `master`; no long-lived branches for the POC.
- The compose plugin is missing on the development machine; Stage 0 installs
  `docker-compose-plugin` (or the standalone `docker compose` binary) and records which.
- Ruby and Rails: latest stable at each stage's start, per the owner's instruction on
  2026-09-17. Planning-time values: Ruby 4.0.7, Rails 8.1.3.1. The spec's "Rails 8.x" is
  satisfied by 8.1.
