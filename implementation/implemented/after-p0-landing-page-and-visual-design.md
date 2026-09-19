# After P0 — Landing page and visual design

**Status:** implemented · decisions recorded 2026-09-18 · no tag (work between stages)

## Decision Log (2026-09-18)

- The signed-out home page is an introduction: the demo paragraph with its three
  compact answers from `08 §9` (linked to the live claims when the public demo is
  seeded), the seven-step pipeline, four use cases with worked examples (`01 §1.1`,
  `01 §3`), the display rules as "you will see / you will not see" (`06 §4`), the
  Foundational Statement, and a pointer to the constitution rather than its text.
  Signed-out visitors get a two-item menu, Constitution and FAQ; signed-in users get
  the full navigation and the dashboard. Outward examples use the `08` demo and short
  fictional scenarios, never Watchers.
- `GET /constitution` renders the whole constitution and `GET /faq` answers the common
  questions in the spec's own terms. The constitution page renders `CONSTITUTION.md`,
  the bytes the published `constitution_hash` covers, parsed by
  `Governance::Constitution#sections` and converted with kramdown, so what a visitor
  reads is what the hash certifies. No spec file was edited.
- Behind the landing page a Stimulus controller draws a slowly growing graph on a
  canvas. Each new branch opens as a small block of text that breaks into lines;
  each line flies to its place and shrinks into a dot, one statement node forking
  into two to four parts. Cross-links form nearby, pulses travel along links, and
  old leaves fade so the picture keeps evolving. It is decorative,
  reads no ledger data, pauses when the tab is hidden, and shows one static frame
  under `prefers-reduced-motion`.
- One stylesheet, no framework: serif headings, a paper palette, cards, tables, forms,
  a sticky header, and a footer carrying the constitution version and hash on every
  page. Rule 12 still holds: no true/false colours and no badges of correctness. All
  class names the system specs depend on are unchanged.
- Auth pages lost their inline colour styles and gained labels. Gem added: kramdown.
- Phones: the Rails `:modern` browser gate returned 406 to Safari before 17.2, so the
  gate now lists explicit minimums (Safari 16.4, Chrome 111, Firefox 114, Opera 97),
  the versions that support import maps. On narrow screens tables scroll inside their
  own box and headings wrap long enum words, so no page widens past the device. Checked
  as an emulated iPhone and Pixel on every page, signed in and out.
- Coverage: SimpleCov runs with the suite and fails it below 90% line coverage. Line
  coverage is 95%; branch coverage is reported but not enforced. Request specs were
  added for signed lease and release requests, sessions and sign-up, moderation and
  audit recompute paths, and the full recompute job.
- The FAQ gained sections on epistemology (justification not truth, evidentialism,
  testimony, suspension of judgment, model-conditional probability) and hermeneutics
  (textual versus interpretive claims, interpretive steps, competing readings, the
  hermeneutic circle), and quotes Genesis 31:48 under the name.
