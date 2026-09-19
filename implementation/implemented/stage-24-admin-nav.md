# Stage 24 — Admins, help, and navigation

**Status:** implemented · tag `stage-24-admin-nav` · decisions recorded 2026-09-19

## Plan

**Tag:** `stage-24-admin-nav` · **Spec:** 05 §13 (moderation), 06 §5 (UI pages),
09 §15 (who appoints moderators: open), Article XII (visible power), Article XIX
(transparency)

Goal: the website has an administrator, the first account, who can make other
accounts admins or moderators; the header is a small set of drop-down menus with
Admin visible only to admins and Help holding the FAQ, the docs, the constitution,
and an About page that says which build is running and where the code lives.

Why an admin is not a ledger role: the log already has its powers, all signed and
public: the system key, moderator keys, principals accepting proposals. Admin is
about accounts and menus, which live outside the log (`users` is not a projection),
so it is a column on `users` with who granted it and when. Moderator stays what
`Governance::Moderators` reads (`users.moderator` plus `LEDGER_MODERATOR_KEY_IDS`);
this stage gives admins the button to set it, since until now nothing but the
database could.

Deliverables:

- `users.admin`, `admin_granted_by_id`, `admin_granted_at`. `Users::Admins`:
  `create_first_or_ordinary!` (under an advisory lock, so exactly the first account
  is an admin), `grant_admin!`, `revoke_admin!` (never the last admin),
  `set_moderator!`; every one refuses a non-admin caller. `bin/rails
  admin:grant[email]` for recovery.
- `Admin::UsersController` at `/admin/users`: every account with sign-up date, key,
  admin (and who granted it), moderator, and the four buttons. `feature_requests`
  opens to admins as well as moderators.
- Navigation as a partial with `details`/`summary` drop-downs (working without
  JavaScript; a Stimulus `menu` controller closes the others, on outside click, and
  on Escape): **Check** (Record a check, Analyze text when signed in), **Browse** (Claims, Topics, Tasks, Weaknesses, Audits, Log, Moderation
  log), **Admin** for admins (Users, Feature requests, Bug reports) or **Moderate** for moderators
  who are not admins (Feature requests, Bug reports), **Help** (FAQ, Connect an assistant, Docs, Constitution, Licences, About, Report a bug).
- `HelpController`: `/docs` renders the README with a card of pointers (connect,
  OpenAPI, meta, the skill, the log, the spec, the plan); `/about` shows the revision,
  repository, issues and licence links, Ruby, Rails, and PostgreSQL versions, the
  node address and key, log head, released models, moderator keys, data licence,
  and the constitution version and hash.
- `/licenses`: the licence stack from `docs/LICENSE-POLICY.md` as a table of what is in
  force today (the `LICENSE` file for the code, `LEDGER_DATA_LICENSE` for the log) against
  what the policy recommends, the code licence in full, the SPDX canonical text of every
  licence in the stack (`LICENSES/*.txt`, downloaded from the SPDX license list), and
  the policy itself.
- Bug reports, the sibling of feature requests (owner request, 2026-09-19): `BugReport`
  outside the log with what happened, what was expected, steps, the page, the tool, and
  the last error; repeats within 30 days counted on one row. Assistants file through the
  `report_bug` tool (ten a day per assistant; the skill and every guidance block say
  when to use it against `request_feature`); people file from Help → Report a bug, signed
  in or not (five an hour per address). Admins and moderators read them at
  `/bug_reports`; `bin/rails bugs:report` summarises them.
- `Dockerfile` takes `GALEDRA_REVISION` and writes `REVISION`;
  `compose.production.yaml` passes it from the environment, so
  `GALEDRA_REVISION=$(git describe --tags --always) docker compose -f
  compose.production.yaml up -d --build` stamps the build. Development reads git.

Acceptance:

1. The first sign-up is an admin and is told so; the second is not.
2. A visitor sees Check, Browse, and Help and no Admin; an admin sees Admin; a
   non-admin is redirected from `/admin/users` and its posts change nothing.
3. An admin cannot revoke the last admin, can grant admin (recorded with the granter),
   can appoint and remove a moderator, and the appointed key appears in `meta`.
4. `/docs` renders the README and the pointers; `/about` shows the revision, the
   repository, the node key, and the constitution hash; a `REVISION` file wins over
   git.
5. Existing page specs (home, sessions, feature requests) pass with the new header.

## Decision Log (2026-09-19)

- Moderator appointment by an admin is a stopgap the owner asked for implicitly by
  asking for admins; the reserved decision ("who holds the system key and appoints
  moderators") stands. The appointment is visible (meta lists every moderator key)
  but not in the log. When the owner decides, a signed `APPOINT_MODERATOR` control
  entry can replace the flag, and `Governance::Moderators` is the one reader.
- Admin grants are not log entries for the same reason: accounts are not
  contributors. Who granted and when is kept on the row.
- Drop-downs use `details`/`summary` rather than a menu library: no dependency, works
  without JavaScript, and the existing header styles carry over. On narrow screens
  the panels render inline.
- The docs page renders `README.md` after turning GitHub code fences into kramdown's
  tildes; `kramdown-parser-gfm` was not added, since the constitution renderer already
  uses plain kramdown.
- The licences page reads the code licence from `LICENSE` and the database licence from
  the node, and shows the policy's stack. The owner adopted it the same day (Stage 23
  decision log): the page now says so rather than "recommended, not adopted". The full
  texts are SPDX's canonical files under `LICENSES/`, as the policy's layout asks.
- Constitutional Test: touches visibility of power only. 1 yes; 2 n/a; 3 no; 4 no;
  5 yes (admins and moderators are listed, moderator keys published); 6 yes; 7 yes;
  8 yes; 9 yes; 10 yes. No blocker.
