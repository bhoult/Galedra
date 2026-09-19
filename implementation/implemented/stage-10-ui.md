# Stage 10 — Hotwire UI

**Status:** implemented · tag `stage-10-ui` · decisions recorded 2026-09-17

## Plan

**Tag:** `stage-10-ui` · **Spec:** 06 §4 (all display rules), §5 (all pages), §6 rule, §7 search, 02 §4 atomicity warning, 01 §7 checkbox

Goal: every P0 page, functional not polished, obeying the normative display rules, with
system tests. No JS framework; Turbo and Stimulus only.

Deliverables:

- Pages: Home; Analyze text (paste, stub proposals, edit/split/type, atomicity warnings
  inline, private-individual checkbox, submit, "create verification tasks"); Claim page
  with sections in the 06 §5 order, answer card by default, "Why?" and "Show calculation"
  disclosures, model selector, snapshot picker, collapsible trace JSON; Evidence page;
  Contribution page with signature, chain, and custody badges; Contributor page (per task
  type × domain, no aggregate prestige); Task board with "Hand this to my agent" lease
  command; Weaknesses page; Moderation log; Snapshot view; Source page with per-claim
  cards and the roll-up; Log browser.
- Display rules enforced in view helpers with unit tests: number only behind Show
  calculation and always with model and snapshot; no number for `INSUFFICIENT_EVIDENCE`
  or `NOT_APPLICABLE`; "Review checks: N of M"; `provisional` and `contested` labels;
  model-dependent notice; raw and independent counts; reason text for `NOT_APPLICABLE`;
  default model labeled as default; neutral wording and colors, no true/false coding or
  badges; reputation never on claim headlines.
- Server-custodied signing for browser users: every UI write builds an envelope, signs
  with the user's unlocked key, and goes through `POST /api/v1/contributions` internally.
  "Server-held key" badge on the contributor page.
- Search: full-text on claim text and evidence statements with filters (type, state,
  source, contributor, status).

Acceptance (07 Phase 6 #3, system tests):

1. Default claim view is the answer card and shows no probability until Show calculation
   is opened.
2. Review coverage renders as "N of M checks".
3. No number for `INSUFFICIENT_EVIDENCE`.
4. Provisional label appears for unaudited links.
5. The model selector switches traces.
6. A quarantined claim URL renders a public stub.
7. Pasting the compound sentence from 02 §4 triggers the atomicity warning and the stub
   extractor proposes the split.
8. A speech-style source view shows state counts only, never a speaker score (06 §6).

## Decision Log (2026-09-17)

- Every `06 §5` page exists, functional not polished, Turbo only, no Stimulus controllers
  needed: home, analyze text, claim, evidence, contribution, contributor, task board and
  task, weaknesses, moderation log, snapshot view (with a two-seq state comparison),
  source with per-claim cards, and the log browser. Web controllers reuse the API's
  services and presenters; the display rules live in `DisplayHelper` with unit tests.
- **The number and the trace are rendered only on request.** `06 §4` rule 1 puts the
  probability behind "Show calculation"; a closed `<details>` still ships the number in
  the HTML, and the rack_test driver reads it, so the calculation card and the trace are
  rendered only when `?calculation=1` is present. The default claim page contains no
  probability at all, which is stricter than the rule and testable without a browser.
  "Why?" stays a native `<details>` because it carries no number.
- Sign-up creates a user and registers a server-custodied key through the log
  (`Crypto::Custody.create_server_custodied`); every UI write goes through
  `Ui::Write`, which signs an ordinary envelope with the user's unlocked key and appends
  it with custody `SERVER`. Contributor and contribution pages show the server-held-key
  badge.
- Analyze text: the pasted text becomes a signed `CREATE_SOURCE` plus a full-range
  location; `Llm::Adapter.current.extract_claims` proposes claims with inline atomicity
  warnings; the user edits, splits, types, includes, and affirms each; each included
  proposal becomes the user's own `CREATE_CLAIM` carrying `source_id`, a new optional
  payload field stored as `claims.extracted_from_source_id` so the per-source card can
  list UI-extracted claims next to task-extracted ones. "Create verification tasks" makes
  an opposing search, a qualifier check, and a verification against the pasted text for
  each claim. The private-individual checkbox is unchecked by default; an unaffirmed
  claim is refused with the spec's error and nothing is logged.
- The source page shows descriptive counts by assessment state with the note that counts
  depend on extraction granularity and that there is never a score for the source or its
  author (`06 §6`); no ranking anywhere.
- Model selector and snapshot picker are plain GET forms; the default model is labelled
  "the default model, not the answer" and any other "an alternative model".
- System specs use Capybara's rack_test driver (`spec/support/system.rb`): no browser is
  installed on the build machine, and every interaction is a form or a link. Switching to
  `driven_by :selenium, using: :headless_chrome` needs no spec changes.
- Constitutional Test (visibility): 1 unchanged; 2 yes, alternative models and the
  weaknesses page are one click away; 3 no, the default model is labelled as such;
  4 no, contributor pages show audited reliability only, no followers or prestige;
  5 yes, unknown states show words and reasons, never numbers; 6 unchanged; 7 yes,
  anyone can browse the log; 8 yes, every page takes a snapshot seq; 9 yes, no personal
  views exist in P0; 10 yes, neutral wording and colours throughout.
- Acceptance: 07 Phase 6 #3 (all eight items) has system specs in `spec/system/`;
  `bundle exec rspec`, RuboCop, and Brakeman pass.
