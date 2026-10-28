# ADR-006: Tests prove each promise at one layer, and every test takes the SQLite write lock

## Status
Accepted

## Date
2026-08-04

## Context
SQLite takes one writer. Browser tests through Playwright run against the real
server and the real database. A suite that proves the same promise at the
unit, the LiveView and the browser layer costs minutes and fails three times
for one defect.

## Decision
Every test takes the SQLite write lock at its start, and the browser case is
not `async`: SQLite serializes writers, and two tests writing at once would
block each other at random moments.

Each promise is proved at one layer. Business logic is a unit test under
`test/texttile`. A controller or LiveView test proves what the page says.
A browser test under `test/e2e` is kept only where a browser is the point:
the tile queue, the clipboard, the confirm dialog, the file picker, the
keyboard, the transport. Browser tests enter screens through
`TexttileWeb.E2E` and wait for the live page and the gallery's `data-ready`
before they act. A test that creates state outside the transaction (locks,
presence, application environment, uploads) clears it, through the shared
cleanup in `test/support/data_case.ex`.

Timing that a test must wait through is read from one place, so a test may
shorten it (`window.__lineTiming`) while production keeps its numbers.

## Alternatives Considered

### Test every promise at every layer
- Cons: 44 seconds of real waiting in five transport tests alone, and three
  failures per defect
- Rejected in #62: the upper copies were removed, and what only they said
  moved down

### Async tests with a database per test
- Rejected: one SQLite file has one writer; a sandbox per test does not change
  that

## Consequences
- `mix test --max-cases 4` is the run before a pull request. `make check`
  runs what CI runs, in CI's order.
- A failure that only happens in CI is treated as an ordering or timing race
  until disproved: reproduce with `--seed 0` and under CPU load.
- A green test is not the end. The change is used in a real browser before it
  is called done.

## Sources
- 042a440 "Take the SQLite write lock at the start of every test"
- #1 "Drop async from the e2e case: SQLite serializes writers"
- #27 "Browser tests wait for the live page before they act"
- #62 "Slim the test suite: one layer per promise, and a faster clock for the transport tests"
