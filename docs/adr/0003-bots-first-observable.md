# 0003. Bots first, and bot games must be observable

## Status

Accepted. The brief marks this decision active, with the project owner as decider.

## Context

The owner's main goal is game-playing bots. Bots are only useful if the owner can watch them play.

## Decision

Bots come first among the products. Bot-vs-bot games must be observable. Bots themselves are Later work (S3), after the engines.

## Consequences

- The engine needs a fast mode and a way to record games, so bots can play many games.
- The game record format (0010) must be good enough for replay.
- Which bots to build, and how to judge them, is open (Q03).

## Brief ids

D02 (see also Q03)
