# How this project is actually worked on

Written 2026-09-20 after a long session whose most valuable output was not code.
`CLAUDE.md` says what the rules are. This says how the work is done, what has
caught real defects, and which mistakes have been made more than once.

## Keep this file current, or it becomes another thing that misleads

**This file is maintained, not archived.** A session that discovers a practice
worth repeating, or finds one here no longer true, updates it in the same session
— the same rule the record folders follow, for the same reason: a note that has
quietly stopped being true is worse than no note, because it is trusted.

- **Add** a practice once it has caught something real, and say what it caught.
  A rule with its evidence attached can be judged later; a bare instruction
  cannot.
- **Delete** what has been superseded. This is not a changelog and it does not
  grow monotonically. `implementation/` holds the history; this holds what is
  currently worth doing.
- **Mark thin evidence as thin.** Several entries below rest on a single long
  run. Say so, so a later session knows which claims to test rather than inherit.
- **Correct it when it is wrong**, including when it was written confidently.
  Most of the mistakes listed here were made while sounding certain.

The point of the file is that what was learned survives a new context window. It
only does that if each session leaves it truer than it found it.

## The loop that finds real defects

**Connect a chat assistant over MCP, give it a real job, and watch from the
server side.** Not a scripted test — an actual task, with the person asking for
what they actually want.

This found, in one session: a two-hour transcript recorded as thirteen claims; a
livelock handing out the same unworkable task forever; page renders at 18
seconds; and the worst one, a scorer counting a transcript's own sentence as
corroboration for the claim taken out of it, so 24 of 29 "supported" claims rested
on the source agreeing with itself.

**The assistant files what it finds, in the application.** `report_bug` and
`request_feature` are MCP tools; reports land in `bug_reports` and
`feature_requests` and are read at `/bug_reports` and `/feature_requests`
(moderators and admins). Each row has a status — `OPEN`, `DONE`, `IGNORED` — and
a **resolution**, because a closed list with no reasons tells the next reader
nothing about whether a thing was fixed, was working as intended, or was set
aside.

`Guidance::ASK` asks for a report **without being asked**, including when the job
got done but the route was wasteful or confusing. That wording matters: while it
was framed around being *blocked*, an assistant paid several hundred redundant
words on every one of a hundred calls and said nothing until the owner told it
to. It is not a complaint and not an interruption; the assistant is the only one
who can see what working here is like.

**The thing to take from this:** watching produced the performance numbers and the
livelock. It did not produce the scoring fault, and could not have. Monitoring
counts and states never asks *whether a state is deserved* — an assistant using
the product asked that, about a claim it had itself just scored, and reported
against its own work.

### Watching well

- **Sample on a call's completion, not its notification.** The log line fires when
  a request *starts*, and writes here commit in large atomic chunks; a count taken
  mid-write is a snapshot of an uncommitted transaction. Reading one as a stall
  happened twice, once loudly.
- **A filter narrow enough to look tidy is narrow enough to discard what you
  needed.** The first monitor matched failures and slow *MCP* calls, so the worst
  performance problem on the node was invisible for a whole run while everything
  read as clean. Twice, grepping only for a test's count line threw away the name
  of the flaky spec.
- Watch for `outcome=refused` as well as errors: a refusal now carries the field
  and the expected format, which is how two client-side faults were diagnosed.

## The four record folders

Each holds one file per thing, and **every finding carries a status updated in
place** — a log that still says a thing is broken after it is fixed misleads the
next reader.

| Folder | One file per | Holds |
|---|---|---|
| `implementation/` | stage (`planned/` → `implemented/`) | the plan, then its Decision Log |
| `docs/experiments/` | run against something real | what was tried, what the database said, what it found, **what the watcher got wrong** |
| `docs/profiler/` | profiling run | conditions, machine, corpus, numbers |
| `docs/security/` | audit | findings, dismissals, what held up |

A stage's correction belongs in **that stage's own file**, in the existing
Decision Log format. An experiment's last section is what the observer got wrong,
because an observer who misreads a run is part of what the run revealed.

## Graphify

Installed (`uv tool install graphifyy`, CLI `graphify`, skill at
`~/.claude/skills/graphify/`). Local, no network egress, Apache-2.0/MIT.

**Worth it for one thing:** documents naming symbols that do not exist. It found a
stage marked implemented naming `Audits::ApplyResult`, a class that has never
existed in code — the same documentation-drift class that caused four separate
bugs, in a place nobody was looking.

**Not worth it for:** structure you already have in `CLAUDE.md`, and anything about
whether a *description* matches behaviour — a tool description is a string
literal and parses fine however wrong it is.

**Known gap:** the dangling-edge count appears in build console output and is
written to no artefact. `graph.json` ships cleaned and `GRAPH_REPORT.md` never
mentions it, so the finding is not reproducible from the files. Fix by writing
`graphify-out/diagnostics.json` with the actual edge list before cleanup.

### The doc-drift sweep, and its four false positives

Extract `Foo::Bar` names from `implementation/**.md`, resolve each, report the
misses. **Four filters are required, all learned by getting it wrong:**

1. **Resolve through Ruby, not grep.** A constant defined inside its own module is
   never written qualified, so `Guidance::OUTLINE` looks absent.
2. **Allow underscores** in the name pattern. `[A-Za-z0-9]*` silently truncates
   `PROJECTION_MODELS` to `PROJECTION`, producing a confidently wrong report.
3. **Skip rejected-name prose.** "renamed from `Ledger::Digest` because it shadowed
   Ruby's `Digest`" is the Decision Log working, not drift. Correcting it would
   delete the record.
4. **`spec/` is not eager-loaded**, so constants in `spec/support/` resolve to
   nothing and look absent.

Of 118 names referenced across 46 stage plans, two were genuine drift.

## Mistakes made more than once

**Instructions drifting from behaviour — four times.** Stage 30 added a `reading`
field the tool schema never gained, so the feature was unreachable. The size rule
was fixed in the skill while `record_investigation` carried no ceiling at all.
Stage 34 opened self-checking while `next_task` still forbade it. The timestamp
format lived only in a tool schema and not in the guidance a task-worker reads.
Every time the code was right, the thing an assistant reads was wrong, and **the
suite passed**. Nothing tests that an instruction matches the behaviour it
describes. Treat the tool description and the guidance as *part of* any change
that alters what an assistant may do, not documentation of it.

**Theorising instead of measuring.** A container clock and a host clock read
eleven hours apart; that was elapsed time, not skew, and one command would have
shown all four clocks identical to the second. An evidence-grouping theory
survived two paragraphs of confident reasoning and was wrong. Measure first; it is
nearly always one command.

**Repeating a lesson already written down.** A Python heredoc searching for
`"\\nend"` finds a literal backslash, returns −1, and silently truncates a file.
This happened, was recorded in the experiment log *along with the note that an
assertion on the search would catch it*, and then happened again hours later
because the assertion was never added. Writing a lesson down is not acting on it.

**Over-correcting on a word.** Told the tool was "graphiphy", not "graphify", the
install was declared wrong before checking whether the new name resolved. It did
not. The retraction was as hasty as the thing it retracted.

**Scripts producing confident wrong lists.** The drift sweep shipped three defects
at once and its output was relayed as fact. Verify a script's output against two
known cases — one that should appear and one that should not — before believing
any of it.

## Scoring, briefly, because it is the sharp edge

Scores are **versioned**: same seq and model give a byte-identical trace, so a
scorer change needs a new model version, new goldens, and a reference-scorer pass.
Both `0.2.0` behaviours read config keys `0.1.0` does not declare, which is what
lets the old model stay reproducible.

**Releasing a model used to change the default silently**, because `default_model`
took the newest. `LEDGER_DEFAULT_MODEL` now pins it. Switching what a visitor sees
is a decision, not a side effect of a rake task.

**Never adjust a golden to make something pass.** When the reference scorer and a
prediction disagree, find which side is wrong. Predicting expected values before
running them caught a real subtlety: collapsing a duplicate lowers stability as
well as probability, because two groups meet the minimum for HIGH and one does
not.

## Standing unknowns

- An intermittent suite failure, ~1 in 6 runs, seen on five different specs,
  always passing in isolation and never seed-reproducible. Unattributed.
- Six extra tasks in the first replay, unexplained; only totals were captured
  beforehand. **Take a `TableDigest` before a replay, not only after.**
- `ledger:replay` needs an idle node: it truncates projections and rebuilds. It
  caught projections edited outside the log, which is the whole reason it exists.
