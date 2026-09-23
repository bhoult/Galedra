# Stage 36 — A quotation interrupted by markup is not a quotation that is missing

**Status:** planned · tag will be `stage-36-interrupted-quotes`

**Tag:** `stage-36-interrupted-quotes` · **Spec:** 02 §3 (projections), 04 §6 (source
retrieval), 06 §4 (display rules), Articles XIX (transparency over persuasion), XXII
(reveal our own weaknesses), XXIII (no conclusion is immune from re-examination),
Invariants 4 (deterministic scores), 10 (nothing invented), 11 (untrusted text stays inert)

Goal: stop Galedra telling a reader that an accurate quotation was not on the page.

## What happens today

`Sources::Retrieve.findings` gives each `SourceLocation` one of `VERBATIM`, `NORMALIZED`,
`NOT_FOUND` or `UNSUPPORTED`, in that order of attempt. `NOT_FOUND` is the fallthrough, so
it carries two entirely different meanings: *this passage is not on this page*, and *we
could not line it up with the page*. The claim card says the first — "A quoted passage was
not found on the page when Galedra fetched it" — for both.

Claim `e8e0b673` is the worked example, filed as bug report `01a0c01e` by a connected
assistant and diagnosed by it. The page (qz.com) was fetched successfully: outcome
`FETCHED`, 331,009 bytes, final URL unchanged. The sentence on the page reads:

```html
Nvidia<a href="/quote/NVDA">$NVDA</a>'s equity investments in AI companies
```

`extract_text` replaces every tag with a space and keeps the anchor's own text:

```ruby
.gsub(/<[^>]+>/, " ")   # → "Nvidia $NVDA 's equity investments in AI companies"
```

The filed excerpt is `Nvidia's equity investments in AI companies` — what a reader sees,
because a reader skips the ticker chip. `normalize` does NFKC, case, quote, dash and
whitespace folding, none of which can remove an interpolated token, so the comparison
fails and the claim carries a not-found label on a faithful quotation. **Correct sourcing
is displayed as discredited sourcing**, which is the worst direction for this to fail in.

The bucket counts on that run were `VERBATIM 39 / NOT_FOUND 14 / NORMALIZED 3`, and the
first reading of them here was that normalization rarely rescues, so failures are absence
rather than near-miss. The filer's rereading is better and is the premise of this stage:
normalization rarely rescues **because it only handles typography**, while the common real
failure is publisher markup injected mid-sentence — tickers, inline links, footnote
markers, `<sup>` references. Those are absence-shaped on pages that are entirely present.

## The line this stage must not cross

**Do not make the verifier lie in the other direction.** The tempting fix is to strip
anchor text before matching, so the excerpt matches. That would let a quotation silently
span text it does not contain, and it would do so invisibly. If someone quotes
`the study found higher productivity` where the page reads `the study found <a>no evidence
of</a> higher productivity`, stripping produces a match on a sentence that says the
opposite. The filer argued against this and is right: the answer is a new verdict, not a
looser match.

**No fuzzy matching.** No edit distance, no thresholds, no similarity scores. Every
rendering below is a deterministic function of the bytes and a fixed element list, so the
same page yields the same finding forever (Invariant 4). A threshold is a number someone
would later tune, and tuning it would silently move verdicts on claims already recorded.

**The finding stays a fact, not a verdict.** `Tasks::Answer` already hands it to an
`EVIDENCE_VERIFICATION` worker as "A fact for you to weigh, not a verdict." That framing is
kept exactly, and the new value gets the same treatment.

## The mechanism

Three renderings of the same body, tried in a fixed order, all deterministic:

1. **As served** — the current `extract_text`: every tag becomes a space.
2. **Inline-joined** — inline elements' tags are removed with *no* space and their text is
   kept; every other tag still becomes a space. `Nvidia<a>$NVDA</a>'s` → `Nvidia$NVDA's`.
   This catches passages the current pass breaks by inserting spaces at `<em>`, `<b>` and
   `<span>` boundaries, which is a distinct and more common failure than the qz.com one.
3. **Inline-elided** — inline elements are removed *content and all*, with no space.
   `Nvidia<a>$NVDA</a>'s` → `Nvidia's`. This is what a reader sees when they skip a chip.

The verdict is the first that matches, verbatim then normalized, giving the finding order
`VERBATIM`, `NORMALIZED`, `INTERRUPTED`, `NOT_FOUND`, `UNSUPPORTED`.

The safety property that makes (3) admissible is that **elision only removes text**. If the
excerpt matches the elided rendering, every character of the excerpt came from outside an
inline element, so no quotation can be made to span words it does not contain. The
opposite-meaning example above does *not* match rendering 3: eliding `<a>no evidence of</a>`
leaves `the study found  higher productivity` with the excerpt's own words intact only if
the excerpt never crossed the elided span — and this one does, so it stays `NOT_FOUND`.
That property is a test, not a comment.

`INLINE_ELEMENTS` is a frozen constant — `a abbr b cite code data dfn em i kbd mark q s
samp small span strong sub sup time u var` — beside `NAMED_ENTITIES` in
`Sources::Retrieve`. Adding to it is a code change and a spec change, deliberately.

## What this does and does not touch in scoring

**It touches nothing in scoring, and the stage must not change that.** `SourceRetrieval` is
read by `Cards::ClaimCard`, `Graph::Presenter`, `Tasks::Answer` and two views. It is not
read by anything under `app/services/scoring/` or `app/services/audits/`. The retrieval
finding has never been a scoring input and does not become one here, so no model version is
required and no golden value moves. `spec/` gets an assertion that the scoring services do
not reference `SourceRetrieval`, so a later change cannot make this quietly untrue.

The filer raised the scope question as "does INTERRUPTED count as verified for scoring?"
The premise needs correcting in its favour: nothing Galedra fetches counts for scoring in
either direction. What reaches scoring is an `EVIDENCE_VERIFICATION` result that a person or
their assistant submits after reading the source themselves. So the real question is the
narrower one, and it belongs in `Guidance` rather than in a config: **what should a worker
do when the packet says `INTERRUPTED`?** The answer this stage adopts is *confirm it if the
passage is faithful to what a reader reads*, because the interruption is an artefact of our
extraction and not a property of the source — which is the filer's position, and it is right
for its reason rather than for convenience.

## A caveat on the evidence for this stage (2026-09-20)

Every markup judgement made while working this outline — including the three research passes
on chapter 12 — came from **converted markdown rather than raw HTML**, because `curl` egress
was blocked in the connected assistant's environment and its research ran through a
converting fetcher. Markup interrupting a sentence is exactly what a converter normalises
away, so those passes could not have seen the failure this stage exists to fix.

The one passage anyone has read as raw bytes is the qz.com anchor in `01a0c01e`, confirmed
against `Sources::Retrieve.extract_text` on this side. That is a sound single case and it is
still a single case. Before the `INTERRUPTED` verdict ships, at least one more instance should
be confirmed from raw HTML, or acceptance 1's fixture should be understood as the whole of the
evidence rather than a sample of it.

## Not in this stage: PDFs (2026-09-22)

Bug report `acd7b1bf` asks for PDF text to be extracted so a passage quoted from one can be
checked (the Ipsos AI Monitor 2026, evidence `d7a2f011`). Galedra's fetch does not read a
PDF: `Sources::Retrieve::TEXT_TYPES` has no `application/pdf`, and since `79ffd4f` such a
passage reads `NOT_READ` — *we did not look* — rather than a verdict. Two of the node's four
PDF retrievals predate that change and still carry the old `UNSUPPORTED`, which is the label
the filer read.

Reading PDFs needs a text extractor, which is a new dependency, and the stack is decided, so
**whether to add one is the owner's call** and not part of this stage. If it is taken, it
belongs beside this stage's renderings: a PDF's extracted text breaks lines and hyphenates
where the page did, which is the same class of failure as markup interrupting a sentence, and
the same rule applies — the matcher may only ever remove what the extraction inserted, never
bridge words the source does not contain. Nothing about it reaches scoring, for the reason in
the section above.

## Deliverables

1. `SourceRetrieval::FINDINGS` gains `INTERRUPTED`; the column is a validated string against
   a closed list, so this is a constant change and no migration.
2. `Sources::Retrieve` gains `INLINE_ELEMENTS` and two further renderings, with `findings`
   attempting them in the fixed order above. `extract_text` keeps its current signature and
   behaviour; the new renderings are separate methods, so the existing goldens for served
   text are untouched.
3. `Cards::ClaimCard` gains its own sentence, and it must not be a hedge of the not-found
   one: "A quoted passage is on the page but our reader could not line it up with it,
   because the publisher's markup interrupts the sentence." The existing "every quoted
   passage was confirmed" line counts `INTERRUPTED` as confirmed for display, since it is.
4. `Tasks::Answer` passes the new finding through with the same "a fact for you to weigh"
   note, plus one sentence saying what interrupted means and that the passage is present.
5. `Guidance::WORK` gains the worker rule above; `Guidance::VERSION` bumps.
6. `/sources/:id` and `/tasks/:id` show the new value with the same treatment as the others.
7. The source page shows, for an `INTERRUPTED` location, the rendering that matched, so a
   reader can see the markup rather than be told about it.

## Acceptance

1. A fixture page containing `Nvidia<a href="/quote/NVDA">$NVDA</a>'s equity investments`
   and the excerpt `Nvidia's equity investments` yields `INTERRUPTED`, not `NOT_FOUND`.
2. A fixture containing `the study found <a>no evidence of</a> higher productivity` and the
   excerpt `the study found higher productivity` yields `NOT_FOUND`. This is the test that
   the stage did not make the verifier lie; it fails loudly if elision is applied to a span
   the excerpt crosses.
3. `the <em>very</em> best` with excerpt `the very best` yields `NORMALIZED` or
   `INTERRUPTED`, never `NOT_FOUND` — the inline-joined rendering closes it.
4. Every existing `docs/epistemic-ledger-poc-spec-v4` golden and `bin/demo` row is
   unchanged, and the reference scorer prints `ALL PASS`.
5. Re-running retrieval on claim `e8e0b673` moves it off the not-found label, and bug report
   `01a0c01e` is closed by its filer rather than by us.
6. A spec asserts no file under `app/services/scoring/` or `app/services/audits/` mentions
   `SourceRetrieval`.

## The Constitutional Test

Answered because this changes what a page displays about evidence, which is a visibility
change even though it is not a scoring one.

1. **Does it preserve the reasons?** Yes, and it adds one. Today two different findings
   share a label; afterwards they do not.
2. **Could it manufacture agreement?** No. The elision property forbids a match across text
   the excerpt does not contain, which is the only route by which this could invent support.
3. **Does it let identity substitute for evidence?** No; nothing here reads who filed the
   excerpt.
4. **Does it hide anything?** No. It removes a hiding place: the current `NOT_FOUND` conceals
   which of two things happened.
5. **Is it deterministic and versioned?** Yes. Fixed element list, no thresholds, and no
   scoring input, so no model version is needed — stated explicitly so a later reader does
   not assume it was forgotten.
6. **Does it double-count?** No; findings are per location and independence is untouched.
7. **Is AI being treated as evidence?** No. Galedra's own fetch is a fact for a worker to
   weigh, unchanged.
8. **Does reputation leak in?** No.
9. **Can it be audited and reversed?** Yes: retrieval is re-runnable, findings are rows with
   validity windows, and the previous finding stays in the log.
10. **Is anything invented?** No. Every rendering is a function of the served bytes.
