# Stage 4 — Quarantine, takedown, and the moderation log

**Status:** implemented · tag `stage-04-moderation` · decisions recorded 2026-09-17

## Plan

**Tag:** `stage-04-moderation` · **Spec:** 02 §5, 05 §13, 06 §2 (`/moderation`), 12 Art. XII–XIII, CONSTITUTION-AMENDMENTS P-1, P-2

Goal: visible moderation. Nothing disappears without a public trace, and the chain still
verifies after a legally compelled redaction.

Deliverables:

- Moderator authorization: a `moderator` flag or role on `users`/`contributors`, checked
  for the control actions `QUARANTINE`, `RELEASE_QUARANTINE`, `TAKEDOWN`, and
  `INVALIDATE` outside the audit path.
- `QUARANTINE` / `RELEASE_QUARANTINE` appliers for sources and claims: closed reason list
  (`PRIVATE_INDIVIDUAL`, `PERSONAL_DATA`, `UNLAWFUL_CONTENT`, `UNLICENSED_MATERIAL`,
  `SPAM`), `status: QUARANTINED` on claims, text withheld from public reads, public stub
  at the same URL with moderator key, date, reason, appeal path.
- `TAKEDOWN` applier with a redaction manifest: physically deletes `payload`, `envelope`,
  and blob bytes of the target, sets `redacted_by_seq`, keeps `payload_hash`,
  `envelope_hash`, `entry_hash`, `server_signature`. Applies the manifest to projection
  rows (fields nulled).
- `ledger:verify` reports `CHAIN_VERIFIED` or `CHAIN_VERIFIED_WITH_REDACTIONS` with the
  redacted seqs; `ledger:replay` applies redacted entries from their manifests.
- `Governance::ModerationLog` and `GET /api/v1/moderation`: every quarantine, release,
  takedown, suspension, and revocation with moderator key, reason category, and appeal
  status.
- Private-individual affirmation: `CREATE_CLAIM` payload carries
  `affirms_not_private_individual: true`; missing or false is a validation error.

Acceptance:

1. After a `TAKEDOWN`, `ledger:verify` reports `CHAIN_VERIFIED_WITH_REDACTIONS` naming the
   seq, and replay reproduces the redacted projection (07 Phase 2 #8).
2. A quarantined claim URL returns a public stub, not a 404, and the claim's text is
   absent from every public read (07 Phase 6 #3, API part).
3. The moderation log lists each action with its moderator key and reason category.
4. A quarantine with a reason outside the closed list is rejected.
5. Constitutional Test answers recorded in the Decision Log for this stage.

## Decision Log (2026-09-17)

- **Moderators are designated outside the log**: key ids in `LEDGER_MODERATOR_KEY_IDS`,
  or a `users.moderator` flag whose server-custodied key then counts. `09 §15` leaves
  appointment open, and inventing an `APPOINT_MODERATOR` action would extend the closed
  list in `02 §3.6`. The current list is published by `/api/v1/meta` and `/api/v1/moderation`
  so the power is visible. The system key is never a moderator. Moderators may
  `QUARANTINE`, `RELEASE_QUARANTINE`, `TAKEDOWN`, `INVALIDATE` any epistemic contribution,
  and `REVOKE_KEY` (suspension) any non-system key.
- Quarantines are a windowed projection (`quarantines`: target, reason from the closed
  list of `05 §13`, `created_seq`, `released_seq`). `claims.status` shows `QUARANTINED`
  while one is live; `status_at(seq)` answers history. Withheld while live: the claim's
  text and qualifiers; a source's title, content, and metadata; its locations' excerpts
  and locators; its evidence items' statements; and the payload and envelope of the
  contributions that carry that text in `GET /log` and `GET /contributions/:id`
  (hashes stay, plus a `withheld` marker). Quarantined claims are also dropped from
  lists, search, and duplicate suggestions. The public stub at the same URL carries the
  quarantine seq and time, moderator key id, reason, appeal status, and appeal path.
  Old snapshots of a quarantined claim also show the stub: the point is not to serve
  the text, though the claim's existence and status history remain visible.
- **TAKEDOWN carries the redaction manifest in its signed payload**: for every projection
  row of the target, the fields removed and the retained (non-sensitive) values. The
  server validates that the manifest covers exactly the target's rows, removes only
  redactable fields (`Ledger::Redaction::REDACTABLE`), and matches the current row
  values; `GET /contributions/:id/redaction_manifest` produces the default manifest
  for the moderator to review and sign. On append the fields are nulled (jsonb NOT NULL
  columns get `{}`), `redacted_by_seq` is stamped, and the target's payload and envelope
  are deleted under the owner role (`Ledger::DatabaseRole.as_owner`), since the
  application role cannot update those columns. Hashes, entry hash, and server
  signature remain, so `ledger:verify` reports `CHAIN_VERIFIED_WITH_REDACTIONS` with
  the seqs, checks that every redacted entry points at a `TAKEDOWN` that names it, and
  breaks on bytes removed any other way. Replay rebuilds redacted rows from the
  manifest. Only epistemic contributions can be taken down; a control entry such as
  `REGISTER_KEY` carries key material the chain needs.
- Deployment note: in direct-role mode (`LEDGER_DB_APP_ROLE=false`) the connection
  cannot escalate, so takedowns must run through a connection with owner rights.
- The private-individual affirmation (`01 §7`) is `affirms_not_private_individual: true`
  on `CREATE_CLAIM` and `SUPERSEDE_CLAIM` payloads; missing or false is rejected.
- `Governance::ModerationLog` is a view over the log: every quarantine, release, and
  takedown, plus key and delegation revocations signed by a moderator (labelled
  `SUSPENSION`). Appeal status is `OPEN` or `RELEASED` for quarantines and `NONE` for
  takedowns; the `RE_AUDIT` appeal path arrives in Stage 7.
- Constitutional Test (moderation, visibility, history): 1 unchanged; 2 unchanged;
  3 moderation power exists but every use is a signed, logged, publicly listed
  contribution with a closed reason list, and the moderator list is published; 4 no;
  5 n/a; 6 yes, redacted logs still verify and replay; 7 yes, releases and later
  re-audits are the same contribution path; 8 yes, stubs and the moderation log keep
  the history of removals; 9 n/a; 10 the residual risk named in `13` (moderation power)
  stands, mitigated by visibility and appeal, not eliminated.
- Acceptance: the five Stage 4 items have specs in `spec/services/governance/`;
  `bundle exec rspec`, RuboCop, and Brakeman pass.
