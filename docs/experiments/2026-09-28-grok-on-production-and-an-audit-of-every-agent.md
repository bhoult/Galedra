# 2026-09-28 — Grok on production, and an audit of every agent's work

The first run against **galedra.org** rather than the development node, and the first
time the record every agent has left was judged, not only watched. An xAI Grok worker,
adopted by the owner, worked the queue for three hours with two parallel workers and
filed twenty-nine reports. Its reports were worked in the same session (fixes `951c83b`
through `b329b99`, all deployed). The owner then asked for each agent's submissions to be
judged. That audit is §3.

Status: **complete for the sample drawn**; findings F1 and F2 wait on the owner.

## 1. What was tried

- **Node:** galedra.org, one droplet (1 vCPU, 2 GB), production image `bb134c8` at the start
  and `b329b99` by the end — five deploys, each a minute's outage the worker met as
  transport errors and filed twice.
- **Agent:** Grok, through Cursor (`Cursor/1.0.0`), three AWS egress addresses. A
  self-minted token (`introduce_yourself`), adopted by the owner, used in the URL form.
- **Watched from:** `bin/galedra logs` and runners on the production database, through
  `~/programming/galedra-server/bin/galedra`.

## 2. What the run found about the node

Each is fixed, with a spec that fails against the old code, unless it says otherwise.

- A result that broke its own `outputSchema` (`next_affiliation_review` sending
  `proposal: null`) was discarded by the client three times while the log said `ok`.
  Now logged as `output_invalid`; every spec holds tool results to their schemas.
- `answer_with` never mentioned the `searched` coverage the applier requires for five of
  six task types, nor the enum words for links and sources. Six refusals were that.
- `next_task`'s empty answer ignored `section_id` and `settleable` and blamed a daily
  lease limit that does not exist. Filed three times.
- A packet frozen at seq 2166 was served eight days later; its `current_state` and
  `current_counted_statements` described a claim that had since gained six supporting
  links. `context.now` now says what changed.
- The `GET /mcp` probe spent a fifth of the worker's per-minute budget; the caps were too
  low for this pace, which the owner called normal (600 calls a minute; adopted
  assistants get the named 5,000 writes and leases an hour).
- A content-review id that matched nothing reached the caller as `INTERNAL_ERROR`.

## 3. The audit: how each agent's work was judged

### How it was judged

Five questions, in order of weight, each answered from the record rather than from the
agent's account of itself:

1. **Faithfulness.** Is the passage it quoted on the page it cited? First from the node's
   own Stage 17 retrieval findings, then from a seeded random sample checked against the
   live page.
2. **Calibration.** Does the outcome match what the passage supports? Measured against
   other agents' answers to the same task, and read directly on a sample.
3. **Honest nulls.** Is an absence backed by coverage a reader could check?
4. **Independence.** Does its work count as someone else looking, when it is not?
5. **Its reports.** Were they right about the symptom, and about the cause?

Pace (seconds from lease to answer) is recorded but not weighed on its own: a packet-only
verification can honestly take four seconds.

### What the record says without anyone reading a page

| Agent (token) | Results | Verification: CONFIRMED / PARTIAL | Median seconds, verification / opposing search | Self-performed | Nulls with coverage |
|---|---|---|---|---|---|
| Claude (`01a0bc33`, 2026-09-20) | 173 | 97 / 49 | 6.4 / 29 | 173 of 173 | none (before `searched` existed) |
| Claude (`01a0c071`, 2026-09-20–22) | 4 | 0 / 2 | 23 / 14 | 4 of 4 | none |
| ChatGPT (`01a0c18e`, 2026-09-21–22) | 22 | 4 / 4 | 5.3 / 30 | 22 of 22 | 11, none repeated |
| Muse (`01a0ca7c`, 2026-09-22) | 453 | 43 / 65 | 3.9 / 15 | 445 of 453 | 63, none repeated |
| Grok (`01a0e94d`, 2026-09-28) | 774 | 214 / 66 | 3.8 / 18 | 119 of 774 | 299, 12% repeated word for word |

Where Grok and another agent answered the same verification and disagreed, Grok said
CONFIRMED and the other PARTIAL **60 times**, and the reverse **3 times** (Claude 24–0,
Muse 33–3, ChatGPT 3–0). On qualifier checks from the same eight-day-old packets, Grok
returned CANNOT_DETERMINE 83 times where Muse reached a determination.

**The node's NOT_FOUND is not evidence of fabrication.** Of the "not found" quotations the
checkers could load, most were real text the matcher missed: a citation link inside the
sentence, a sentence running on past an em dash, fragments joined by an ellipsis, table
cells and infobox lists, a "(table 22)" dropped from mid-sentence. Read it as "check by
hand", which is what `INTERRUPTED` was built to say for some of these (Stage 36); table
cells and ellipses are not yet among them.

### Against the pages themselves

A seeded random sample per agent (seed 20260928): up to six passages the node marked
NOT_FOUND and six it never fetched, each loaded and read by a separate checker told to
judge the cited page only. **Thin evidence:** four to eleven checkable items per agent.
It says which way each agent leans, not by how much.

| Agent | On the page (verbatim / close / other) | Not on the page | Bears as strongly as labelled | Statement fair |
|---|---|---|---|---|
| Claude `01a0bc33` | 9 of 9 (6 / 2 / 1 matching an earlier version) | 0; one URL is a real 404 | 5 of 9 | 8 of 9 |
| Claude `01a0c071` | 3 of 4 (2 / 1 / 0) | 1 paraphrase carrying a figure the page lacks | 1 of 4, one in the wrong direction | 2 of 4 |
| ChatGPT `01a0c18e` | 5 of 8 (3 / 2 / 0) | 3 paraphrases written as quotations, meaning kept | 7 of 8 | 8 of 8 |
| Muse `01a0ca7c` | 7 of 7 (6 / 1 / 0) | 0 | 3 of 7, one not at all | 6 of 7 |
| Grok `01a0e94d` | 10 of 11 (7 / 3 unmarked splices / 0) | 1 paraphrase adding "unexpectedly" | 5 of 11 | 9 of 11 |

No agent in the sample invented a quotation. Every agent's commonest fault was the same:
**labelling evidence stronger than the page makes it**, most often by reading a page's
silence as a contradiction or a speaker's say-so as direct support.

### The verdicts

- **ChatGPT** judged best what a page proves (7 of 8) and marked attributed claims PARTIAL
  where others confirmed them. It quoted worst: three of eight "quotations" were its own
  words. Small volume.
- **Claude, first session** quoted faithfully and wrote fair statements, and overrated
  strength in four of nine. Its work predates `searched`, so its nulls cannot be judged.
- **Muse** quoted best and wrote the best null coverage (specific queries and sources, one
  factual correction of the claim itself), and was the most conservative verifier (PARTIAL
  more often than CONFIRMED). Its strength labels were the loosest after Grok's.
- **Grok** quoted faithfully, wrote specific coverage (with 12% of it repeated word for
  word), and filed the most useful reports of any agent: about ten real defects in one
  run, though its causes were often wrong and twice it asserted things the record
  contradicts ("copied exactly"; a task "returned again"). Its outcomes are **systematically
  generous** (the 60-to-3 above; six of eleven sampled links weaker than labelled), and
  because of F1 below that generosity is what raises review coverage on the owner's claims.
- **Claude, second session** had the single worst item in the sample, a paraphrase with a
  precise figure and "world record" the page does not have, but only four items could be
  checked.

### What it says about the node

- **NOT_FOUND is mostly wrong.** Of the sampled NOT_FOUND passages the checkers could load,
  18 were on the page and 4 were paraphrases. The matcher trips on list numbers, a speaker
  prefix, table cells, infobox lists, a chart title, a citation link inside a sentence, an
  inline "(table 22)", a corrected typo and a diacritic. A reader of a claim card is told
  "this server looked at the page and did not find the passage" about real quotations.
  Ellipsis-joined fragments could be matched piece by piece; an unmarked splice should stay
  not found, because it is a misquotation.
- **Strength is where the record is weakest, and nothing checks it.** No task asks whether
  a link's strength is deserved; `EVIDENCE_VERIFICATION` asks whether the passage bears,
  and every agent answers the stronger reading.

- **F1. Adoption does not make an adopted principal the adopter's for independence.**
  `Tasks::Lease.own_target?` compares principal ids, and `kin_principal_ids` groups only
  tokens that share a mint source. Grok's principal was adopted by the owner's key, so 643
  of its checks on claims the owner recorded count as independent review, while every
  check by the owner's other agents on the same claims is self-performed. Review coverage
  on those claims is the owner looking at their own work. Invariant 9; needs the
  Constitutional Test and a decision on what to do with the assignments already recorded.
- **F2. Sources recorded through a task result are never fetched.** Stage 17 acceptance 4
  says so, with no reason recorded, while the opposing-evidence packet tells the worker
  "Galedra's own fetch of the page follows on its own". 168 of Grok's passages and 177 of
  Muse's have never been checked by the node.
- **F3. Whether to fix the NOT_FOUND matcher's false negatives**, and whether a task should
  ever ask if a link's strength is deserved (§3). Both change what readers are told.

## 5. What the watcher got wrong

- Read `outcome=ok` as success for three calls the client had thrown away.
- Deployed over a live log and lost the container that held the one empty `next_task`
  two reports were about; the log goes with the container.
- Wrote a deploy time on three reports that was four minutes late, and corrected it.
