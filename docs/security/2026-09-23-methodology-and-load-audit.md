# Methodology and load audit

**Date:** 2026-09-23 · **Scope:** does a score mean what it says, can it be gamed, and
what fails first under heavy use · **Head:** `587ffda` (findings), fixes as named below

## How it was done

Two auditors read the code in parallel — one on scoring methodology and accuracy, one on
load and robustness — each required to trace every finding to a file and line, to measure
where it could, and to mark each finding CONFIRMED (traced or reproduced) or PLAUSIBLE. The
lead ran the load tests and spot-checked the findings before any was recorded. Counts are
from the development node (seq 7594, 373 current claims, `ledger-default@0.3.0`); timings
and plans from `galedra_bench` (100,034 claims, 1,019,861 contributions) on a quiet host.
Nothing was written to the development database; the write load test committed a few
hundred entries to the bench corpus, which is a scratch database for exactly this.

**One lead measurement was wrong and is recorded because the mistake is easy to repeat.**
The first write-concurrency test wrapped each attempt in a transaction to roll it back.
The append lock is a transaction-scoped advisory lock, so the test's own wrapper held it
for the whole attempt and serialised every writer — 0.5 investigations a second whatever
the concurrency, latency growing linearly to 15.7 s at eight writers. Committed for real,
the same test scales. **Never measure lock contention inside a rolled-back outer
transaction.**

## Load: what the node carries

| Writers recording 5-claim investigations | Throughput | Median | Worst |
|---|---|---|---|
| 1 | 1.48/s | 0.68 s | 0.68 s |
| 4 | 4.30/s | 0.71 s | 1.03 s |
| 8 | 5.77/s | 0.77 s | 1.98 s |

| Threads reading claim pages, one process | Throughput | p50 | p95 |
|---|---|---|---|
| 1 | 20.6/s | 42 ms | 58 ms |
| 3 | 21.6/s | 137 ms | 182 ms |
| 12 | 18.5/s | 625 ms | 799 ms |

Reads are CPU-bound at about twenty a second **per process**; threads add only waiting. So
read capacity is the number of processes, and **nothing sets `WEB_CONCURRENCY`** — not
Compose, the Dockerfile or `docs/HOSTING.md` — so a deployment serves every reader from one
core. (Development mode; production is faster per request, not differently shaped.)

## Findings

Status is updated in place when a finding changes.

### Blocking

**B1. The production environment did not boot. FIXED.** `config/cache.yml` named a `cache`
database that `database.yml` never defined, so `RAILS_ENV=production` raised
`AdapterNotSpecified` before serving anything. The live node runs in development, which is
why nobody saw it. Fixed by dropping the line: `solid_cache_entries` is in the primary
schema, as the queue already is. Verified: production boots and the Solid Cache store reads
and writes.

### Identity and integrity — each needs the Constitutional Test and an owner decision

**M1. Anyone can register a key at any identity tier, and ESTABLISHED is what makes an
auditor. OPEN — high.** `ledger/appliers/register_key.rb:14-15,30` takes `identity_tier`
from the self-signed payload; `audits/eligibility.rb` lets an ESTABLISHED human audit.
One person can mint as many auditors as they like, and audits change scores: `UNRESOLVED`
drops a link from scoring without a trace (`build_input.rb:100`), `FABRICATION` invalidates,
two `CONFIRMED` clear `provisional`. Self-registered keys are also never counted as kin
(`tasks/lease.rb:113` groups only assistant-token mints), so they can supply a task's
"three independent answers". Spec 02 says the tier never affects scores; through audits it
does. *Fix:* a self-signed registration may only claim PSEUDONYMOUS or ANONYMOUS; a higher
tier comes from a signed attestation; rate-limit registration by address; extend kin to
keys registered together and apply it in acceptance, audit eligibility and consensus.

**M2. Anyone can regroup anyone's evidence, accepted at once. OPEN — high.**
`appliers/assign_independence_group.rb` has no `auto_accept?`, so the default
(`appliers.rb:198-202`) accepts any human's assignment on any item. An explicit group
overrides the origin fallback. Three contradicting items from three origins put into one
group: CONTRADICTED 0.0266 becomes UNRESOLVED 0.5000; splitting one origin into two groups
double-counts it; either way `independence_reviewed` turns true. This bypasses the rule that
refuses a SOURCE_INDEPENDENCE_CHECK on one's own claim. *Fix:* accept only on one's own
evidence item, otherwise a proposal for a non-kin principal; in a new model, let an explicit
group merge items but never split an origin.

**M10. Invariant 9 gaps. OPEN — medium.** An agent auditor is compared by its own id, not its
principal's (`audits/eligibility.rb`); `tasks/checks.rb:53-58` counts self-performed opposing
searches for the high-impact audit band; `Accept` over REST checks the proposer's principal,
not the owner of the rows the proposal touches (MCP's `Corrections.may_accept?` does).

### What a score means — each changes numbers and needs a new model version

**M3. One link produces SUPPORTED, its own labels decide the state, and omitted labels
default to the strongest. OPEN — high.** One DIRECT × DIRECT_TEXT × 0-step link is 0.8581,
SUPPORTED. On the node: **68 of 145 SUPPORTED claims rest on one counted link**; **98 of 145
change state if their strongest link is removed**; **122 of 215 directional states change if
every relevance label drops one notch**. `investigations/record.rb` and `tasks/answer.rb`
default a missing `strength` to DIRECT and a missing `observation_type` to DIRECT_TEXT, and
the log cannot tell a defaulted label from a chosen one. *Fix:* stop defaulting to the
maximum now (an owner call, since it changes what is recorded); in a new model, require two
support groups or one confirmed by a non-kin principal for SUPPORTED, and treat an
unconfirmed DIRECT as STRONG.

**M4. SUPPORTED means "one principal's assistant linked it, unaudited". OPEN — medium-high.**
214 of 215 directional claims rest on one principal's links; 212 are provisional; the node has
14 audits; 143 of 145 SUPPORTED claims have review coverage ≤ 0.25. The headline is "Checks
out so far." *Fix (display, no model change):* say it — "one contributor's reading, not yet
audited" — and extend the caveat to the LEANS states.

**M5. Two passages of one document count as independent. OPEN — medium.** The origin
fallback keys on origin *and* passage (`calculate.rb`). Grouping by origin alone changes 6
states on the node (five SUPPORTED to LEANS_SUPPORTED). The comment's reason — collapsing
would lose a qualifier — does not hold, since QUALIFY has sign 0 and is never collapsed.
http/https are different origins, and `excerpt_hash` is not normalised.

**M6. Excerpts are not verified and a NOT_FOUND retrieval changes nothing. OPEN — medium.**
Only 8 of 875 locations are CHAR_RANGE-checked; retrieval never reaches scoring; 249 of 413
kept links were never retrieved; dropping the 19 NOT_FOUND links changes 8 claims, two of
them SUPPORTED to INSUFFICIENT_EVIDENCE. `MODEL_OUTPUT = 0` is a self-applied label.
*Fix (new model):* let the retrieval finding weigh the extraction factor, allowing for false
negatives (Stage 36 exists because a NOT_FOUND was wrong).

**M7. Review checks certify less than their names.** `primary_source_reviewed` involves no
reviewer and is met by zero-weight links (106 claims show it as their only check);
`CANNOT_DETERMINE` satisfies a check; an EVIDENCE_VERIFICATION `NOT_SUPPORTED` has no effect
(3 claims SUPPORTED despite one). OPEN — medium.

**M8. Challenged and quarantined links vanish from the trace** instead of appearing at weight 0
with a reason, as spec 05 §13 asks. With M1, a sock puppet's audit removes a link invisibly.
OPEN — medium.

**M9. `code_hash` covers seven files**, not the batch builder, origin grouping, task checks,
audit status or the audit policy, all of which decide numbers; Stage 34 changed
`review_coverage` for released models without a version; `Affected.claims_of(EvidenceItem)`
is not windowed by seq. OPEN — medium.

**M11–M16, lower:** "stability" measures the sigmoid's slope more than the evidence (every
single-link claim is MEDIUM); four decimal places on label-driven numbers; an investigation of
all-LEANS claims says "Checks out so far."; the own-source rule is wrong for
ATTRIBUTED_BELIEF claims and depends on placement; `authenticity_factor` is never set;
claim-shopping via near-duplicates; nothing asserts `MODEL_OUTPUT = 0` at release. OPEN.

### Load

**L1. Text length decided the cost of a similarity search, with no token needed. FIXED.**
`Claims::Duplicates` scans every claim computing `similarity()` against the caller's text:
166 ms for 99 characters, 3.1 s for 5,000, 28 s for 10 KB at 100,034 claims (lead-verified).
`search_claims` took any query length and `record_investigation` checked claim length only
after the search. *Fixed:* queries over 300 characters are refused, claim text over 2,000 is
refused before the search, and the search itself never compares more than 2,000.
`spec/requests/mcp_schema_refusals_spec.rb` asserts the search is never reached.

**L2. An old `snapshot_seq` on a public GET rescores the whole corpus and stores it. OPEN —
critical.** A seq below a claim's watermark is always a cache miss; every claim on the bench
corpus misses at seq 500,000. `/api/v1/weaknesses` and snapshot digests accept any seq, and
`call_many` writes every miss — about 370 MB of traces from one anonymous URL. *Fix:* allow
old seqs on whole-graph reads only for pinned snapshots, and never store scores computed on a
GET for a key other than the watermark.

**L3. Revoking a key marks every claim. OPEN — high.** REVOKE_KEY is not in the watermark's
`PRECISE` list, so it marks the whole table; anyone can register a key and revoke it, and the
contributions endpoint rate-limits by a key id taken from the body. Two anonymous posts empty
the score cache node-wide. *Fix:* a revocation without a compromise window marks nothing; with
one, only the claims its signer's entries in that window reach; rate-limit by address.

**L4. The append lock is held for a whole recording. OPEN — high.** `Contribution.transaction
{ append_all }` keeps the transaction-scoped lock until the last append of a bundle: a
40-claim investigation on the development node held it for 17 s. No `lock_timeout` is set,
so other writers wait indefinitely, holding Puma threads that readers need. *Fix:* a
`lock_timeout` with a retryable refusal, per-append work done before the lock, and more
processes (`WEB_CONCURRENCY`).

**L5. Any first MCP call from a new address writes three permanent entries**, and again every
UTC day; rotating IPv6 grows the log without bound. OPEN — medium-high; this is the open
Stage 42 §5a owner question.

**L6. The hourly write cap scanned a signer's whole history per write. FIXED.**
`index_contributions_on_signer_key_id_and_received_at`: 137 ms to 0.7 ms for the busiest
signer on the bench corpus.

**L7. `list_tasks` and `/tasks` load every open task, whole packets included, per call. OPEN
— medium-high.** 1,058 open tasks at 386 claims; extrapolated to ~275,000 rows at 100,000
claims (unmeasured: the bench corpus has no tasks). *Fix:* counts in SQL, and a limit.

**L8. One recompute job per append,** sharing three threads with source retrieval, which
`sleep`s up to 60 s per host; lag reached 64 s. OPEN — medium.

**L9. Whole-corpus pages lose their cache on every write** with no stampede protection
(`race_condition_ttl`). OPEN — medium; `/weaknesses` is the open Stage 26 owner decision.

**L10. No `statement_timeout`, no request body limit,** and two hot counter rows. OPEN — low
to medium.

## Checked and sound

The scorer implements 03 §4 exactly and the reference scorer prints ALL PASS; directional
states need directional evidence; a single WEAK or MODERATE link cannot reach SUPPORTED;
`MODEL_OUTPUT` is 0.0 in all twelve configs; the edition rule is narrow and windowed; the
batch input builder mirrors the single one; self-performed checks stay out of the checklist;
acceptance blocks the same principal; lease kin works for assistant tokens; every list
endpoint and tool clamps its limit; prune jobs are scheduled; the connection pool fits the
thread count; the append path's own lookups are indexed.

## Not checked

Reputation internals and audit sampling; federation and import; inferences; RSS of
`/weaknesses` after today's fixes; Thruster and Cloudflare limits; `get_outline` on very large
outlines; a production-mode load test (acceptance 4 of Stage 26 still needs a droplet).
