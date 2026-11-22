# 0014. Decision records and Haddock rule citations

## Status

Accepted. The brief marks this decision active, with the project owner as decider. Whether it works for the owner is untested (A02).

## Context

The owner wants to learn why the code is the way it is (P02). Comments rot, and the reasons behind a choice are easy to lose.

## Decision

Every decision gets a record in `docs/adr/`, using the template (0000). Every rule function's Haddock comment cites the rule id it implements (for example R03). Literate Haskell was the alternative; the owner accepted the agent's recommendation of records plus Haddock.

## Consequences

- Each non-obvious choice costs a short record.
- A `proposal` in the brief is never recorded as accepted.
- A02 tests this: the owner reads 0001 and the first rules module and reports what was unclear.
- Numbers 0016 and above are for implementation decisions.

## Brief ids

D13 (P02, A02, D06)
