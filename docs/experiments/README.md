# Experiments

One file per run of the system against something real, named
`YYYY-MM-DD-<subject>.md`.

An experiment is not a test and not a profiling run. A test says the code does
what it was written to do. A profiling run says how fast. An experiment asks
whether a **person and an assistant, given the real thing, actually end up with
what the design intended** — and that question is answered only by watching it
happen, because the interesting failures are ones no spec predicted.

Every file records, in this order:

1. **What was tried**, precisely enough to repeat: the input, who ran it, what
   was installed and at which commit.
2. **What happened**, in numbers taken from the database rather than from
   anybody's report of it.
3. **What it found.** Each finding carries a status the way `docs/security/` and
   `docs/profiler/` do — FIXED, OPEN, WON'T FIX, NO ACTION NEEDED — and is
   updated in place when it changes, or the log misleads the next reader.
4. **What was wrong in the watching**, if anything. An observer who misreads the
   run is part of what the run revealed.

Findings that belong somewhere else go there instead and are linked from here: a
timing to `docs/profiler/`, a vulnerability to `docs/security/`, a design change
to a stage file under `implementation/`.

The rule the folder exists to serve: **a claim about how Galedra behaves with
real input is worth what the run behind it is worth.** An experiment nobody can
repeat is an anecdote, and this project is about the difference.

## Runs

- [2026-09-19 — A connected assistant outlines a two-hour transcript](2026-09-19-live-connector-outline.md) — the size rule, Stage 30 readings, and four bugs found by watching
