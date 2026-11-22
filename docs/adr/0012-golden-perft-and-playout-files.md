# 0012. Golden perft and playout files

## Status

Accepted. The brief marks this decision active, with the project owner as decider.

## Context

S2 needs a fixed target. Perft counts check which moves exist, but not how a game ends.

## Decision

S1 freezes golden files: perft values for the start position and for fixed mid-game positions, plus the outcomes of seeded random playouts. S2 must match them. This began as an agent recommendation; the owner confirmed it as written.

## Consequences

- Freezing happens before S2. The owner may compare rules with the rulebook first (A01).
- If a rule changes later, the golden files must be regenerated on purpose, and the change explained in a record.
- The playout files cover game end and outcome.

## Brief ids

D11 (D05, A01)
