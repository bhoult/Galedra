# Stage 18 — Work open tasks from a connector

**Status:** implemented · tag `stage-18-work-tasks` · decisions recorded 2026-09-18

## Plan

**Tag:** `stage-18-work-tasks` · **Spec:** 04 §2 (task types), 04 §3 (packets, blind
slots), 04 §6 (result validation), 04 §7 (leasing), 02 §1.1a (automated acceptance),
05 §8 (auditor selection), Article II, Article XI

Goal: a person tells the assistant they already use "work five open tasks in Galedra",
and it does: leases the highest-priority task it may hold, does the reading itself,
answers in the same vocabulary it records investigations in, and moves on. This is the
third use on the connect page made true. Task work is what the agent protocol was built
for; Stage 18 only carries it over the connector, in the shape an assistant can use
without learning refs, packet hashes, or signing.

Not in this stage: audits. Spec 05 §8 admits as auditor a human at `ESTABLISHED` or
above, or a contributor with `n ≥ 5` and `mean ≥ 0.8` in `AUDIT` for the domain. An
assistant acting under a delegation is an agent, not a human, and starts with no track
record, so an `audit` tool would be refused for everyone who could reach it. Whether an
agent acting for an `ESTABLISHED`+ human may audit under its delegation is a
constitutional-scope question for the owner (a proposed amendment, not a code change);
until then the "not yet independently audited" label clears only through human audits.

Deliverables:

- Four connector tools, all also usable through `/mcp/:token` and the REST API:
  - `list_tasks` (read-only, no token): open work by type and domain with counts, and
    the top few by priority with the claim text and a page link. Lets an assistant say
    what needs doing before anyone connects.
  - `next_task` (token): leases the next task through `Tasks::Lease` under the
    assistant's delegation, optionally filtered by `types`, `domains`, or a `claim_id`,
    and returns the packet in plain form: the objective, the claim, the untrusted
    excerpt or the counted evidence, the search direction, the known qualifiers, the
    allowed outcomes, and an `answer_with` note saying exactly what to send back. The
    packet hash and lease expiry are returned and kept server-side, so the assistant
    never handles signatures. Nothing available answers with a reason (no open tasks
    in the permitted types and domains, daily limit reached, or every open task
    belongs to the assistant's own principal).
  - `submit_task` (token): `task_id`, `outcome`, and an answer in the investigation
    vocabulary (`sources`, `excerpts`, `claims`, `evidence`, `links`, `groups`,
    `edges`, `supersede`) with local handles; `"target"` names the packet's claim and
    `"packet"` names the packet's source location. `Tasks::Answer` translates it into
    the ordered `TASK_RESULT` ops with refs and appends through `Assistants::Write`
    with the task id and packet hash, so every check in 04 §6 runs unchanged: allowed
    ops, scope rules, blind slots, automated acceptance. The reply says whether the
    result was accepted or is pending another principal, and returns the claim's card.
  - `release_task` (token): gives a lease back.
- Leasing excludes a task whose target stands on the assistant's own principal's
  say-so: recorded by that principal, directly or through an agent, and accepted by
  the system rather than by a different principal. 04 §3.1 asks for distinct
  principals per slot and Article XI forbids self-certification; a principal checking
  its own claim is neither an independent slot nor a check. A proposal another
  principal accepted (the demo's extracted claims, accepted by the curator) is that
  principal's responsibility too, so its author may still work it, which is what 08
  §7 step 7 does. This applies to every lease path, not only the connector.
- Instructions and skill: a "Working open tasks" procedure. On "work N tasks": call
  `next_task`, read the sources yourself, answer honestly (a documented null search is
  a result; `CANNOT_DETERMINE` is a result), `submit_task`, repeat N times or until
  nothing is available, then report each task in one line with its outcome and link.
  Never fabricate a source to have something to submit; never pad an answer.
- The connect page and FAQ gain the sentence a person needs: "Tell it: work five open
  tasks in Galedra."
- Older connected assistants: a delegation records the domains that existed when it
  was made, so an assistant connected before Stage 15 sees only those. The connect
  page says to disconnect and reconnect to pick up new subjects; no silent widening.

Acceptance:

1. Through `/mcp` with a token, `next_task` leases an `OPPOSING_EVIDENCE_SEARCH` task
   on another principal's claim, `submit_task` with `FOUND` and one source, excerpt,
   evidence, and `CONTRADICT` link on `"target"` appends a `TASK_RESULT` plus `ACCEPT`,
   the source is `retrieval_pending`, and the claim's card changes; the same for an
   `EVIDENCE_VERIFICATION` answer whose evidence sits on `"packet"`.
2. A `QUALIFIER_CHECK` answer that creates a narrower claim with a `NARROWS` edge and
   a `QUALIFY` link is accepted; one that supersedes another principal's link stays
   `PENDING`, and the reply says so.
3. `next_task` never hands an assistant a task on a claim its own principal recorded,
   and answers with the reason when that is all that is open; `list_tasks` needs no
   token and shows counts that match the tasks page.
4. A submission after the lease expired, with a wrong outcome for the type, or with an
   op the type does not allow is refused with the existing codes and appends nothing;
   `release_task` returns the slot.
5. A read-only OAuth grant is refused on `next_task` and `submit_task` with
   `INSUFFICIENT_SCOPE`; anonymous (tokenless) callers are refused on `next_task` with
   the connect instruction, since leases need a delegation. Demo goldens, replay, and
   `ledger:verify` are unchanged.

Owner decisions to record: whether an agent acting for an `ESTABLISHED`+ human may
audit under its delegation (needs an amendment to 05 §8); whether anonymous per-source
assistants may lease tasks at all (this stage says no: a lease needs a delegation with
a principal someone can hold to account).

## Decision Log (2026-09-18)

- Four MCP tools: `list_tasks` (no token), `next_task`, `submit_task`, `release_task`.
  `Tasks::Answer` presents a leased task in plain form with a per-type `answer_with`
  note and translates an answer in the investigation vocabulary (handles; `"target"`
  for the task's claim, `"packet"` for its passage) into the ordered `TASK_RESULT`
  ops with refs; `Assistants::Write.result` signs the `eir-result-v1` envelope with
  the assistant's agent key under its delegation. Every 04 §6 check runs unchanged.
  The initialize instructions and the skill carry the "work N open tasks" procedure.
- Self-checking. `Tasks::Lease` never hands a principal a task whose target stands on
  its own say-so (recorded by it and accepted by the system). The first draft
  excluded anything the principal recorded and broke the public demo, where the
  verifier searches opposing evidence on a claim it extracted and the curator
  accepted; the narrower rule keeps 08 §7 intact and still stops an assistant from
  verifying the claim its own person just recorded.
- Active-lease uniqueness. The unique indexes on `task_assignments` were
  unconditional, so a contributor whose lease expired could never take the task
  again, and the lease's retry-on-conflict loop spun until Postgres ran out of lock
  memory. They are now partial (`LEASED`, `SUBMITTED`), matching 04 §7 "one active
  lease", the retry is bounded, and every assignment lookup takes the contributor's
  latest row.
- Same-result claims. A claim created earlier in a `TASK_RESULT` was rejected as
  unaccepted when a later op in the same result linked to it or drew an edge from
  it, which made the qualifier task's "narrower claim with an edge" impossible. Edges
  and links now treat claims created in the same result as current; the result is
  accepted or held as one.
- Audits stay human. Spec 05 §8 admits as auditor a human at `ESTABLISHED`+ or a
  contributor with a track record in `AUDIT`; an assistant under a delegation is
  neither, so no audit tool was added. Owner decision reserved: whether an agent
  acting for an `ESTABLISHED`+ human may audit under its delegation (an amendment to
  05 §8). Also reserved and decided conservatively here: anonymous assistants (per
  source or by anonymous OAuth grant) may record but not lease.
- Constitutional Test (identity, visibility): 1 more traceable (every result is a
  signed, attributed `TASK_RESULT` on a signed packet); 2 yes; 3 no; 4 no; 5 yes; 6
  yes; 7 yes, anyone connected under a name may work tasks; 8 yes; 9 yes, an
  assistant never checks its own person's say-so; 10 yes.
