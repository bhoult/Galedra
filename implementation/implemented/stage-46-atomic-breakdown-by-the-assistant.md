# Stage 46 — The atomic breakdown comes from an assistant, not a sentence splitter

**Status:** built 2026-10-05 · tagged `stage-46-atomic-breakdown` · the owner's one decision taken 2026-10-05 (marked **Owner**)

**Tag:** `stage-46-atomic-breakdown` · **Spec:** 02 §4 (atomicity), 04 §2 (task types),
06 §5 (Analyze text, the per-source answer card), Articles IV (atomicity), XIV (contributors,
not oracles), XIX (transparency over persuasion), Invariant 18 (Galedra runs no model)

## Where this comes from

The owner, 2026-10-05: "Analyze text" in the menu breaks a pasted text into assertions
deterministically, and the owner doubts that it is accurate; the atomic breakdown should come
from the assistant that submits the text.

## The evidence

`Claims::Extract`, behind `Llm::Adapter#extract_claims`, splits on sentence punctuation and
guesses a type from keywords. Run on five ordinary statements on 2026-10-05 (host Ruby,
loading `app/services/claims/{atomicity,extract}.rb` directly):

```
IN:  The new law, passed in 2023, cut violent crime by 40% and saved taxpayers $2 billion, according to the mayor.
  -> [QUANTITATIVE] The new law, passed in 2023, cut violent crime by 40% and saved taxpayers $2 billion, according to the mayor.  warnings=["ATOMICITY_CONJUNCTION", "ATOMICITY_SERIAL"]

IN:  Einstein failed math in school and later won the Nobel Prize for relativity.
  -> [OBSERVATIONAL] Einstein failed math in school and later won the Nobel Prize for relativity.  warnings=["ATOMICITY_CONJUNCTION"]

IN:  Vaccines cause autism, which is why rates rose after the MMR shot was introduced in 1971 and doctors won't admit it.
  -> [CAUSAL] Vaccines cause autism, which is why rates rose after the MMR shot was introduced in 1971 and doctors won't admit it.  warnings=["ATOMICITY_CONJUNCTION"]

IN:  Dr. Smith of the U.S. Dept. of Energy said the plant is safe. It isn't.
  -> [OBSERVATIONAL] Dr.  warnings=[]
  -> [OBSERVATIONAL] Smith of the U.S.  warnings=[]
  -> [OBSERVATIONAL] Dept.  warnings=[]
  -> [OBSERVATIONAL] of Energy said the plant is safe.  warnings=[]
  -> [OBSERVATIONAL] It isn't.  warnings=[]

IN:  Coffee is good for you: a 2019 Harvard study of 500,000 people (Lee et al., 2019) found drinkers live longer.
  -> [QUANTITATIVE] Coffee is good for you: a 2019 Harvard study of 500,000 people found drinkers live longer.  warnings=[]
  -> [TEXTUAL] Lee et al. (2019) reports that coffee is good for you: a 2019 Harvard study of 500,000 people found drinkers live longer.  warnings=[]
```

What that shows:

- **It does not split compound assertions.** Four checkable parts of the first statement
  (passed in 2023, cut crime 40%, saved $2 billion, the mayor said so) come back as one claim
  with a warning. Article IV asks for the parts.
- **It shatters abbreviations** into claims reading "Dr." and "Dept.".
- **It cannot resolve a reference.** "It isn't." is proposed as a claim.
- **Its types are keyword guesses.** A causal claim about a law is `QUANTITATIVE` because it
  holds a number.
- **Its citation rule misattributes.** It credits Lee et al. with "coffee is good for you",
  which is the writer's gloss, not the study's finding.

It passes its one spec (`spec/services/cards/answers_spec.rb`) because that spec's memo is the
input it was written for. The proposals are presented as "atomic claims for you to edit", and
a person is entitled to read that as a breakdown someone did. That is a label that does not
match what was done (Stage 44 A1), on the page most first-time users try first.

**How much it has been used.** On galedra.org on 2026-10-05, of 1,087 claims, exactly one
came through Analyze text: "All dogs go to heaven." (seq 296, from a source titled "test"),
named by no investigation. Every claim named by any of the 1,208 investigations came from an
assistant: 927 recorded directly, 41 from task results, 9 as corrections. That follows from
the code, since only `Investigations::Record` and `Investigations::Outline` create an
investigation and both take their claims from the caller. So nothing recorded needs
redoing; the harm is to the next person who tries the page, not to the record.

Invariant 18 rules out the obvious fix: Galedra runs no model, so the server cannot do the
breakdown better. The breakdown is model work, and model work is done by a connected
assistant and enters as a signed contribution.

## Deliverables

1. **Analyze text stops proposing claims.** It records the pasted text as a source, as now,
   then opens one `CLAIM_EXTRACTION` task on it (the type exists, targets `SOURCE`, and is
   accepted on submission) and shows two ways forward:
   - **With an assistant:** a `galedra:` prompt naming the source's URL, ready to copy, which
     a connected assistant answers by working that task or by `record_investigation`.
   - **By hand:** the existing claim form, empty, with `Claims::Atomicity`'s warnings inline
     as each claim is typed. A person breaking a text down is a contributor like any other.
   The source page lists the claims as they arrive, as it does today.

   **It and `/investigations/new` point at each other** (**Owner**, decided 2026-10-05: kept
   as two pages, not merged). Each says in one line what the other is for — raw text here, an
   assistant's draft there — and links to it, so a paste in the wrong place costs one click.

   **A size rule, the same one assistants are held to.** One `CLAIM_EXTRACTION` task takes at
   most 20 claims off one packet with a capped excerpt. A 10,000-word paste routed to it
   would come back as twenty claims off a truncated passage, which is the two-hour transcript
   recorded as thirteen claims all over again (`Guidance::SIZE`). A paste over about 3,000
   words is therefore refused on the page, naming the outline route (`create_outline` from an
   assistant), and opens no task. The threshold is `Guidance::SIZE`'s, read from one constant
   so the two cannot drift.
2. **`Claims::Extract` is deleted**, and `Llm::Adapter#extract_claims` with it. The memo spec
   in `answers_spec.rb` is rewritten deliberately: it now proves that Analyze text opens the
   extraction task and proposes nothing. Its last two assertions — the adapter is named
   `stub-v0.1`, and an unknown `LEDGER_LLM_ADAPTER` raises — are the Invariant 18 guard, not
   the extractor's, and survive the rewrite. `Claims::Atomicity` stays.
3. **Copy that described the stub** is corrected: `app/views/analyze/new.html.erb`, the FAQ
   (`home/faq.html.erb`), the glossary, and the dashboard card.
4. **Spec**, with a `REVIEW-NOTES.md` entry and `build-full-spec.sh` in the same commit:
   - 06 §5, the Analyze text line ("stub/LLM proposes claims") becomes paste, source, an
     extraction task, and the claims an assistant or a person records; the per-source answer
     card line ("one line per extracted claim") stays true and is checked.
   - 07 Phase 8 still lists "Real LLM adapter behind `Llm::Adapter`". Article XIV's last
     paragraph already forbids it; the line is struck while the file is open.
   - 08 §2 ("a user pastes this AI-drafted memo paragraph into Analyze text") stays true:
     08 §3 already gives extraction to `AgentVerifier`, an agent, which is the flow this stage
     makes real. No golden value in 08 §8 is touched.
   - `README.md` line 187 tells a new user to paste the memo into Analyze text "and follow
     the answer cards"; after this stage there are no cards until someone does the breakdown,
     so the sentence changes with it.

   Stages 09 and 10 are history and are not rewritten; this file records that they are
   superseded on this point.

## Acceptance

1. Pasting the five statements above records five sources, opens five `CLAIM_EXTRACTION`
   tasks, and creates no claim.
2. A connected assistant working one of those tasks records claims that appear on the
   source's page.
3. Nothing in `app/` calls `extract_claims`, and `Llm::Adapter` keeps only the functions that
   still have a caller.
4. `bin/demo` still prints PASS for every golden row (it never used the extractor; checked
   2026-10-05 by grep across `bin`, `lib`, `config`, `db`, `spec`, `app` and `examples`).
5. A paste of more than about 3,000 words is refused with the outline route named, and opens
   no task.
6. Analyze text and `/investigations/new` each link to the other.

## Constitutional Test (selection)

1. **More traceable?** Yes: every proposed claim is now a signed contribution by a named
   assistant or person, instead of an unsigned regex output presented as a proposal.
2. **Preserves the evidence chain?** Yes; nothing in it changes.
3. **Authority over evidence?** No.
4. **Hides uncertainty?** No. It removes a breakdown that looked done and was not.
5. **Unknown explicit?** Yes: until someone does the breakdown, the page says it has not been
   done.
6. **Open to audit?** Yes, more than before: extraction is an auditable task result.
7. **Resists capture?** Unchanged.
8. **Reproducible?** Yes.
9. **Shared and personal separate?** Unchanged.
10. **Reveals our weaknesses?** Yes; it stops presenting a known-weak function as a capability.

## Owner decision

- **Whether Analyze text should also take a pasted bundle**, merging it with
  `/investigations/new` (the paste flow for an assistant that cannot call tools). **Decided
  2026-10-05, as proposed:** keep them separate in this stage, each pointing at the other
  (Deliverable 1). Merging them is a redesign rather than a cleanup, and there is no use to
  design it from: Analyze text has been used once on galedra.org.

## What remains after this stage

Whether the two paste pages become one, decided once both have been used.

## How it closed (2026-10-05)

### What was resolved

Deliverables 1 to 4, and every acceptance criterion, 1 to 6 (4 by CI; see below). Analyze text stores the text and opens
its breakdown, and the server proposes nothing. The breakdown is done one of three ways:

- by the person's own assistant, through a prompt the page gives them;
- by a volunteer's assistant, through the extraction tasks;
- by the person, on a form.

### How

- **`Sources::Paste`** (`app/services/sources/paste.rb`) refuses a paste over
  `Guidance::MAX_CHECK_WORDS`, the constant Stage 45 introduced for the size rule. It names
  the outline route and records nothing. Otherwise it records the source and a location
  over the whole text, as before. It then opens one `CLAIM_EXTRACTION` task per reading
  window.
- **Reading windows, which the plan missed.** A packet carries at most 2,000 characters of
  excerpt (`Tasks::Types::EXCERPT_CAP`). The plan's single task over a 3,000-word paste would
  have read the first ~350 words and returned claims as if it had read them all, which is
  the failure the size rule exists to prevent. `Sources::Paste.windows` therefore cuts the
  text into exact slices no longer than a packet carries. Each cut is at a paragraph break
  where there is one in the window's second half, otherwise at the last space. This chooses
  where a reader's page ends, never what a claim is. A text short enough for one window gets
  one task over the whole-text location, as before.
- **The person's own assistant, which the plan also missed.** `Tasks::Lease` never hands a
  principal an extraction task on its own source, since only the routine checks are
  self-checkable (Stage 34). The plan's route, "a connected assistant answers by working that
  task", was therefore closed to the one assistant the person actually has. The prompt
  instead asks that assistant to record the breakdown as a check, with
  `record_investigation`.
  - Each claim carries a new `source` field, which becomes `CREATE_CLAIM`'s existing
    `source_id`.
  - The check gets a page, a share line and Stage 45's first readings.
  - When the recorder is the text's own principal, `Sources::Paste.cancel_extraction!`
    closes the open tasks, by the same rule as an outline's leaves.
  - A stranger filing under someone else's text leaves the tasks open.
  - `source` is refused with `attach_to`.
- **The form.** `sources#analyze` shows the prompt, the tasks and an empty form of five rows.
  - Live warnings while typing would need script, so they are approximated by "Check
    wording", which re-renders with `Claims::Atomicity`'s warnings and records nothing.
  - A row without the private-individual affirmation now stops the whole form before
    anything is written, and the writes are one transaction, so a refusal on any row
    appends none of them. Before, the rows ahead of a refused one had already been
    recorded.
- **Deleted.** `Claims::Extract`, and `Llm::Adapter#extract_claims` with it. The adapter keeps
  `summarize` and `resolve_affiliation`, which both have callers.
- **Copy.** `analyze/new` now says what happens, and links to Record an investigation, which
  links back. The breakdown page, the FAQ, the glossary, the dashboard card and the source
  page's link were updated. The glossary also had extraction as a proposal awaiting
  acceptance, which has been untrue since 2026-09-19, when extraction began to be accepted on
  submission; that is corrected.
- **The spec.**
  - 06 §5's Analyze text line is rewritten.
  - 07 Phase 8's "Real LLM adapter" is struck.
  - 13's XIV row is updated.
  - The README's walkthrough no longer sends a new user to paste the memo and "follow the
    answer cards".
  - The Watchers README's atomicity line said the stub proposed four claims; it never did.
  - `REVIEW-NOTES.md` has entry Q, and `FULL-SPEC.md` was regenerated.
  - 08 §2 and the per-source answer card line in 06 stay true and are unchanged. No golden
    value is touched.
- **The guard.**
  - `spec/requests/analyze_text_breakdown_spec.rb` has one example per acceptance criterion,
    plus the own-assistant route and the reading windows. The windows example checks that
    every excerpt fits a packet, that together they hold every word in order, and that each
    is an exact slice of the source.
  - `spec/system/analyze_text_spec.rb` is rewritten for the form.
  - The memo example in `spec/services/cards/answers_spec.rb` now proves the server proposes
    nothing. It keeps the two Invariant 18 assertions.

### What remains

- ~~**Acceptance 4 (`bin/demo` prints PASS)** was not run locally.~~ **Met 2026-10-05:** CI's
  demo job passed on the push of this stage (run 37392186114, commit `0e595bb`). It was not
  run locally, because it resets the development log, and that is someone's working data.
- **The owner's decision on merging the two paste pages**, deferred until both are used.
- **Real assistants given the prompt are unmeasured.** No run of the external-agent loop has
  checked whether a connected assistant fills in `source` from the prompt. There is a second
  thing to read on the first live run. `galedra:` means "record the whole statement", so an
  assistant reading that literally may record the prompt's instructions as part of
  `investigations.statement`. The prompt now puts the text below a line and names it as the
  statement, but only a run shows whether that is enough. If assistants ignore `source`, the
  fix belongs in `Guidance`, which does not mention it yet.
- ~~**Deployment** waits on the owner.~~ **Deployed 2026-10-05** at `7233817`
  (`stage-46-atomic-breakdown-2-g7233817`), with the code review's fixes, on the owner's say-so.
  The migration ran on boot, guidance `2026-10-05.2` is served, and the check, claim and card
  pages answer 200.
- **Found, not this stage's.** "Create verification tasks" on a source page points every
  claim's evidence check at the location over the whole text. That packet's excerpt stops at
  2,000 characters, so a claim taken from late in a long paste is checked against an excerpt
  that does not contain it. The whole-text location predates this stage. Before it, Analyze
  text had no size limit at all.


### Code review, 2026-10-05

Found after the stage closed and fixed the same day. Each fix has an example in
`spec/requests/analyze_text_breakdown_spec.rb` that fails against the code above.

- **"Check wording" did nothing in a browser.** It answers the POST with the form itself
  (200), and Turbo Drive drops a form response that is not a redirect. The system spec runs
  on `rack_test`, without Turbo, so it passed. The form now opts out of Turbo, as
  `assistants/new` already did for the same reason.
- **A refused row lost the form.** A `Ledger::Rejected` inside the transaction (a claim over
  `Claim::MAX_TEXT_CHARS`, a topic outside the vocabulary) fell to `ApplicationController`'s
  `redirect_back`. That dropped every typed row, and after "Check wording" the referer is
  the POST-only claims URL, which has no GET. `create_claims` now renders the form again,
  with the rows and the refusal, and records nothing.
- **Words did not bound the prompt.** The prompt hands the text on as `statement`, which
  `record_investigation` refuses past `Investigation::MAX_STATEMENT_CHARS` (20,000). Text
  with few spaces is a handful of words however long it runs, so a long Chinese or Japanese
  paste passed the 3,000-word rule and produced a guaranteed refusal. `Sources::Paste` now
  also refuses past `MAX_CHARS`, the same constant.
- **The same paste twice opened two sets of tasks.** The source and its locations are the
  same entries the second time (the idempotency key), but tasks have no such key. A paste
  whose source already has extraction tasks now opens none, and the paste is one
  transaction, so a refusal partway leaves no source without its tasks.
- **The notice counted rows, not claims.** Two identical rows are one `CREATE_CLAIM`; the
  notice now counts what was appended.
