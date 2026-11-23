# 0002. Haskell backend serves the web frontend

## Status

Accepted. The brief marks this decision active, with the project owner as decider.

## Context

The owner chose Haskell for the project. The viewer needs a web server. We could run a second server for the frontend, or let one backend do both.

## Decision

The backend is Haskell and it serves the web frontend directly. This was the owner's choice. One program means one thing to run on the server.

## Consequences

- No separate frontend server to deploy.
- The web layer and frontend technology are still open (Q02). The decision only fixes who serves the files.
- The engine stays usable without the web layer, so S1 and S2 need no server.

## Brief ids

D01 (see also D03, Q02)
