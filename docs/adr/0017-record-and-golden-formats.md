# 0017. A version field in game records, and one JSON value per line in golden files

## Status

Proposed. This is an implementation choice made by the agent while building E02-S03 and E02-S04. The owner reviews it in the PR.

## Context

D09 lists the fields of a game record: `rules`, `white`, `black`, `result`, `moves`, `plies`. `BACKWARD_COMPATIBILITY.md` says a breaking change to the record format needs "a version field bump", but D09 has no version field. D11 asks for golden files but does not fix their format.

## Decision

- A game record also has `"version": 1`. All six D09 fields are kept as they are. `result` is `"white"` or `"black"` (the winner), `"capped"` (stopped by a ply bound), or `null` (unfinished). `rules` names the rule set: `"pylos-owner-2026-11-22"`.
- The golden files are JSON arrays with one entry per line:
  - `golden/perft.json`: `{"name", "moves", "perft"}`, where `moves` reaches the position from the start in D09 notation and `perft[d-1]` is perft at depth d.
  - `golden/playouts.json`: `{"seed", "bound", "result", "plies"}` for seeds 1–200 with a bound of 300 plies.

One entry per line makes a regeneration show up as a readable `git diff`.

## Consequences

- The record format can change later by bumping `version`, as `BACKWARD_COMPATIBILITY.md` requires.
- The golden playouts store the outcome and length, not the moves. That is enough to detect a difference. To see *where* two engines differ, use `pylos-bit compare`.

## Brief ids

D09, D11
