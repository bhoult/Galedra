# P1 — Assistants as contributors

Planned 2026-09-18, after `v0.1.0`. Same rules as P0: one stage at a time, tagged, only
when asked. `07` Phase 8 items not listed here (questions and hypotheses, dedup edges,
export mappings, personal assessments, the political-speech view) stay unplanned.

**The target user.** Someone reads a claim or a meme on social media and is about to
repost it. They are not a researcher and will not learn a vocabulary. The pitch is one
sentence: *take your favourite AI, tell it to check this in Galedra before you post it.*
The assistant they already use (Claude, ChatGPT, Grok, or anything that speaks MCP or
plain HTTP) does the work; Galedra records it so the next person does not have to.

**Design rules for every P1 stage.**

- One instruction, one link back. The user says "check this in Galedra"; the assistant
  returns an answer card and a URL. Nothing else is required of the user.
- Assistants cannot hold keys, so the server signs for them. Every such write is a
  server-custodied contribution under a delegation that names the assistant in the
  `software` field. Same log, same rules, same audit sampling.
- Galedra stores claims, excerpts, and a link plus a content hash to the source. It
  never fetches URLs and never stores a page's full text (`01 §7`). The assistant
  quotes the passage it read; the hash lets anyone later check the page is unchanged.
- Anonymous contributions are allowed. They are weighted in audit sampling, task
  priority, rate limits, and labelling, never in claim scores: identity does not
  replace evidence (Art. XI) and reputation is not a scoring input in v0.1
  (Invariant 8). Changing that is an owner decision, recorded before it is built.
- Assume the reader has thirty seconds. Every result leads with a plain-language
  headline and a "what to say instead" line before any number.
