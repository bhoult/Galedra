# Stage 33 — Take an outline away as a file you can read

**Status:** planned · tag will be `stage-33-static-export`

**Tag:** `stage-33-static-export` · **Spec:** 02 §1.3 (validity windows), 02 §6 (canonical
JSON and hashing), 03 §7 (a score is meaningless without its model and snapshot), 06 §2
(API), 06 §4 (display rules), 14 §P1 (independent mirrors), Articles VII (attribution),
XIII (corrections do not erase history), XVI (answers first, numbers on request),
XIX (transparency over persuasion), XXI (research should be cumulative), XXIII (no
conclusion is immune from re-examination), Invariants 2 (projections are derived),
4 (deterministic scores), 16 (the answer card is the default view), 17 (determinism is not
objectivity)

Goal (owner request, 2026-09-19): a large outline is a significant piece of work, and the
person who made it should be able to keep a local copy of it when it is done — as static
HTML, Markdown, or PDF.

The run that prompted this produced, from one two-hour source: 62 sections, 47 leaves,
141,937 characters of readings, ~250 claims and ~780 open checks, over roughly 2,500 signed
contributions. That is hours of an assistant's work and a real amount of a person's
attention. At present the only way to keep it is to keep the node running.

## How this differs from Stage 28, and why both exist

Stage 28 exports **JSON for machines**: signed envelopes, verifiable, importable, built so
another node can mirror or re-assert the graph. Its hard problem is forgery — never letting
a copy claim signatures it does not have.

This stage exports **a document for people**: one file, opened by double-clicking it,
readable in ten years on a machine that has never heard of Galedra. It is deliberately a
dead end. It does not import, it carries no signatures, and nothing reads it back.

The two must not be conflated in the UI. A person who wants "my outline" wants this one;
a person who wants "the record" wants Stage 28. Offering only the second to someone asking
for the first is the mistake this stage exists to avoid.

## The line this stage must not cross

**An exported file must never read as more settled than the record it came from.**

A static file outlives the thing it describes. The node moves on: evidence arrives, audits
run, claims are superseded, scores change. The file does not. So every export states, on
its face and not in a footer:

- the **snapshot seq** and the **scoring model** it was produced under, because `03 §7` says
  a number without both is meaningless, and a file is exactly where such a number goes to
  be quoted out of context;
- that it is a **point-in-time copy**, with the date and the node it came from, and the URL
  where the live version is;
- that claims in it are **provisional until audited**, in the same words the pages use.

It carries the answer card's plain headline, never a bare probability at the top of a
claim (Invariant 16). It never says true or false. A claim with no evidence says so.

## What it produces

One command, three renderings of the same content, from the same builder:

| Format | What it is | How |
|---|---|---|
| **Markdown** | one `.md`, plain text, diffable, greppable | rendered directly |
| **HTML** | one self-contained `.html`, no network at all: CSS inlined, no fonts, no scripts | rendered directly |
| **PDF** | the HTML with a print stylesheet | **the browser's own print-to-PDF** |

**PDF deliberately adds no dependency.** Galedra's stack is settled and a PDF engine is a
large one — a gem that renders its own layout, or a headless binary in the image. Instead
the HTML gets a real `@media print` stylesheet with page breaks at sections, and the export
page says "open this file and print to PDF". If that proves insufficient, adding an engine
later is a separate decision with its own justification; starting without one is the
reversible choice.

## What goes in it

The whole outline, in document order, at one snapshot:

1. **Header**: outline heading, source title, canonical URI, node, export date, snapshot
   seq, scoring model, and the counts by state.
2. **The tree**, as a table of contents with the same counts the sidebar shows.
3. **Each section**, in depth-first order: heading, locator, the quoted anchor marked as a
   quotation, and the **reading** marked as a transcription with its contributor and date —
   the Stage 30 distinction survives into the file, because collapsing it there would
   publish edited speech as though it were quoted.
4. **Each claim** under its section: text, type, the plain headline, the evidence for and
   against with sources and excerpts, interpretive steps, and how many checks are open.
5. **Footer**: the share line, the licence notice, and what is deliberately absent.

### Options, because one shape does not fit

- `--readings` / `--no-readings` — with the full text, or the structure and claims only.
  The difference on the run above is ~142,000 characters against ~15,000.
- `--evidence` / `--no-evidence` — every excerpt, or claims and their headlines only.
- `--claims-only` — no tree, for citing.

## Copyright, which this stage cannot dodge

A file is easier to redistribute than a page, and an outline's readings are a transcription
of someone else's work — on the run above, ~142,000 characters of a commercial podcast.
Export does not change the rights; it changes how easily they are exercised badly.

So: the default carries readings **only when the source's `license` field says they may
travel**, and that field is currently `nil` on every source. Until the owner settles the
policy in `docs/LICENSE-POLICY.md`, `--readings` is opt-in, prints the source's attribution
and licence beside the text, and the file states that readings are a contributor's
transcription of a third-party work, not a licensed copy of it.

This is not a legal opinion and the stage should not pretend to give one. It is the
conservative default while the decision in the owner list is open, and it is easy to relax
once that decision is made. **This stage should not ship its default before that decision.**

## Determinism

The same outline, at the same seq, under the same model, exports **byte-identical** output.
That follows from Invariant 4 and is worth stating because it makes an export citable: two
people can compare files and know any difference is a difference in the record. Ordering is
the tree's document order, already verified for readings; iteration over claims and evidence
is by `(position, id)`, never by hash order or `created_at`.

## Performance, which is the real risk

The builder touches every section, reading, claim, score and evidence item under one root.
A live `record_investigation` on this corpus was observed issuing **21,543 queries in one
request** (`docs/experiments/2026-09-19-live-connector-outline.md`, finding 2). A naive
exporter over ~250 claims would be worse and would hold a request open for minutes.

So it batch-loads by design: sections in one query, locations in one, claims and placements
in one, scores through `Scoring::Score.call_many` at a fixed seq, evidence and links grouped
in one pass each. It renders to a file rather than a response, runs as a job for anything
large, and the page offers the finished file. **Acceptance includes a query-count ceiling**,
because this is the place where an N+1 hides best and hurts most.

## Where it lives

- `bin/rails 'export:outline[SECTION_ID]'` with `FORMAT`, `READINGS`, `EVIDENCE` — the
  primary interface, and the one that needs no browser.
- A **download button on the outline page**, which for a large outline enqueues a job and
  offers the file when it is ready.
- `GET /api/v1/sections/:id/export?format=` — described in `Api::Openapi` in the same
  commit, per the standing rule.
- Not an MCP tool. An assistant has the graph already; this is for the person.

## Acceptance

1. Exporting the Moonshots outline in each format produces one file that opens with no
   network access, containing all 47 leaves in document order.
2. Every rendering states the seq, model, node, date and provisional status on its face.
3. Anchors are marked as quotations and readings as transcriptions, distinguishably, in all
   three formats.
4. Two exports of the same outline at the same seq and model are byte-identical.
5. `--no-readings` omits every reading and says in the file that it did.
6. The whole export runs under a stated query ceiling and does not hold a web request open.
7. No claim appears with a bare probability above its plain headline.
8. The HTML passes with scripts and remote loads disabled; the print stylesheet breaks pages
   at sections.

## Open questions for the owner

- **The licence decision above**, which gates the readings default. This stage should wait
  for it rather than guess.
- Whether an export should include **open task counts** — useful for "what is left", but it
  is the part that ages fastest and is meaningless the day after.
- Whether a PDF engine is wanted after all, if print-to-PDF proves too manual for the
  people who will actually use this.
- Whether exports should be **retained server-side** for re-download, which is a storage and
  a privacy question, or streamed once and forgotten.
