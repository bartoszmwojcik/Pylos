# 0020. The bitboard representation

## Status

Proposed. This is an implementation choice made by the agent while building E03-S01. The owner reviews it in the PR.

## Context

The board has 30 squares (R08), so it fits in a 32-bit word. The rules ask a few questions over and over: is this square supported, is this ball free, does this ball complete a shape. The reference engine answers them by walking lists and maps, which is clear but slow (N04).

## Decision

- Square → bit: level a uses bits 0–15 (row by row), level b 16–24, level c 25–28, level d 29.
- A position is one `Word32` mask per colour, the two reserves, and whose turn it is.
- Tables are computed once, *from the reference geometry*: the support mask of each square, the mask of squares resting on it, the squares on higher levels, and the masks of the shapes through it.
- Then "supported" is `support .&. occupied == support`, "free" is `above .&. occupied == 0`, and "completes a shape" is `shape .&. own == shape` for each shape through the square.
- Take-back pairs come from two sources: two balls that are both free now, or a free ball x plus a ball y that is free once x is gone (R04). The two sources cannot overlap, so no deduplication is needed. A mask is a set, so the order of removal never creates a duplicate (D08).
- Perft counts the last level by the length of the move list, without playing those moves ("bulk counting").

Rejected: one `Word64` with both colours, which is harder to read for no gain. Rejected: mutable arrays or unboxed move lists. They would be faster again, but harder to read, and the current speed-up is already large (`pylos-bit bench`).

## Consequences

- On this server, `pylos-bit bench 6` measured about 9.4 million nodes per second for the bitboard engine and 0.49 million for the reference engine, a speed-up of about 19×.
- The tables reuse the reference geometry. A geometry bug would be shared by both engines, but the geometry is checked on its own by the E02-S01 tests.

## Brief ids

D05, R03, R04, R07, R08, N04
