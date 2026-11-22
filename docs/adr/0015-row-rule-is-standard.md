# 0015. The row rule is part of the standard rules

## Status

Accepted. The brief marks D14 active, with the project owner as decider. The rules behind it come from the owner's memory and are not yet checked against the rulebook (A01).

## Context

The first proposal (R01, N01) left out the "lines" rule and kept only a hook for it. The owner then said, from memory, that a complete row of four balls on the bottom level counts as a shape, like a 2×2 square.

## Decision

The engine implements the row rule. A complete horizontal or vertical row of 4 of one's own colour on level a triggers the take-back (R07). Diagonals and rows on level b do not count. This is part of the standard rules, not a variant behind a hook.

Taking balls back is optional: 0, 1 or 2 balls in total per move, however many shapes the move completes (R07).

## Consequences

- There is no rules-variant switch to build.
- A move can complete several shapes at once, but still takes back at most 2 balls.
- The perft and golden values (0009, 0012) include the row rule.
- A01 compares R03, R04, R05, R07, R08 and D14 with the rulebook. If they differ, the rules change and the golden values must be regenerated.

## Superseded brief rows

| Superseded row | Replacement | What changed |
|---|---|---|
| N01: not building the "lines" variant, only a hook | D14 | The row rule is built as a standard rule. |
| R01: standard Pylos without the "lines" variant | R08 | Same geometry (30 positions on 4 levels; 15 balls each), now including the row rule. |
| R02: take-back is mandatory, 1 or 2 balls | R07 | Take-back is optional, 0–2 balls in total. |

## Brief ids

D14; supersedes N01. Related: R07 (supersedes R02), R08 (supersedes R01), A01.
