# What a connection left hanging, told to it unprompted

**Built 2026-09-22** · `Assistants::Waiting`, carried on every MCP result beside `guidance`.

## Why

One ChatGPT session filed a bug report. A later session from the same account had no idea it
existed, so it could neither read the answer nor say whether it settled anything. The owner
watched both halves happen within an hour and asked the obvious question: can the node tell
it is the same model and user, and tell it what is left hanging?

It could always tell. Every MCP call carries an `AssistantToken`, and
`AssistantToken#filer_token_ids` has followed a named token to its principal since the
register was built, so a reconnection already finds its own filings — `list_reports` uses
exactly that. What was missing is that **nothing said so unless asked**, and a fresh session
does not know to ask.

`docs/CONTEXT.md` carries the maintainer's half of the same fault: an assistant filed
fourteen reports in a day, could not read a single answer, and kept filing the same ground.

## What it says

`waiting_on_you` rides on every result, and only when it has something to say. Three states,
because they are three different obligations:

- **answered** — a maintainer replied and it is the filer's turn. Said out loud because an
  answer nobody comes back on settles itself after `Triageable::UNANSWERED_AFTER`, which is
  right when the filer agrees and wrong when it does not.
- **held** — work was agreed and is not done. Nothing is wanted from the filer; it is here so
  a later session can see where it stands rather than filing it again.
- **open** — a count, not a list. The useful thing to know is "you have already told them".

Anonymous connections stay scoped to their own token, because an anonymous principal is not a
stable identity and treating it as one would show one filer somebody else's reports.

## What happened next

It went live mid-session, with no restart, because development reloads per request. At
**00:07:00** — roughly ninety seconds later — the assistant returned to the routing bug it had
filed 65 minutes earlier, in a session that no longer existed, and closed it:

> The next fresh request linked the same Galedra section. I discovered and used Galedra MCP
> directly without opening a browser session. The pre-call tool descriptions were visible and
> the updated guidance arrived in the first result. This observed retry settles my reported
> routing problem.

`satisfied: true`, `settles: true`, CLOSED by the filer. **Whether the notice caused it is
not proven** — the reasoning is not visible from this side, and it may have gone back on its
own. The sequence fits, and it is the behaviour this was built to produce.

## What remains

- **Threads are not included.** A determination thread waiting on this principal's vote is
  also something left hanging, and three have sat at one vote each since 01:46. The same
  mechanism would carry them; it was left out of the first version because "your turn" is
  clearer for a report than for a thread nobody has asked you to join.
- **It costs two statements on every call.** Both are on an indexed column and return
  nothing in the ordinary case, but it is a cost paid by every tool call to serve a rare
  message. If it ever shows up in `request_samples`, cache it per token for the length of a
  session.
- **Nothing tells the maintainer the reverse.** The filer now learns when we answer; we still
  learn that a report was answered only by looking.
