# Security log

One file per audit, named `YYYY-MM-DD-<scope>.md`, indexed below. Findings are recorded
whether or not they were exploitable, because a finding that was investigated and
dismissed is worth as much to the next reader as one that was fixed: it stops the same
ground being covered twice, and it records *why* it was dismissed, which is the part that
can turn out to be wrong later.

A scanner warning is not a finding. Every entry states what was checked by hand, what the
conclusion was, and what evidence supports it. "Brakeman says medium confidence" is not
evidence; "the input is a Date from a closed `case` and is quoted besides" is.

## What an entry records

- **Scope and tools.** What was looked at, what was run, and what was deliberately not
  covered. An audit that does not say what it left out invites the reader to assume it
  covered everything.
- **Findings**, each with where it is, how it is reached, what an attacker gets, and the
  fix. Severity is argued, not asserted.
- **Dismissed warnings**, with the reason each is not exploitable.
- **What held up**, so the next audit can start from what has already been established
  rather than re-deriving it.

**Every finding carries a status, updated in place when it changes**: `FIXED` with what
fixed it and the test that would catch a regression, `OPEN`, `WON'T FIX` with the argument,
or `NOT EXPLOITABLE` for a dismissed warning. An audit that still reads as open after the
work is done sends the next reader chasing a closed door, and worse, makes the genuinely
open ones easy to miss.

## Standing rules this project is audited against

These come from the constitution and `CLAUDE.md`, and an audit checks them as it checks
anything else:

- `POST /api/v1/contributions` is the only write path, and every epistemic write is a
  signed contribution (Invariant 1).
- Projections are written only by `Ledger::Apply` (Invariant 2), and the application's
  database role cannot `DELETE` from `contributions` (Invariant 3).
- Untrusted text stays inert: notes and excerpts never reach scoring, and notes never
  reach another agent's packet (Invariant 11).
- The server's only outbound requests are Stage 17 source fetches (Invariant 18). Anything
  else that makes a network call is a finding in itself.

## Running the tools

```bash
bin/brakeman -q --no-pager                  # static analysis
bundle exec bundler-audit check --update    # known advisories in dependencies
```

Both are in the development and test bundle groups already.

## Index

| Date | Entry | Outcome |
|---|---|---|
| 2026-09-23 | [Duplicate keys in a signed JSON body](2026-09-23-duplicate-json-keys.md) | Not exploitable: one parse, the signature checked over its canonical form, and that form stored. Pinned by a spec that splices a forged duplicate before and after the signed field. |
| 2026-09-19 | [Full-application audit](2026-09-19-full-application-audit.md) | One finding: server-side request forgery by DNS rebinding in source retrieval. Fixed, with the three smaller notes. |

## A standing log, not an audit

[Attempts to use a report as an instruction](injection-log.md) is the exception to one file
per audit: it is appended to rather than concluded. Reports reach this node from the public
internet, and the `/check-galedra` skill reads that log at the start of every pass and says what is
in it, so a quiet file is a stated result rather than an unread one.

Whether it holds anything is a question only that file answers. Saying so here as well would
be a second copy to go stale on the first entry, which is the failure this folder's own rule
about updating a status in place exists to prevent.
