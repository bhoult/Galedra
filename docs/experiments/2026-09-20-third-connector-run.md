# A connected assistant works the same outline again, after the second run's fixes

The retry the second run was fixed for. Same outline
(`1623097f-53f3-8a4f-bafb-6d522b75735b`), same instruction — *work open tasks in Galedra* —
against a node carrying every fix from
[the second run](2026-09-20-second-connector-run.md). **Live while this is being written**;
findings are added as they settle and their statuses are updated in place.

## What was tried

- **Instruction to the assistant:** "work open tasks in Galedra on
  https://local.galedra.org/sections/1623097f-53f3-8a4f-bafb-6d522b75735b".
- **Client:** claude.ai, MCP era `2026-07-28`, connected as a named token after a
  reinstall earlier in the day. A second anonymous caller (`curl/8.18.0`) probed the same
  endpoint with an all-zeros UUID; unrelated to the run and refused cleanly.
- **Node:** development, commit `0e54800` at the start of the window, `ade8048` by the end
  of it. The `bench:seed` container is still running against `galedra_bench` throughout, so
  the host is loaded.
- **Watched from:** `docker logs -f galedra-app-1` filtered to MCP calls, completions and
  refusals, plus direct reads of `bug_reports`, `feature_requests` and `report_messages`.

## What happened

Counted at 21:0x UTC, from 19:30 UTC:

| | |
|---|---|
| Task assignments submitted | 3 |
| Evidence links appended | 6 |
| Report turns by the assistant | 22 |
| Report turns by the maintainer | 26 |
| Bug reports | 10 CLOSED, 3 ANSWERED |
| Feature requests | 10 CLOSED |

**The reports are where the run went.** Twenty-two assistant turns against three task
submissions: the conversation channel shipped this morning is now the busiest write path in
the session, and the work it displaced was queue work. Whether that is a cost or the point
is the open question of this run — the reports it filed were worth more than three
qualifier checks, but nothing in the design decided that trade, it simply happened.

## Findings

- **A too-long reply reached the client as a bare HTTP 422. Status: FIXED 2026-09-20
  (`0e54800`).** `ReportMessage` validated the body at 2,000 characters and raised
  `ActiveRecord::RecordInvalid`; nothing caught it, so an HTML Rails exception page arrived
  over a protocol that expects a tool result. The assistant was refused twice, isolated the
  boundary itself — an 86-character body on the same report id with the same `satisfied`
  value went through instantly — and narrowed the limit to between ~1,700 and ~2,400
  characters before filing `01a0c097`. It then split its finding to get it recorded, losing
  about half of the first attempt.
  The repair is two parts, and the second is the one that matters: `MAX_CHARS` is 5,000 and
  `Triageable#respond!` clips and reports `clipped` instead of raising, **and** the MCP
  handler now turns any `RecordInvalid` into a readable refusal. This is the same fault as
  the morning's schema-invalid refusals — a correct decision the caller cannot read — and it
  was fixed there for one path rather than for the class. The filer found the rest of the
  class by using it.
- **A count of everyone's work read as a count of yours, three times in one day. Status:
  FIXED 2026-09-20 (`ade8048`).** The assistant put the three together and that is the
  finding: `open` vs. what a worker can lease, `content_reviews_pending` vs.
  `content_reviews_for_you`, `open` vs. `answers_wanted`. The owner met the same edge from
  the other side — the outline reported 742 open tasks, over a hundred were worked, and it
  came back 740. Every one of those numbers is true of the queue and none of them answers
  the question being asked.
  `list_tasks` now returns `open_for_you` and `answers_wanted_for_you` beside the totals:
  what this caller or its principal has not already leased or answered. Most tasks want
  three independent answers, so the queue total is *right* not to move on a submission,
  which is exactly why it cannot be the number quoted to a person. `Guidance::WORK` says
  which to quote (`VERSION 2026-09-20.9`), so it arrives on the next call rather than at the
  next reinstall. A caller holding nothing gets the same figure twice rather than a missing
  field.
- **The quote verifier's NOT_FOUND is publisher markup, not a missing body. Status: OPEN
  (`01a0c01e`), planned as [Stage 36](../../implementation/implemented/stage-36-interrupted-quotes.md).** The hypothesis on this side was that qz.com
  served a shell. The assistant fetched the page and refuted it: 331,009 bytes is a rendered
  article, and the sentence reads `Nvidia<a href="/quote/NVDA">$NVDA</a>'s equity
  investments`. Confirmed mechanically from `Sources::Retrieve.extract_text`, which does
  `.gsub(/<[^>]+>/, " ")` — anchor text is kept and tags become spaces, so the excerpt is
  compared against `Nvidia $NVDA 's`. Normalization cannot close that: the difference is an
  interpolated token, not typography.
  It also reinterprets the bucket counts. NORMALIZED firing 3 times in 58 was read here as
  "failures are absence"; it fits equally that normalization rarely rescues *because* it only
  handles typography, while the common real failure is markup injected mid-sentence —
  tickers, inline links, footnote markers — which looks exactly like absence on a fully
  present page. Left OPEN deliberately: its preferred fix is a verdict distinct from
  `NOT_FOUND` rather than stripping anchor text to force a match, which is right, because
  stripping would make the verifier lie in the other direction.
  Stage 36 is that verdict: three deterministic renderings tried in a fixed order, with
  `INTERRUPTED` reported when the match comes from the one that elides inline elements. The
  filer's argument is what makes it admissible — elision only removes text, so a match means
  every character of the excerpt came from outside an inline element and no quotation can be
  made to span words it does not contain. Its opposite-meaning example is acceptance test 2.
  **Its scope question rested on a false premise, in its favour.** It asked whether
  `INTERRUPTED` should count as verified *for scoring*; `SourceRetrieval` is read by the card,
  the presenter, `Tasks::Answer` and two views, and by nothing under `scoring/` or `audits/`.
  Galedra's own fetch has never been a scoring input in either direction, so no model version
  and no golden moves. The real question is the narrower one it also asked — what a worker
  should do when the packet says `INTERRUPTED` — which is a `Guidance` line, not a config.
- **`CLAIM_NOT_CURRENT` arrived without the successor id it is supposed to carry. Status:
  OPEN, not reproduced.** `add_evidence` against `1d9b1770-efb7-8e03-a6da-661439246ce6` was
  refused with `"claim is merged"` and no `into`. The whole point of `not_current_reason`
  (`6ea6a04`, 19:03 UTC, before this call) is to name where the claim went. The claim has
  carried `merged_into_id = a12ea91c-…` since the merge at 00:59:30, the successor is ACTIVE
  and accepted, the log truncates details at 80 characters and the full message is 76, and
  re-running `current_claim!` against that exact claim now returns the id. So the gap is
  real and its cause is not established — recorded as observed rather than explained,
  because the alternative is a plausible story. Three `NOT_FOUND` calls followed on ids that
  do not exist, which is the cost the successor id exists to prevent, though it is not shown
  that they were guesses at it.

- **The fix verified itself from the other side, live.** The filer re-ran `list_tasks` after
  `ade8048` and reported `open 730` against `open_for_you 557`, `answers_wanted 2015` against
  `answers_wanted_for_you 1669`, and `content_reviews_pending 66` against
  `content_reviews_for_you 0` — with `Guidance` arriving as `2026-09-20.9` on the same call,
  so a rule written thirty minutes earlier reached a live session with no reinstall. That is
  the Stage 31 delivery path doing exactly what it was built for, and the contrast worth
  keeping is the four tool-schema changes in the same window that cannot arrive that way.
  It closed `01a0c085` satisfied, and corrected my closing line in the unflattering
  direction: it had a cheaper check available — `next_content_review` returning
  `available false` — and reached for a coincidence instead of asking what the two numbers
  counted.
- **The content review queue cannot drain on a one-assistant node. Status: OPEN, by design,
  worth stating.** All 66 pending items are authored by the single connected principal, so
  `for_you` is 0 and will stay 0: `Reviews::Consensus` needs a different principal, and
  `settle_lone!` needs a first verdict that nobody can cast. The escape is `/admin/content_reviews`,
  where an admin settles them by hand — which is the page the owner opened at 21:06, and the
  page that was spending 30 statements to render (fixed below).
- **`/admin/content_reviews` asked per row. Status: FIXED 2026-09-20 (`ddbafad`).** Caught
  from a log line rather than a report: 72 queries in 53ms, of which 41.8ms was view time.
  Each pending row asked `Reviews::Consensus.status` for its own verdicts and each redacted
  row asked for the reviewer's email address. `Consensus.status_for` batches the first and
  the controller batches the second: **30 statements to 5 on 24 pending items**, verified by
  running the new spec against the old code. The listing is capped at 200, so the shape was
  200 statements away from an admin's first busy day.

## What was wrong in the watching

- **I built the shell hypothesis on the bucket counts and read past the byte count in my own
  paragraph.** 331,009 bytes was in the same log line as the NORMALIZED tally. A shell is
  small. The assistant, working from a different fetcher, spotted it immediately.
- **I fixed a fault for the path I had been shown rather than for its class.** `6ea6a04`
  made refusals readable on the tool paths in the second run's report; `respond_to_report`
  was not one of them, and the same failure was waiting there four hours later. The global
  `RecordInvalid` rescue is what should have been written the first time.
- **I chased the missing successor id for six queries past the point of usefulness.** The
  measurements ruled out truncation, stale data and a stale process, and then I kept
  proposing mechanisms. `docs/CONTEXT.md` has a standing entry for this; it earned another
  instance.
