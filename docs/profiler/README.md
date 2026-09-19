# Profiler log

One file per profiling run, named `YYYY-MM-DD-<what-was-profiled>.md`, newest at the
bottom of the index below. A run is worth a file when it changed what we believe, not
every time a task is executed.

The point of keeping these is comparison. A timing on its own says almost nothing: 2.8
seconds is either fine or a disaster depending on the corpus it was measured against and
the machine it ran on. A timing next to the one taken before the change, at a stated
corpus size, is evidence. So every entry records the conditions as carefully as the
numbers, and an entry that cannot say what it was measured against is not worth writing.

## What an entry records

- **Conditions.** Corpus size in claims and contributions, environment, machine, and what
  was held still. Without these the numbers cannot be compared to anything.
- **Numbers.** What was measured, with the units, in a table.
- **Findings.** What the numbers mean, in plain words, including the ones that turned out
  to be nothing. A profile that rules something out is worth recording; it stops the next
  person from chasing it.
- **What changed as a result**, or what was decided not to change, and why.

**Every finding carries a status, and the status is updated in place when it changes.**
One of `FIXED`, `PARTLY FIXED`, `OPEN`, `WON'T FIX` or `NO ACTION NEEDED`, on the finding
itself, with what fixed it. A log whose entries still read as open after the work is done
is worse than no log: it sends the next reader chasing something that is already gone, and
it hides the ones that are genuinely still there. Fixing a finding and leaving the entry
alone is half the job.

## How a run is taken

```bash
bin/rails bench:workloads                 # what can be profiled
bin/rails 'bench:cpu[weaknesses]'         # sampling profile; MODE=cpu, RUNS=n
bin/rails 'bench:memory[weaknesses]'      # what one run allocates and retains
bin/rails 'bench:rss[claims/:id]' RUNS=300 # does the process grow as it serves
bin/rails bench:boot                      # what it holds having served nothing
bin/rails bench:report                    # time every workload
```

Every one of them runs inside `Bench::Isolation`, which holds the reloader, verbose query
logs and log writes still, because none of those exists in production and in the first
profile they were a fifth of the samples. Profiling also swaps the page cache for a null
store, so a page that caches its own answer is measured doing the work.

The gems live in the development bundle group only, so the production image never carries
them. See `implementation/planned/stage-26-capacity.md` for the plan this serves.

## Index

| Date | Entry | The one thing it found |
|---|---|---|
| 2026-09-19 | [The weaknesses page at 3,000 claims](2026-09-19-weaknesses-at-3000-claims.md) | The score cache was queried once per claim per model. Carries a same-day correction, and a follow-up measuring what the cold path costs |
