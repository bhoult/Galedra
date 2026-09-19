# Stages 20–22 — Large sources: outlines, sections, and work shared out

Planned and built 2026-09-19 as Stages 20, 21, and 22, one tag each; this file is the
shared goal and vocabulary the three stage files rest on. They share one goal and are split so that each leaves the demo goldens,
`ledger:replay`, and `ledger:verify` unchanged and can be reviewed on its own.

The goal: Galedra so far takes a meme or a paragraph. It should take a whole podcast
transcript, a political speech, a sermon, or a long article: thousands of claims from
one source. When the assistant can do the whole check in about a quarter of an hour it
does it now, as today. When it cannot, it records the **structure** first (the source,
an outline of sections nested like a directory tree, and one extraction task per leaf
section), so that other volunteers' assistants can take the work in pieces, and then
asks the person whether it should start on the research itself. A claim that belongs
to an outline shows the outline beside it, as a tree with the current claim
highlighted, so a reader always sees where in the speech or the episode a claim sits.

```text
Moonshots episode 123                       (root section; source: the transcript, by link)
├── LLM alignment
│   ├── OpenAI                              (leaf; TIME_RANGE 00:41:10–00:47:30)
│   │   ├── C1  "OpenAI published its Preparedness Framework in December 2023."
│   │   └── C2  …
│   ├── Anthropic
│   └── Open models
└── "Math is cooked"
    └── Millennium Prize
```

Vocabulary, fixed here so no synonym appears anywhere: an **outline** is a tree of
**sections** over one source; a **root section** has no parent; a **leaf section** has
no children; a claim is **placed** in a section by a **placement**. Not "chapter",
"topic" (taken), "collection" (reserved by 14 for federation), "folder", or "dossier".
