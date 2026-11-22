# 0004. The demo runs in a web browser

## Status

Accepted. The brief marks this decision active, with the project owner as decider.

## Context

The owner develops on a headless server. There is no display, so a desktop window cannot show a game (P01).

## Decision

The demo runs in a web browser, served by the backend (0002).

## Consequences

- Games must be viewable over the network.
- Live play and replay both need the browser; the exact form (2D or 3D, live or replay) is open (Q02).
- Online multiplayer, accounts and public deployment stay out (N02).

## Brief ids

D03 (P01, Q02, N02)
