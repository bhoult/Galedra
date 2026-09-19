# Full-application audit

**Date:** 2026-09-19 · **Scope:** the whole application at commit `0935591` · **Asked for:** injection, and whatever else turned up

## Tools and method

| | |
|---|---|
| Static analysis | Brakeman 8.0.6: 57 controllers, 49 models, 59 templates. 5 warnings |
| Dependencies | bundler-audit against 1,245 advisories. No vulnerabilities |
| By hand | Every raw SQL site, every dynamic dispatch, the outbound fetcher, OAuth, token handling, authorization, output escaping, mass assignment, redirects, session and forgery configuration |

Not covered, and worth a later pass: the deployed configuration (TLS, firewall, database
grants as actually applied rather than as written), the assistant skill's prompt-injection
surface, denial of service by expensive queries, and anything about the host.

## Finding: server-side request forgery by DNS rebinding · **FIXED**

**Where:** `app/services/sources/retrieve.rb`, in `Fetcher#get`.

**What it was.** The host was resolved and every returned address checked against private,
loopback, link-local and metadata ranges. The addresses were then discarded, and the
connection was opened with `Net::HTTP.new(uri.host, uri.port)`, which resolves the name a
second time. Nothing bound the address that was checked to the address that was used.

A name under an attacker's control, with a short time-to-live, answers with a public
address for the check and a private one for the connection. The per-host throttle sits
between the two and can sleep for a full minute, so the window is wide rather than a race
that has to be won on the first attempt.

**How it is reached.** No privilege at all. `Ledger::Appliers::CreateSource` enqueues
`RetrieveSourceJob` for any source held by reference, retrieval defaults to on outside the
test environment, and an anonymous assistant token is enough to record a source. A source
whose `canonical_uri` points at an attacker-controlled name is enough.

**What an attacker gets.** Less than a full read, because page text is never stored. What
is recorded is the content hash, the byte length, the media type, the final URL, and, for
each quoted passage on the source, whether it was found verbatim, found normalised, or not
found. That last one is an oracle: an attacker records a source whose "excerpts" are
guesses at the content of an internal endpoint, and the ledger tells them, in public,
which guesses were right. Against a cloud metadata service that is an exfiltration
channel, one guess at a time, and the content hash confirms a complete guess outright.

**Severity.** High. Unauthenticated, automatic, and against the one component that by
design makes outbound requests. Bounded only by the shape of the oracle.

**The fix.** Keep the address that passed the check and connect to that one.
`Net::HTTP#ipaddr=` opens the socket to a given address while leaving `address` as the
hostname, which is what Ruby uses for the `Host` header, for the SNI extension and for
certificate verification. So the pin costs nothing: the request is indistinguishable from
before to an honest server, and a rebinding answer is never consulted. The check already
ran once per redirect, so each hop is pinned to its own checked address. The `robots.txt`
request, which shares the host, is pinned to the same address, so it cannot be the way in
either.

**Test.** `spec/services/sources/retrieve_spec.rb`, "connects to the address it checked".
A resolver answers `93.184.216.34` the first time and `169.254.169.254` after, and the
test asserts the socket goes to the first while the hostname survives for verification.
It was run against the unfixed code and fails there, reporting `connects_to: nil`.

## Warnings dismissed · **NOT EXPLOITABLE**

Brakeman raised five. None is exploitable. Each was read at the source rather than taken
on its confidence rating.

| Site | Why it is not injectable |
|---|---|
| `affiliations/resolve.rb:44` | The user's text goes through `normalize`, which strips it to `[a-z0-9 ]` and so cannot carry a quote at all, and is passed through `connection.quote` besides. The `VALUES` list is built from `config/affiliations.yml`, quoted the same way |
| `contributors/tally.rb:76` | `since` is a `Date` from a closed `case` in `ClaimReference.since_for`, never user text; `principal_ids` are internal UUIDs. Both are quoted |
| `users/admins.rb:18` | `lock_key` is `Zlib.crc32("users.first_admin")`, a constant integer |
| `lib/bench/report.rb:50` | Table names are literals at the call site, and the file refuses to run outside development and test. Not reachable from a request |
| `contributors/show.html.erb:10` (cross-site scripting) | The URL is validated at append by `Contributor.home_url?`: `URI::HTTP` only, no query, fragment or user info, 200 characters. A `javascript:` value cannot be stored. The fallback is this node's own configured URL |

## What held up

Established by reading, so the next audit need not re-derive it.

- **Injection.** Every raw SQL site in `app/` either interpolates a constant
  (`ADVISORY_LOCK_KEY`, `SET ROLE`, the projection table list in `Ledger::Replay`) or
  passes values through `connection.quote`. No query method takes interpolated user input.
  `params[:sort]` is compared to a literal and never reaches a query.
- **Dynamic dispatch.** `Weaknesses::Report` calls `send(k, ...)`, and `k` is checked
  against the frozen `KINDS` list before the call, raising on anything else. That is the
  only user-influenced dispatch in the application.
- **The API has no cookie surface.** `Api::V1::BaseController` is `ActionController::API`,
  so there is no session and no cookie to forge across; authentication is a bearer token
  only. `snapshot_seq` is range-checked against the log head and `limit` is clamped.
- **OAuth.** PKCE is mandatory and `S256` only, with `plain` refused. Authorization codes
  live ten minutes and are single-use; refresh tokens rotate and are single-use. Redirect
  URIs match exactly, with the RFC 8252 loopback exception narrowed to scheme, host and
  path, and registration is restricted to https or loopback. Client secrets and code
  challenges are compared with `ActiveSupport::SecurityUtils.secure_compare`.
- **Tokens.** Assistant tokens are 32 bytes from `SecureRandom` and stored only as a
  SHA-256 digest; lookup is by digest, so the secret is never compared byte by byte.
- **Authorization.** All three admin controllers declare `before_action :require_admin`,
  which requires an authenticated session and the `admin` flag. The last admin cannot be
  revoked.
- **Output.** Four `html_safe` sites: two render repo-controlled markdown, one joins values
  already escaped by `content_tag`, and the SVG badge builds from a frozen table of labels,
  colours and glyphs with `GLYPHS.fetch` raising on anything unknown. `Cards::Image`
  escapes with `CGI.escapeHTML` before embedding text in SVG.
- **Mass assignment.** None. No `permit!`, no `create(params[...])`.
- **Redirects.** The post-login return path is set from the application's own
  `request.url` and held in the session, so it cannot be steered to another host. The
  OAuth redirects pass `allow_other_host: true`, which is required there, and their targets
  are checked against the client's registered URIs first.

## Smaller notes · **FIXED**

All three were addressed the same day. None was exploitable; each was a habit worth not
keeping.

- `Claims::Duplicates` interpolated `connection.quote(text)` rather than binding. It now
  binds the parameter in the `where`, and builds the `select` fragment through
  `sanitize_sql_array`, which `select` needs because it takes no binds. Brakeman's SQL
  warnings drop from four to three as a result.
- `lib/bench/report.rb` interpolated a table name. It now takes one from a closed list and
  quotes it as an identifier.
- The retrieval throttle slept the whole minute however recently the host had been fetched,
  holding a worker for time it did not need to wait. It now waits only the remainder. That
  was availability rather than security, but it is the same file as the finding above and
  was fixed with it.

## Re-scan after the fixes

Brakeman: 3 SQL warnings and 1 cross-site scripting warning, all previously dismissed with
reasons above. bundler-audit: no vulnerabilities.
