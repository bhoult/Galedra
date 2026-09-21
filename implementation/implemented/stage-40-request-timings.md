# Stage 40 — The node records how long it took, and how often it was asked

**Status:** built 2026-09-21 · tagged `stage-40-request-timings`

**Tag:** `stage-40-request-timings` · **Spec:** 06 §2 (reads), 11 §2 (one app, one
database, no external service), 11 §5 (layout), Invariant 11 (untrusted text stays inert),
Invariant 12 (moderation is visible), Article XXII (the system reveals its own weaknesses)

Goal: make a slow page findable from the node itself, and make it possible to tell whether
a slow page is worth fixing.

## Why

Three defects were found on 2026-09-21 — the outline page at 5,343 statements, the
weaknesses report building 3,500 entries to show fifty, and a 2 KB trace read 200,000 times
to get at nine fields. **Not one of them was visible in the Rails log**, and each was found
by hand-instrumenting a script.

The reason is specific and worth stating: the Rails log records duration and it does not
record **statement count**. `Completed 200 OK in 2834ms (Views: 120.1ms | ActiveRecord:
1900.2ms)` says a page was slow; it does not say it issued five thousand queries. Every one
of those findings came from counting statements.

Three further gaps:

- The log is unaggregated text. "Is p95 on the claim page creeping up" is a grep and a hope.
- In a container it is ephemeral unless shipped somewhere, and `HOSTING.md` §15 sets no
  retention for it.
- **A timing without the corpus it was taken against is not evidence** —
  `docs/profiler/README.md` says exactly that. A log line cannot say "this was at 100,024
  claims, head 1,019,861". A row can.

And the question the owner actually asked, which no log answers at all: **how often is this
endpoint called?** A page that takes two seconds and is asked for once a day is not the same
problem as one that takes 300 ms and is asked for constantly. Without call counts, "which
slow thing should I fix" is guesswork.

## What this is not

`HOSTING.md` §15 says "do not build a large observability stack initially", and that stands.
This is one subscriber and two tables in the database that already exists. No agent, no
external service, no time-series store, nothing to run alongside the app.

**It records no client IP and no user identity.** Galedra deliberately holds no client IPs;
that decision is not weakened for a performance table. What is recorded is the controller
action, the numbers, and the request id the Rails log already tags — enough to find the
request in the log, and not enough to identify who made it.

## The shape

Two tables, because they answer two different questions.

- **`request_tallies`** — one row per `(action, hour)`, upserted on **every** request:
  `calls`, `total_ms`, `max_ms`, `statements`, `slow_calls`. This is the call-count half:
  it says what the node is actually asked for, and one indexed upsert per request is the
  whole cost.
- **`request_samples`** — one row per request **over a threshold**, which by definition is
  rare: `action`, `method`, `duration_ms`, `db_ms`, `view_ms`, `statements`, `status`,
  `head_seq`, `request_id`, `recorded_at`. The head seq is what makes a row still mean
  something in a month's time.

Both are outside the log, like `claim_scores`, `bug_reports` and `personal_assessments`:
derived operational data, absent from `Ledger::TableDigest`, deletable without loss.

**Off unless asked for.** `LEDGER_REQUEST_METRICS` gates the whole thing; unset means not a
single extra statement. It is set in `.env` now so this node records, and it is documented
in `.env.example` as off.

**Retention, two ways.** Age — `bin/rails metrics:prune` (`KEEP_DAYS`, default 30), on the
nightly schedule. And resolution — `bin/rails 'metrics:clear[claims#show]'` drops what is
recorded for one action, which is what you want the moment you have fixed it: the old rows
are a record of a problem that no longer exists, and leaving them makes the report lie about
where the time is going.

## Deliverables

1. `request_tallies` and `request_samples`, and models for them.
2. `RequestMetrics::Recorder`, subscribed to `start_processing.action_controller` (to reset
   the statement counter), `sql.active_record` (to count) and `process_action.action_controller`
   (to record), all of it behind `RequestMetrics.enabled?`.
3. `bin/rails metrics:report` — by total time, by call count, and the slowest samples.
4. `bin/rails metrics:prune` and `bin/rails 'metrics:clear[action]'`, with
   `PruneRequestMetricsJob` on the nightly schedule.
5. `.env` set to on for this node; `.env.example` documents it as off.
6. Specs: nothing recorded when the flag is off; a tally per request and a sample only over
   the threshold when it is on; the statement count is the real one; pruning by age and by
   action.

## Acceptance

1. With `LEDGER_REQUEST_METRICS` unset, a request issues no statement against either table.
2. With it on, every request increments its action's tally for the hour, and a request over
   the threshold also leaves one sample carrying the statement count and the head seq.
3. The recorded statement count matches what a subscriber counts independently.
4. `metrics:prune` removes rows older than `KEEP_DAYS` and nothing newer;
   `metrics:clear[action]` removes that action's rows and nothing else.
5. No client IP and no user identity is recorded anywhere in either table.
6. `ledger:replay` produces identical digests: neither table is a projection.

## How this stage closed (2026-09-21)

### What was resolved

The node can now say what it was asked for, how long it took, and **how many statements it
issued** — the number the Rails log has never carried and the one that found every slow path
on 2026-09-21.

It earned its keep on the first run. Three page loads on the dev node, at **304 claims**:

| action | calls | mean ms | max ms | statements/call | slow |
|---|---|---|---|---|---|
| `weaknesses#index` | 1 | 14,335 | 14,335 | **17,552** | 1 |
| `claims#index` | 3 | 708 | 1,916 | **825** | 1 |
| `home#index` | 1 | 17.5 | 17.5 | 5 | 0 |

Fourteen seconds and seventeen thousand statements to draw the weaknesses page on a node
with three hundred claims, and two thousand statements for one claims index. Neither was
visible in the log before this; both are now a row with the head seq beside them.

### How

- `request_tallies`, one row per `(action, hour)`, upserted on **every** request with
  `calls`, `total_ms`, `max_ms`, `statements` and `slow_calls`. One statement, and it is the
  whole cost on the fast path. The upsert adds and takes `GREATEST` in SQL, so two workers
  recording the same hour cannot lose each other's counts.
- `request_samples`, one row per request over `SLOW_MS` (500) **or** `MANY_STATEMENTS`
  (200). The second threshold is the one that finds defects: an N+1 on a small corpus is
  fast and still wrong. Each row carries the head seq, so it still means something in a
  month.
- Three subscribers in `config/initializers/request_metrics.rb`:
  `start_processing.action_controller` resets a thread-local counter,
  `sql.active_record` increments it, `process_action.action_controller` writes the rows
  **after** the response. A failure in the recorder is caught and logged: a broken metric
  must never break a page.
- `LEDGER_REQUEST_METRICS` gates all of it, read per request so it can be flipped without a
  restart. Off in `.env.example`, on in this node's `.env`, and **forced off in
  `spec/rails_helper.rb`** — Docker Compose passes `.env` into the container, and an extra
  upsert per request breaks the statement-count budgets that guard against N+1s. That is the
  same trick, and the same reason, as the pinned system key two lines above it.
- Retention both ways: `PruneRequestMetricsJob` nightly at 3:40 (`KEEP_DAYS`, default 30),
  and `bin/rails 'metrics:clear[claims#show]'` for when a path has been fixed.
- `bin/rails metrics:report` prints three tables: where the time goes, what is most asked
  for, and the slowest requests kept.
- `spec/requests/request_metrics_spec.rb` holds it: nothing recorded when the flag is off, a
  tally for every call and a sample only over the threshold, the recorded statement count
  matching an independent one, no column or value that could identify anybody, and both
  kinds of pruning.

### What remains

- **No page for it.** `metrics:report` is a terminal command, so this is a maintainer's
  tool, not something a moderator or the owner can look at from the site. An admin page
  under `/admin` would be a small addition and is the obvious next step if it gets used.
- **Hourly is the finest grain.** A burst inside an hour is invisible; the tally says the
  hour was busy, not which minute. That is deliberate — a row per request would be the
  observability stack `HOSTING.md` §15 says not to build — but it is a real limit.
- **Nothing alerts.** A page that gets slower is recorded and nobody is told. Whether that
  should change belongs with §15's monitoring decisions, not here.
- **It records controller actions only.** Jobs, the MCP tool calls inside a request, and
  `bin/rails` tasks are not covered. The MCP tools run through a controller, so they appear
  as one action rather than per tool, which is coarser than it could be.
- **`HOSTING.md` §15 has not been updated** to mention it. It should be, next time that file
  is touched: the monitoring list there is where an operator looks first.
