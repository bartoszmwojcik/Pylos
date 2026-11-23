# 0005. Pure reference engine checked by QuickCheck

## Status

Accepted. The brief marks this decision active, with the project owner as decider.

## Context

A fast engine needs something to check it against (P03). The owner also wants to understand the rules code (P02).

## Decision

We write a readable, pure Haskell reference engine first. It does no input or output and has no performance tricks (N04). QuickCheck properties check it over positions reached by random legal play. It is the oracle for everything later.

Alternative rejected: write the bitboard engine first. It would have no oracle (see 0001).

## Consequences

- Slower code in S1 is fine. Speed is S2's job.
- A rules mistake here is copied by S2, because S2 is checked against S1. The properties and the rulebook comparison (A01) are our defence.
- Reference modules never import bitboard modules.

## Brief ids

D04 (P02, P03, N04)
