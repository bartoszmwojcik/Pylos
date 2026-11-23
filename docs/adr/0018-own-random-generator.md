# 0018. The engine carries its own random number generator

## Status

Proposed. This is an implementation choice made by the agent while building E02-S04. The owner reviews it in the PR.

## Context

The golden playout file (D11) stores the outcome of a random game for each seed. If the random numbers for a seed ever changed, every stored outcome would be wrong. The golden file would have to be regenerated without any rule change, which `CODE_REVIEW.md` forbids. A library generator such as `random` may change its algorithm between versions.

## Decision

`Pylos.Reference.Random` implements SplitMix64: about 20 lines, with fixed published constants. A number from 0 to n−1 is taken as the remainder of a 64-bit draw. That is very slightly uneven, which does not matter for random play.

Rejected: the `random` package. It is one more dependency, and its output may change between versions.

## Consequences

- A seed means the same game forever, on every machine and compiler.
- Both engines use the same generator, so the bitboard engine can replay the golden seeds (see 0019).

## Brief ids

D11, D12
