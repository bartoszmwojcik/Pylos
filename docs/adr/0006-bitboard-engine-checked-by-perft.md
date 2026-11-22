# 0006. Bitboard engine checked against the reference by perft

## Status

Accepted. The brief marks this decision active, with the project owner as decider.

## Context

Bots need a fast engine. A fast engine is easy to get subtly wrong.

## Decision

S2 builds an optimised bitboard engine. We check it against the reference engine with perft counts (the number of move sequences of a given depth). The golden files in 0012 hold the expected values.

## Consequences

- Any difference in a perft count points to a bug in one engine.
- Perft only shows the two engines agree. It does not show they follow the official rules (A01).
- Perft does not check how games end, so seeded playouts are compared too (0012).

## Brief ids

D05 (P03, D11)
