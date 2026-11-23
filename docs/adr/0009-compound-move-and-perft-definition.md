# 0009. A move is a compound value; perft counts moves

## Status

Accepted. The brief marks this decision active, with the project owner as decider.

## Context

In Pylos a player may take balls back after completing a shape. We must decide what one "move" is. That choice decides the perft numbers, which are our oracle.

## Decision

One move is a compound value: an action (`Place p` or `Raise from to`) plus a set of 0–2 take-backs (R07).

- Two moves are equal when they have the same action and the same take-back set.
- A take-back set is legal when at least one removal order is legal (R04).
- Perft counts these move values, not distinct positions.
- Sanity values from the start position: 16, 240, 3360, 43680.

Alternative rejected: each take-back as its own ply. It inflates the tree and changes the notation. This began as an agent recommendation; the owner accepted it.

## Consequences

- Both engines must produce the same move values, so perft numbers are comparable.
- Different move values can lead to the same position. Perft numbers are not position counts.
- The brief reviews this with A01: if the rules change, the golden values change.

## Brief ids

D08 (R03, R04, R07, A01)
