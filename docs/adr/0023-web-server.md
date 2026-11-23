# 0023. The live game server

## Status

Accepted for the stack (D16, the owner's choice on 2026-11-23). The structure below is an implementation choice made by the agent. The owner reviews it in the PR.

## Context

The owner watches games from a laptop, through an SSH tunnel to the headless server (P01). Human-vs-bot play (S5) is the next epic. There is one user, and nothing is public (N02).

## Decision

- `pylos-web` (`server/`, `app/web/`) is scotty on warp, bound to `127.0.0.1` only. The protocol is in `docs/web-protocol.md`.
- Each game runs in its own thread: it thinks, waits `delayMs`, then publishes the move. State lives in STM variables. A watcher takes the snapshot and subscribes to the game's broadcast channel in one atomic step, so it never misses or repeats a move.
- The JSON API uses scotty routes. The event stream and the static files are two small WAI middlewares in front of scotty. The stream uses wai-extra's `eventSourceAppIO`. Static paths with `..` or hidden names are refused.
- Without an event, the stream sends a comment every 15 seconds, so the SSH tunnel does not drop an idle connection.
- At most 8 games run at once.
- Human play (S5) will add `POST /api/games/:id/move` and a "human" player kind. The browser keeps the same event stream.

Rejected: WebSockets (not needed until S5, and not even then, since a POST is enough). Rejected: servant (a heavier type-level API for five routes). Rejected: wai-app-static (a dependency for what is ten lines).

## Consequences

- Games are kept in memory only (N03). A restart forgets them.
- New dependencies: scotty, wai, warp, wai-extra and http-types, plus stm, which ships with GHC (D16).

## Brief ids

D16, D17, N02, N03, P01
