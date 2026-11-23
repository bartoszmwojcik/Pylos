# 0019. A playout picks its random move from the sorted move list

## Status

Proposed. This is an implementation choice made by the agent while building E02-S04 and E03-S02. The owner reviews it in the PR.

## Context

Issue #12 asks the bitboard engine to replay every golden seed and get the same outcome. A playout picks "move number i" from the legal moves. The two engines list their moves in different orders, so the same i would mean different moves.

## Decision

Before picking, a playout sorts the legal moves in the canonical order of the reference `Move` type: action first (placements before raises, by square), then the take-back set. The bitboard engine converts its moves to reference moves and sorts them the same way.

## Consequences

- The outcome of a seeded playout depends only on the set of legal moves and the seed, not on how an engine happens to generate them.
- Sorting costs time in every playout. That is acceptable: playouts are for checking, not for speed. A fast bot does not need this ordering.

## Brief ids

D05, D11, D12
