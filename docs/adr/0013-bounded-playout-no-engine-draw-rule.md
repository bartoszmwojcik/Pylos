# 0013. Bounded playout; no draw rule in the engine

## Status

Accepted. The brief marks this decision active, with the project owner as decider.

## Context

Taking balls back can make positions repeat, so a game may never end. A draw rule in the engine would need repetition tracking. The owner accepted the agent's recommendation to avoid that.

## Decision

The engine has no draw rule (R06). S1 provides a bounded random playout that returns an outcome or `Capped`. The draw-by-ply-cap policy lives in the S3 match runner.

## Consequences

- The engine stays simple and pure.
- Every playout ends, with a result or `Capped`.
- The cap value is not yet chosen. Playout length is checked in S1 (A04).
- R06 is reviewed before S3.

## Brief ids

D12 (R06, A04)
