# 0011. Toolchain: GHC 9.10, ghcup, cabal, tasty

## Status

Accepted. The brief marks this decision active, with the project owner as decider. Whether it installs on the server is untested (A03).

## Context

No Haskell tools are installed on the server today. We need a compiler, a build tool and a test framework.

## Decision

GHC 9.10.x, installed with ghcup. Built with cabal. Tested with tasty, tasty-quickcheck and tasty-hunit. This began as an agent recommendation; the owner confirmed it as written. Adding other dependencies needs the owner's approval.

## Consequences

- The first task is to install it and get `cabal build` and `cabal test` green on a hello-world.
- If ghcup fails on the server, we revisit this (for example nix or stack). That is A03.
- Validation commands become `cabal build all` and `cabal test all`.

## Brief ids

D10 (A03)
