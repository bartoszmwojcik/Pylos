# 0001. Slice plan S1–S5, Now versus Later

## Status

Accepted. This is the owner's agreed direction, recorded in the brief's Scope. It is not a numbered D row.

## Context

The owner wants bots and a browser viewer. But the owner also wants to understand every part, and develops on a headless server with no Haskell toolchain yet. A fast engine and bots both need a trusted rules engine to check them against. So the order of work matters.

## Decision

We split the work into slices. Each slice can be checked on its own.

| Slice | Content | Depends on | When |
|---|---|---|---|
| Toolchain | Install GHC and cabal, get a build and test green (0011) | none | Now |
| S1 | Reference rules engine, notation, game records, QuickCheck properties, bounded playout, perft CLI, golden files | toolchain | Now |
| S2 | Bitboard engine, checked against S1 by perft and playouts | S1 | Now |
| S3 | Bots, match runner with a ply cap, stats | S1 (S2 for speed) | Later |
| S4 | Web viewer served by the backend: replay and a live game | S1 records, S3 | Later |
| S5 | Human against a bot in the browser | S4 | Later |

Why this order: the reference engine is the oracle. Every later slice trusts it, so it comes first and is kept small and readable.

Rejected alternatives:

- **Build nothing; adopt an existing engine or game framework and only write bots.** Pylos implementations are scarce and rarely in Haskell. It also defeats the learning goal.
- **Bitboard engine first.** It would have nothing to check against, so its bugs would be invisible.
- **Web viewer first.** There is nothing to show until the rules exist.

## Superseded brief rows

These brief rows are shown as superseded. Each has a replacement.

| Superseded row | Replaced by | What changed |
|---|---|---|
| R01 (standard Pylos, no "lines" variant) | R08 | Same board and ball counts, plus the row rule of R07. See 0015. |
| R02 (take-back is mandatory, 1 or 2 balls) | R07 | Take-back is optional: 0, 1 or 2 balls in total per move. |
| N01 (no lines variant, only a hook) | D14 | The row rule is built as a standard rule. See 0015. |

## Consequences

- Only the toolchain, S1 and S2 are planned in detail. S3–S5 wait for the open questions Q03 (which bots) and Q02 (web demo form).
- If S1 has a rules mistake, S2 repeats it and still passes. That is why the owner may compare the rules with the rulebook (A01).
- Each slice ends with something we can run and check.

## Brief ids

Scope (Now and Later), D04, D05, P03; superseded R01, R02, N01; replacements R07, R08, D14.
