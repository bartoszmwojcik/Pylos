# 0007. Code and reasons must be understandable

## Status

Accepted. The brief marks this decision active, with the project owner as decider.

## Context

The owner is learning. A working engine they cannot follow does not meet the goal (P02).

## Decision

Understandability is a requirement, not a bonus. We prefer plain code, short modules and explained decisions. When speed and clarity conflict, clarity wins in the reference engine. 0014 says how we record the reasons.

## Consequences

- Every task includes explanation.
- Whether it works for the owner is untested (A02). The owner reads ADR 0001 and the first rules module and says what was unclear.
- Less clever code may mean more lines.

## Brief ids

D06 (P02, A02, N04)
