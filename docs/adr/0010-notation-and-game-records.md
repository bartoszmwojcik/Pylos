# 0010. Position notation and JSON game records

## Status

Accepted. The brief marks this decision active, with the project owner as decider.

## Context

Perft diffs, logs, replays and the viewer all need one text format for positions and moves.

## Decision

Positions are written `<level><row><col>`, from `a11` to `d11`. A place is `a23`. A raise is `a11-b22`. Take-backs are appended as ` x a23 a24`. Game records are JSON with the keys `rules`, `white`, `black`, `result`, `moves`, `plies`. This began as an agent recommendation; the owner confirmed it as written.

## Consequences

- A parser and printer must round-trip, and a property test checks it.
- Records are plain files. We use no database (N03).
- The same format serves perft, bots and the viewer.

## Brief ids

D09 (N03)
