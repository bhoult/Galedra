# Stage 43 — An open door and a guarded record

**Status:** planned 2026-09-23, revised the same day after the constitution was revised · not
started · four items wait on the owner (marked **Owner**)

**Tag:** `stage-43-open-door-guarded-record` · **Spec:** 02 §2 (contributors and tiers), 03 §4
(scoring), 04 §3–§6 (agent protocol), 05 §3, §8, §13 (identity, audits, challenged links),
06 §7 (API), 11 §9 (deployment) · **Articles:** VII (model-conditional), IX (independence),
X (reputation is not authority), XI (identity, earned standing), XII (capture, powers held by
roles, defaults and selection), XIV (contributors, not oracles), XVIII (aggregates and
selection), XIX (transparency), XXII (reveal our own weaknesses), XXIV (extraordinary
conclusions) · **Invariants:** 1, 4, 6, 9, 11

Goal: turn every open finding of `docs/security/2026-09-23-methodology-and-load-audit.md` into
a decision. Each one gets a recommendation with pros and cons. Two things have to hold at the
same time:

1. **A new person or assistant gets in with as little commitment as possible.** They should be
   able to read, search and record an investigation without an account, a key or an email
   address. Today they can, and this stage keeps it that way.
2. **Nothing a newcomer can do cheaply can move someone else's score, spend the node's
   capacity, or grow the log without bound.**

These two do not conflict as much as the audit makes it look. **Almost every abuse in it
comes from one of two things.** Either an unproven identity is doing something that
*judges* (auditing, regrouping, accepting, counting as an independent answer), or an
unauthenticated request is doing something whose *cost is unbounded* (an old seq, a
revocation, a mint per address). Contributing is a different kind of act from either. So the
stage draws one line:

> **Anyone may contribute. Only a proven, non-kin identity may judge. Nobody unauthenticated
> may make the node do unbounded work.**

## What the revised constitution changed about this stage

The constitution was revised in place on 2026-09-23 (`CONSTITUTION-AMENDMENTS.md`, 1.0.0
revised before first release). Two consequences:

1. **Several items stop being recommendations and become obligations.** The text now requires
   things the node does not do. Each shortfall is a **Gap** row in
   `13-constitutional-compliance.md`, and Article XXV forbids closing a conflict by amending
   the constitution in the same change that introduces it. So these can only close by
   changing the node, and this stage is where that happens. Items marked **Required** below
   have no "do nothing" option. What remains open is *how*, not *whether*.
2. **The Constitutional Test got stricter.** Questions 2 and 10 now block, and "selection"
   joins the list of sensitive changes. The answers at the end of this file are written
   against that.

| Gap in `13` | Article | Closed by |
|---|---|---|
| Excerpts unverified before they count | II | M6 |
| Challenged links missing from the trace; `code_hash` coverage | VII | M8, M9 |
| Two passages counted as two witnesses; anyone can regroup | IX | M5, M2 |
| A moderator skips audit eligibility | X, XII | M1 (moderators) |
| Tier reaches scores through audits; auditing cannot be earned | XI | M1, M1 (earned route) |
| Moderators appointed outside the log | XII | G1 |
| Default model set in configuration | XII | G2 |
| Ranking, task priority and verdict wording are code, not published rules | XII | G3 |
| An investigation headline reads as a verdict | XVIII | G4 (was M13) |
| Why a claim is proposed for checking is not shown | XVIII | G5 |
| An agent auditor compared by its own id only | XIV | M10 |
| One link reaches SUPPORTED | XXIV | M3 |

## The tiers this stage uses

Four standings, from what the node can actually tell apart today (`Contributor::IDENTITY_TIERS`,
`AssistantToken#anonymous?`, `address_keyed?`, `kin_key`, `Governance::Moderators`):

| Standing | How you get it | What it costs the newcomer |
|---|---|---|
| **Visitor** | No credential at all | Nothing |
| **Anonymous contributor** | The first *write* from a visitor mints an ANONYMOUS key | Nothing; an adoption link is returned |
| **Named** | Sign up (email and password), or connect an assistant token or OAuth from an account: PSEUDONYMOUS | One sign-up |
| **Established** | An attestation, or an earned AUDIT record in a domain, never a claim about oneself; see M1 | Being vouched for, or five audits someone else confirmed |

The rules for each:

| Act | Visitor | Anonymous | Named | Established / moderator |
|---|---|---|---|---|
| Read any page, tool or API at the **head** | yes | yes | yes | yes |
| Read at an **old seq** on whole-graph reads (L2) | pinned seqs only | pinned only | pinned only | pinned only; a moderator may pin |
| Read one claim at an old seq | yes | yes | yes | yes |
| `search_claims`, `record_investigation`, `add_evidence` | yes; mints a key on first write | yes | yes | yes |
| File a report or feature request | yes (the existing anonymous cap) | yes | yes (higher cap) | yes |
| Work tasks (`next_task`) | no | no (already so) | yes | yes |
| Content and affiliation review | no | no (already so) | yes | yes |
| Regroup evidence that is not your own (M2) | no | no | propose only | propose; accepted by a non-kin principal |
| Accept a proposal on others' rows (M10) | no | no | owner of the rows only | owner, or moderator |
| Audit (M1) | no | advisory only, with a resume token (L5) | advisory, until an earned record in that domain | yes, if attested or earned; a moderator role alone is not enough |
| Count toward a task's independent answers | no | no | yes, one per kin group | yes |
| Register a raw key over REST | rate-limited by address | — | yes | yes |
| Revoke a key with a compromise window (L3) | no | no | own key | own key |

Rate limits by standing (L5, L10), keyed on the **address, with IPv6 collapsed to its /64**,
since rotating within a /64 is free and rotating /64s is not:

| | Visitor / anonymous | Named |
|---|---|---|
| MCP calls | 60 a minute per /64 | 120 a minute per token (today's) |
| Writes (`record_investigation`, `add_evidence`) | 10 an hour per /64, 30 a day | the delegation's `max_tasks_per_hour` |
| Keys minted | 1 a day per /64; 5 a day per /48 | — |
| Request body | 256 KB | 1 MB |

These numbers are starting points, to be checked against `request_tallies` after a week.
On the development node (2026-09-23), the busiest single anonymous contributor wrote 16
contributions in its busiest hour, and every anonymous contributor together wrote 21. An
investigation is several contributions, so a cap of ten write *calls* an hour binds nobody
there today. On the same node, anonymous keys have written **107 mint entries
(`REGISTER_KEY`, `DELEGATE`) against 68 epistemic ones**. That is L5 in two numbers.

---

## Identity and integrity

### M1. A self-signed registration can claim ESTABLISHED, and ESTABLISHED makes an auditor

**Recommendation:** a `REGISTER_KEY` payload may claim only `ANONYMOUS` or `PSEUDONYMOUS`.
Anything higher comes from a separate `ATTEST_TIER` contribution, signed by a moderator or the
system key and naming the key and the tier. The applier refuses any other self-claimed tier,
and replay treats existing rows that claimed higher as `PSEUDONYMOUS` from the migration seq
onwards. **The development node has exactly one:** the human "Reviewer" registered at seq 4
as ESTABLISHED, and it signed every one of the node's 14 audits. It needs an `ATTEST_TIER` in
the same release, or the node loses its only auditor. Separately, keys registered over REST from
one /64 within a day share a `kin_key`, the same as assistant tokens minted from one address.

- **Pros:** closes the only path from "nobody" to "auditor" that costs nothing. Makes 02's
  claim that tier never affects a score true again, since tier would reach scores only
  through audits, and audits only through attestation. Costs a newcomer nothing: nobody
  needs ESTABLISHED to contribute.
- **Cons:** the node has no working auditor pool until a moderator attests someone. The
  audit queue already moves slowly. Attestation is a new governance act, and who may attest
  is bound up with **who holds the system key and appoints moderators, which is an owner
  decision**. Kin by /64 over-groups people behind one carrier-grade NAT. That only matters
  for counting independent answers, and those people can sign up.
- **Alternative rejected:** keep self-claimed tiers but ignore them in `Audits::Eligibility`.
  Simpler, but the column would then lie on every page that shows it.

**Required: the earned route (Article XI, revised 2026-09-23).** "No
standing shall be reachable only by attestation." Today AUDIT reputation comes only from
one's own audits being audited, and auditing needs the tier or that reputation, so without
attestation nobody can ever start. The route:

- An **ineligible** principal may still file an audit. It is recorded as **advisory**, with
  `advisory: true` on the audit row. It has no effect on the target's status, its
  `provisional` flag or scoring, and it enters the audit-sampling pool at a fixed rate.
- When an eligible auditor re-audits an advisory audit, the result becomes a reputation
  event of type AUDIT for the advisory auditor, in the domain concerned, exactly as for any
  other audit.
- A principal whose AUDIT record reaches `auditor_min_n` and `auditor_min_mean` becomes
  eligible **in that domain**, without anyone vouching.
- Kin apply throughout: an advisory audit re-audited by the auditor's own kin earns nothing.
- An anonymous contributor can take this route only while holding a resume token (L5).
  Without one there is no durable identity for a record to accrue to, and an address-and-day
  key would reset every day.

- **Pros:** makes Article XI true. Attestation becomes a shortcut, not the only door. The
  standing is per domain, as Article X asks.
- **Cons:** advisory audits cost eligible auditors time to re-audit, and the pool is small.
  A patient sock-puppet farm could earn standing. It would need five audits per domain that
  a non-kin eligible auditor confirmed, which is real work checked by someone else. That is
  the cost Article XI accepts.

**Required: moderators (Articles X and XII, "a role shall not confer epistemic authority").**
Today a moderator skips every eligibility check. Recommendation: a moderator's audit is eligible only by the
same routes as anyone's, meaning attestation or an earned record. Moderation keeps its own
powers (quarantine, takedown, attestation, pins). *Con:* the bootstrap auditor today is a
moderator-or-ESTABLISHED key. It has to be attested explicitly in the same release.
- **Owner:** who may attest. The conservative reading, and the default if nobody decides, is
  moderators only.

### M2. Anyone can regroup anyone's evidence, and the change is accepted at once

**Recommendation:** `ASSIGN_INDEPENDENCE_GROUP` is accepted at once only when the signer's
principal owns **every** evidence item in the assignment. Otherwise it is a proposal, which
a non-kin named principal accepts through the existing `accept_proposal` path. Anonymous
callers may not propose it. In the next model version (see M3 to M9 below), an explicit group
may *merge* items across origins but never *split* one origin into two groups.

- **Pros:** closes the CONTRADICTED 0.0266 → UNRESOLVED 0.5000 attack. It reuses machinery
  that exists (proposals, `Corrections.may_accept?`), and it matches the rule that already
  refuses a SOURCE_INDEPENDENCE_CHECK on one's own claim. Grouping one's own evidence stays
  instant.
- **Cons:** honest regrouping of another person's evidence, which is a legitimate
  correction, now waits for someone else to accept it. The proposal queue is thin today.
  The model change is Invariant 4 work and waits for the next version.
- **Owner:** none for the acceptance rule. The model half rides on the next model version.

### M10. Three gaps in Invariant 9

**Recommendation:** fix all three now. None is a decision:

1. `Audits::Eligibility` compares an agent auditor's **principal** as well as its own id.
   Today `auditor_principal` is nil for an agent, so the check compares only the agent's own
   id. A second agent under the same principal passes it and can audit its sibling's work.
2. `Tasks::Checks` leaves self-performed opposing searches out of the high-impact audit band,
   the same way Stage 34 left them out of the checklist.
3. `Accept` over REST uses `Corrections.may_accept?`, which checks the owner of the rows the
   proposal touches, as MCP already does.

- **Pros:** each is a bug against a written invariant. Specs are straightforward: one refusal
  each, and each fails against the current code.
- **Cons:** (2) can change a claim's audit band, which feeds sampling. It does not change
  scores, but it does change which claims get audited. It needs a line in the release notes.

---

## Governance the revised constitution requires

Article XII now says every power a role holds is exercised through signed, visible,
challengeable contributions. The default model, search ranking, task priority, what is proposed
for examination, and the wording of summary verdicts must be governed by published rules,
with every change recorded. Article XVIII says a summary over many claims is not a verdict on
a speaker, and that selection is shown. None of this is true today. All five items are
**Required**.

### G1. Moderators are appointed outside the log

`Governance::Moderators` reads a list of key ids in `LEDGER_MODERATOR_KEY_IDS` and a `moderator`
flag on `users` that `/admin/users` sets. Neither is a contribution. `/api/v1/meta` publishes
the current list, but there is no history of who was appointed when, or by whom.

**Recommendation:** add `APPOINT_MODERATOR` and `REMOVE_MODERATOR` control contributions, signed by
the system key and naming the key. `Governance::Moderators` reads the projection. The admin
buttons sign one of these through the system key instead of flipping the flag. The environment
list survives only as bootstrap on an empty log: `ledger:genesis` turns it into appointments,
and it is ignored once any appointment exists.

- **Pros:** appointments and removals become history anyone can reconstruct (Articles XII and
  XIII), and a moderator's past acts can be checked against their appointment window.
- **Cons:** a new pair of action types. The admin page now writes to the log, which it never
  did. Who holds the system key stays the owner's reserved decision, and this makes that
  decision matter more.

### G2. The default model is set in configuration, and has two answers

`Scoring::Registry.default_model` honours `LEDGER_DEFAULT_MODEL`, which is how 0.3.0 became the
default. `default_model_at(seq)`, which `Tasks::Create#priority_for` uses, **ignores that pin**
and takes the latest `ledger-default` released. The two agree today only because 0.3.0 is
also the latest release. Releasing 0.4.0 "but not the default", as this stage plans, would
quietly re-prioritise the task queue under 0.4.0 while every page showed 0.3.0.

**Recommendation:** add `SET_DEFAULT_MODEL`, signed by the system key and naming a released
model. Both methods read the latest one at or before the seq, so the display and task
priority cannot diverge. Releasing a model never changes the default by itself. The environment
pin is removed. `/api/v1/meta` shows the seq at which the default was set.

- **Pros:** fixes a latent inconsistency before 0.4.0 makes it real. Choosing the default is
  arguably the most consequential choice an operator makes (Article XIX), and it becomes a
  dated, signed act.
- **Cons:** one more action type. Replay changes the task priorities computed before the first
  `SET_DEFAULT_MODEL` unless genesis records one for the existing default at seq 0's
  successor. The migration has to record `SET_DEFAULT_MODEL ledger-default@0.3.0` and check
  that priorities replay unchanged.
- **Must land before 0.4.0 is released.**

### G3. Ranking, priority and wording are code, not published rules

**Recommendation:** gather the rules that decide what is seen first into one declared place,
`Governance::Rules`. That covers:

- how `Claims::Search` orders results;
- `Tasks::Create#priority_for`, with its weights;
- which claims the weaknesses page lists, and in what order;
- the templates for summary verdicts.

Serve them readably at `/help/rules` and as JSON at `/api/v1/rules`, and record each version
as a `RELEASE_RULES` contribution, signed by the system key and carrying the rules document
and its hash. That is the same pattern as `RELEASE_SCORING_MODEL` and `AMEND_CONSTITUTION`,
and `/api/v1/meta` would report whether the rules served are the ones recorded. A spec fails
if the running constants hash differently from the document served.

- **Pros:** "published rules" becomes something a reader can read and a node can be checked
  against, using a pattern the node already has twice.
- **Cons:** the rules are code, and pulling them into one declared module is real
  refactoring across search, tasks and weaknesses. Every change to ranking now needs a
  release entry. That friction is the point, but it will be felt.
- **Alternative rejected:** publishing the rules only in git. Git is not the ledger, and
  Article XII asks for changes to be recorded and visible to the people the ranking affects.

### G4. An investigation headline reads as a verdict (was M13)

Investigations of one person's statement end in one line, "Checks out so far.", even when
every claim in it only LEANS.

**Recommendation:** the headline says what it aggregates and never judges the whole, for
example "7 claims checked: 3 lean supported, 1 contradicted, 3 without enough evidence". No
single-word verdict is given on a set that contains a speaker. The wording is one of the G3
templates.

- **Pros:** meets XVIII's new sentence directly. It is more informative too.
- **Cons:** less shareable than a verdict, and people want verdicts. That is the trade the
  Article makes on purpose.

### G5. Why a claim was proposed for checking is not shown

**Recommendation:** every task, in `list_tasks`, `next_task` and `/tasks`, and every row on
the weaknesses page carries `proposed_because`: the priority terms that ranked it, from G3's
rules. For example: "high impact: 4 claims depend on it; coverage 0.00; created 2 days ago".
An investigation page says who chose its claims, which is the investigator.

- **Pros:** selection becomes as inspectable as scoring (XVIII). A reader can ask whether the
  queue leans one way.
- **Cons:** a few more fields on every task. The terms have to be computed once, when the
  task is created, and stored with it, or the reason shown could drift from the reason used.

---

## What a score means

Every item in this section changes numbers. Under Invariant 4 they ship together as **one
new model version**, `ledger-default@0.4.0` and `ledger-strict@0.4.0`, with regenerated
goldens and the reference scorer brought along. They should not dribble out as four
versions. M4 is display-only and can ship first.

### M3. One link makes SUPPORTED, and omitted labels default to the strongest

Two halves, which ship separately.

**(a) Now, no model change: stop defaulting to the maximum.** A `record_investigation` or
`submit_task` link that omits `strength` or `observation_type` is refused, and the refusal
names the enum and says what each value means (Stage 42 showed a refusal is the channel that
works). Also record `labels_defaulted: true` for the existing rows that were defaulted.
That needs `Ledger::Apply` to be able to derive it, so it is a projection column computed
from the payload, never an edit.

- **Pros:** the log stops recording a choice nobody made. Each label now costs the caller one
  decision, which is the least the scoring model assumes they made.
- **Cons:** it is the first refusal a newcomer's assistant will meet. Some assistants will
  retry badly. It changes what is recorded, so **Owner** it is. The softer alternative is to
  default to the *weakest* label (`WEAK` and `INDIRECT`) instead of refusing. That is
  friendlier to a newcomer and still honest, and **it is what I recommend if the owner
  prefers no new refusal**.

**(b) In 0.4.0: SUPPORTED and CONTRADICTED need corroboration.** A decisive state needs two
support groups, or one link confirmed by a non-kin principal's audit or evidence
verification. Without that the claim is capped at LEANS. An unconfirmed `DIRECT` counts as
`STRONG`.

- **Pros:** "SUPPORTED" stops meaning "one assistant said so". On the node, 68 of 145
  SUPPORTED claims rest on one link. Most will read LEANS_SUPPORTED, which is what they are.
- **Cons:** most of the node's decisive states drop a notch overnight. That is visible,
  and it needs saying on `/about` and in the changelog. It makes the audit queue matter,
  and M1 is shrinking the auditor pool in the same stage. The two together mean fewer
  decisive states for a while. That is the honest outcome, and people may still dislike
  it.

### M4. SUPPORTED means "one principal's assistant linked it, unaudited"

**Recommendation, display only, now:** when every counted link comes from one principal and
nothing has been audited, the answer card says "one contributor's reading, not yet checked by
anyone else". The same caveat goes on LEANS states. The headline "Checks out so far." is kept
for claims whose review coverage is above 0.25.

- **Pros:** no model change and no number change. It tells a reader exactly what is there
  (Article XIX), and it is cheap.
- **Cons:** nearly every claim on the node gets the caveat today, which may read as the node
  running itself down. That is accurate, but it is not flattering.

### M5. Two passages of one document count as independent

**Recommendation (0.4.0):** the origin fallback groups by origin alone. Origins are also
normalised before grouping: scheme-insensitive, `www.` stripped, and `excerpt_hash` over
NFC-normalised, whitespace-collapsed text.

- **Pros:** one document is one witness, which is what a reader assumes. Six state changes on
  the node. QUALIFY is unaffected, since it has sign 0.
- **Cons:** a long report that genuinely contains two independent findings, such as a review
  article quoting two studies, now counts once unless someone regroups it explicitly. After
  M2, that regroup is a proposal. Normalising `excerpt_hash` changes hashes on new rows only,
  so old and new rows hash differently. That needs a note, but nothing breaks.

### M6. Excerpts are not verified, and a NOT_FOUND retrieval changes nothing

**Recommendation (0.4.0):** a retrieval finding weighs the extraction factor. `FOUND` or
`INTERRUPTED` counts in full. `NOT_READ` (not retrieved) takes a modest discount, which
starts at 0.85. `NOT_FOUND` takes a steep discount, 0.25, and **never zero**, because Stage
36 exists because a NOT_FOUND was wrong. The trace shows the finding and the factor.

- **Pros:** a quotation nobody could find stops carrying full weight, which is the single
  most-gameable input left. The two SUPPORTED claims resting on unfound quotes drop.
- **Cons:** scores start to depend on a job that runs on the network (Stage 17), so they
  become sensitive to a site's uptime at retrieval time. The finding is a contribution at a
  seq, so this is still deterministic. But a site down on one day leaves a discount on the
  record until someone retrieves again. The re-retrieval path needs to be obvious. It also
  makes retrieval capacity (L8) matter more.

### M7. Review checks certify less than their names say

**Recommendation (0.4.0):**
- `primary_source_reviewed` requires a link with weight above 0 whose source is PRIMARY, and
  a reviewer other than the linker.
- `CANNOT_DETERMINE` records the attempt but does not satisfy a check.
- An EVIDENCE_VERIFICATION `NOT_SUPPORTED` sets that link's weight to 0, with the reason shown
  in the trace.

- **Pros:** each check then means what its name says. An explicit negative verification
  finally does something.
- **Cons:** review coverage drops across the node. 106 claims lose their only check. A
  `NOT_SUPPORTED` from one verifier now removes a link, so the verifier's own standing
  matters: this depends on M1 and M10 being in first.

### M8. Challenged and quarantined links vanish from the trace

**Recommendation (0.4.0):** they appear in the trace at weight 0, with the audit or quarantine
id as the reason, as spec 05 §13 already says. Their contribution to the probability is
unchanged.

- **Pros:** anyone can see why a link stopped counting, and a bad audit becomes visible and
  challengeable. This is the counterweight to M1 whatever else is decided.
- **Cons:** traces grow. Every trace hash changes, so the goldens change, which 0.4.0 needs
  anyway. A quarantined source's excerpt must still stay out of the trace text; only the ids
  appear.

### M9. `code_hash` covers seven files

**Recommendation, now:** `code_hash` is computed over a declared list,
`Scoring::Model::CODE_FILES`. A spec walks every constant the scorer's input and calculation
reach (the graphify call graph gives the list) and fails if a reachable file is not in it.
Stage 34's unversioned change to `review_coverage` is recorded in the Decision Log as a
violation, with the claims it moved. `Affected.claims_of(EvidenceItem)` is windowed by seq.

- **Pros:** the next unversioned change fails in CI instead of in a replay. No numbers change.
- **Cons:** adding the missing files changes the hash of the *released* models 0.1 to 0.3.
  So the fix is to freeze their recorded hash and compute the full list from 0.4.0 on.
  That is honest but awkward to explain.

### M11 to M16, lower

| | Recommendation | Pros | Cons |
|---|---|---|---|
| M11 stability measures the slope | Compute it from the evidence margin instead of the sigmoid (0.4.0) | Single-link claims stop all reading MEDIUM | One more number whose definition changes |
| M12 four decimals | Show two by default and four on request; the trace keeps four | Stops false precision (Invariant 16) | Two views of one number |
| M13 an all-LEANS investigation "checks out" | Moved to G4, which is now required by Article XVIII | | |
| M14 own-source rule for ATTRIBUTED_BELIEF | Exempt ATTRIBUTED_BELIEF: its source *is* the evidence (0.4.0) | Right for the claim type | Placement stops mattering for those claims, which needs a spec |
| M15 `authenticity_factor` never set | Remove it from the config in 0.4.0, or wire it to the retrieval finding (see M6) | Removes a dead knob | None |
| M16 no release check on `MODEL_OUTPUT = 0` | `ledger:release_models` refuses a config with `MODEL_OUTPUT` ≠ 0 | Guards Invariant 7 | None |

Near-duplicate claim-shopping (M16's second half) waits on M3(b). Once a lone link cannot
make SUPPORTED, a near-duplicate that picked up one is worth little.

---

## Load

### L2. An old `snapshot_seq` on a public GET rescores the whole corpus, and stores the result. Critical

**Recommendation, now:**
1. Whole-graph reads (`/weaknesses`, snapshot digests, `/api/v1/weaknesses`, the claims API
   with `snapshot_seq`) accept an old seq only if it is a **pinned snapshot**. Otherwise they
   refuse with the list of pinned seqs. Pinning is a moderator act.
2. A score computed for a key other than the claim's watermark is **never stored**. It is
   served and dropped.
3. A single claim at any seq stays open to everyone. That costs one claim's work.

- **Pros:** one URL can no longer spend 370 MB and a core-minute. Reproducibility is
  unchanged for anyone who needs it, because pinned seqs are exactly what a citation should
  name. Readers of one claim lose nothing.
- **Cons:** a researcher who wants the whole graph at an arbitrary past seq has to ask a
  moderator to pin it, or replay locally (`ledger:replay`), which the export in Stage 28
  makes easier. This also settles half of the Stage 26 `/weaknesses` question. The other
  half is which seqs get pinned, and how often.
- **Owner:** whether a pin is automatic (for example daily) or manual. I recommend
  automatic daily pins plus manual ones.

### L3. Revoking a key marks every claim

**Recommendation, now:** a `REVOKE_KEY` with no compromise window marks nothing, because it
changes no past entry. A revocation *with* a window marks only the claims its signer's entries
in that window reach, found through `projection_rows_everywhere`. The contributions endpoint
rate-limits by **address** (/64), not by the `signer_key_id` in the body, which costs
nothing to vary.

- **Pros:** two anonymous posts can no longer empty the score cache node-wide. It is precise
  and cheap.
- **Cons:** a revocation with a window over a very active key still marks a lot. That is
  correct and rare. Address-keyed limits over-limit a shared NAT, which the named-token path
  avoids.

### L4. The append lock is held for a whole recording

**Recommendation, now:**
1. Set a `lock_timeout` of 5 s on the advisory lock. On timeout, refuse with
   `BUSY, retry_after` and the same idempotency key, so a retry is free.
2. Move validation, duplicate search and canonicalisation of every item in a bundle **before**
   the lock is taken, so the lock covers only the appends.
3. Set `WEB_CONCURRENCY` in Compose and `docs/HOSTING.md` (the audit's load section).

- **Pros:** a 40-claim recording stops freezing every other writer and the readers queued
  behind them. The retry path already exists (idempotent tools).
- **Cons:** (2) means a bundle validated before the lock can be invalidated by a write that
  lands while it waits, so the checks that depend on state must run again inside the lock.
  That part must stay. A refusal under load is a new failure a caller can see.

### L5. A first MCP call from a new address writes three permanent entries, every day

This is the Stage 42 §5a owner question. **Recommendation:** mint lazily. A visitor reads with
no key at all. The first **write** mints the ANONYMOUS principal, the agent key and the
delegation, which is the same three entries, but only for callers that contribute. The
write's result carries an adoption link and a **resume token**: an opaque, signed value the
caller can present on later calls to be the same anonymous contributor across addresses and
days. Callers that present nothing keep today's address-and-day key. Mints are capped per /64
and /48 as in the table above.

- **Pros:** reading costs the log nothing, which covers most traffic. A contributor gets
  continuity without an account, and continuity is what made the old anonymous filer unable
  to read its own answers. The door stays as open as it is today.
- **Cons:** the resume token is a bearer secret, and anonymous callers will leak it. It must
  grant nothing an anonymous key cannot already do, and it must be revocable. A caller
  rotating addresses without presenting it still mints per /64 per day, within the caps.
- **Owner:** yes, as Stage 42 §5a. The alternative is refusing anonymous writes outright.
  That is simpler and safer, but it breaks the first-use path this project is built around,
  and I do not recommend it.

### L7. `list_tasks` and `/tasks` load every open task, whole packets included

**Recommendation, now:** counts come from SQL `GROUP BY`. Lists are limited (50) and paged, and
select narrow columns without the packet. A spec counts statements and asserts a row budget.

- **Pros:** constant cost, whatever the size of the queue.
- **Cons:** none worth naming. Callers that relied on getting everything get a page, and a
  `next` cursor.

### L8. One recompute job per append, sharing threads with retrieval

**Recommendation, now:** coalesce recompute jobs by claim, one job per claim per head seq, keyed
`(claim, seq)` as `CLAUDE.md` already requires. Put source retrieval on its own queue with its
own thread count, so a slow host cannot starve rescoring.

- **Pros:** recompute lag stops tracking retrieval's `sleep`.
- **Cons:** one more queue to watch. A coalesced job can serve a score one append stale,
  which the watermark already tolerates.

### L9. Whole-corpus pages lose their cache on every write

**Recommendation:** after L2, `/weaknesses` and the snapshot pages read the latest **pinned**
snapshot by default, with "as of seq N, pinned HH:MM" shown. The live head is available on
request, cached with `race_condition_ttl` so one request rebuilds while the others get the
stale copy.

- **Pros:** a write no longer triggers a 2 s rebuild for every reader. It settles the Stage 26
  owner decision along with L2.
- **Cons:** the default view is up to a day old. It says so, but some readers will not read
  the line.
- **Owner:** same decision as L2.

### L10. No `statement_timeout`, no request body limit, and two hot counter rows

**Recommendation, now:** set `statement_timeout` to 10 s for web connections and leave it off
for jobs and rake. Put body limits in Rack by standing (see the table). The counter rows
(request tallies, reference counts) move to per-process accumulation, flushed once a minute.

- **Pros:** no single request can hold a connection for minutes. The limits are cheap and
  conventional.
- **Cons:** a legitimate slow path, such as `record_investigation` at 40 claims on a large
  corpus, may meet the timeout. L4(2) and the duplicate-search work have to land first, or
  the timeout has to be generous for writes. Batched counters lose up to a minute of counts
  when a process crashes.

---

## Order of work

1. **Required by the constitution, no decision needed:**
   - M10 (the three Invariant 9 gaps);
   - M1's earned route and moderator change;
   - G1 (moderators appointed in the log);
   - G2 (the default model), which must land before 0.4.0;
   - G3 (published rules), then G4 and G5, which depend on it;
   - M9 (the `code_hash` guard).
2. **Now, no decision needed:**
   - L3, L7, L8 and L10;
   - M4;
   - L4 (1) and (2);
   - the part of L2 that does not depend on pins: never store scores for a non-watermark key.
3. **Owner decisions:**
   - M1: who attests;
   - M3(a): refuse, or default to the weakest label;
   - L5: lazy minting and the resume token;
   - L2 and L9: the pin policy.
4. **Model 0.4.0:** M2 (no split), M3(b), M5, M6, M7, M8, M11, M14 and M15.
   - Goldens are regenerated, and the reference scorer is extended until it prints `ALL PASS`.
   - 0.4.0 is released but not made the default until the owner says so, through G2's
     `SET_DEFAULT_MODEL`.
   - M3(b), M5 and M8 are also **Required**, since they close the IX, VII and XXIV gaps.
     Only the version they ship in is a choice.

## Constitutional Test

The ten questions from the end of `12-constitution.md`:

1. *Does it make evidence more traceable or less?* **More.** M8 puts challenged and
   quarantined links in the trace with the reason. M6 ties a quotation's weight to a signed
   retrieval finding. M9 makes the code behind a number declared and checked.
2. *Does it make disagreement more inspectable or less?* **More.** A regroup of someone
   else's evidence becomes a visible proposal (M2) instead of a silent overwrite. A
   negative verification shows up in the trace (M7). Why a claim was proposed for checking
   is shown (G5), so a disagreement about *what gets examined* can be inspected as well as
   one about what was found.
3. *Does it increase hidden authority?* **No. It adds authority in plain view and removes
   authority that was hidden.**
   - **Added:** attestation (M1) and pinning (L2) are new moderator powers. Both are signed
     contributions in the log, listed on the moderation page and open to challenge.
   - **Removed, from hidden places:**
     - a self-claimed tier that conferred audit rights;
     - a moderator's exemption from audit eligibility (M1);
     - moderator appointment through an environment variable and a database flag (G1);
     - a default model set by an environment variable (G2);
     - ranking and priority rules that lived only in code (G3).
   - Who may attest is reserved to the owner.
4. *Does it allow reputation to substitute for evidence?* **No, and it closes a path that
   did.** Today a tier, which is a kind of reputation, reaches scores through audits without
   anyone checking it. After this stage an audit still has to cite what it found, and the
   right to audit is granted visibly. Tier never enters `Scoring::Calculate`.
5. *Does it preserve uncertainty?* **Yes, more of it.** M3(b) caps uncorroborated claims at
   LEANS rather than decisive. M6 discounts a quotation nobody found but never zeroes it,
   because retrieval is fallible. M11 and M12 stop presenting label-driven numbers with
   false precision.
6. *Can the result be reproduced?* **Yes.** Every number change is in 0.4.0, with goldens and
   the reference scorer. L2 makes past whole-graph reads come from pinned snapshots, which
   are exactly reproducible, instead of from an ad-hoc rescoring at any seq. M9 guards the
   next unversioned change.
7. *Can an opposing investigator challenge it using the same system?* **Yes.** Attestations,
   audits, pins and regroup proposals are contributions, and each can be audited or
   threaded (Stage 37). An anonymous investigator can still record contrary evidence with no
   account. What they cannot do without standing is *judge* someone else's work, which is
   the act a sock puppet uses.
8. *Can the history of the conclusion be reconstructed?* **Yes, and more of it than
   before.**
   - Nothing is edited. Old self-claimed tiers are reinterpreted from a migration seq
     onward, and the old rows remain as they were.
   - Appointments (G1), the default model (G2) and the rules (G3) gain a history they
     never had.
   - Replay must reproduce task priorities from before the first `SET_DEFAULT_MODEL`
     (G2's migration), and G2 has a check for that.
9. *Does it preserve the distinction between shared evidence and personal belief?* **Yes.**
   Nothing here touches personal assessments. The resume token (L5) is an access
   credential, not a view.
10. *Would we still want this mechanism if it were used by people whose conclusions we
    strongly disagree with?* **Yes, and this is the question the stage is built around.** An
    open door with no guard would let an organised group we disagree with mint auditors,
    regroup our evidence into one witness, and empty the cache, all anonymously. The guard
    without the door would let whoever holds standing shut others out. The rule proposed
    holds for both sides: anyone may contribute, and judging needs standing that is granted
    in public and can be challenged. The one place it could be turned against dissenters
    is attestation, if moderators attest selectively. That risk has four answers:
    - attestation is logged;
    - the moderation page lists it;
    - the earned route means no one depends on it (Article XI);
    - who may attest is the owner's decision, not this stage's.

    The same test applied to G1–G3: an operator we distrusted would find every appointment,
    default and ranking rule dated and signed. That is what we would want to be able to see.

No "no" to 1, 2, 5, 6, 7, 8, 9 or 10, and no "yes" to 3 or 4. That is the blocking list as
revised on 2026-09-23.

## Acceptance

- **M1:** a self-signed `REGISTER_KEY` claiming ESTABLISHED is refused. An attested key
  audits. An unattested, unearned one files an *advisory* audit that changes no status or
  score, and the result says so and says how standing is earned. After five advisory audits
  are confirmed by a non-kin eligible auditor in one domain, the next audit in that domain
  counts. One confirmed by kin earns nothing. A moderator with neither attestation nor a
  record files an advisory audit like anyone else.
- **G1:** appointing and removing a moderator are signed contributions.
  `Governance::Moderators` answers from them at any seq, and the environment list is ignored
  once an appointment exists.
- **G2:** after 0.4.0 is released without `SET_DEFAULT_MODEL`, the pages, `/api/v1/meta` and
  task priority all still use 0.3.0 (a spec that fails against today's `default_model_at`).
  Replay reproduces every task priority on the development node.
- **G3:** `/api/v1/rules` serves the rules. `/api/v1/meta` reports whether they are the ones
  recorded, and a spec fails when a ranking or priority constant changes without the rules
  document changing.
- **G4 and G5:** no investigation headline is a single verdict. Every task and every
  weaknesses row carries `proposed_because`, stored when the task is created.
- **M2:** the three-origin regrouping attack from the audit leaves the claim CONTRADICTED
  (spec replays it). Regrouping one's own evidence is still accepted at once.
- **M10:** three specs, each failing against the current code.
- **L2:** `GET /api/v1/weaknesses?snapshot_seq=<unpinned>` refuses in under 50 ms on the
  bench corpus. `claim_scores` gains no rows from any GET at a non-watermark key (a
  statement-count and row-count spec).
- **L3:** an unwindowed `REVOKE_KEY` marks zero claims.
- **L4:** with a 40-claim recording in flight, a second writer gets `BUSY` within 6 s, and
  a claim page p95 stays under 200 ms (bench, committed writes, never a rolled-back outer
  transaction).
- **L5:** a visitor's reads write nothing to `contributions`. The first write mints once, and
  a presented resume token from a new address writes nothing new.
- **L7:** `list_tasks` issues a constant number of statements at 10 and at 10,000 open tasks.
- **0.4.0:** goldens for both models, the reference scorer `ALL PASS`, and a Decision Log
  table of how many node claims change state and in which direction.
- The audit file's statuses are updated in place for every item this stage closes, and every
  Gap row in `13-constitutional-compliance.md` that it closes is changed to what the node
  now does.
