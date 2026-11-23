# 0021. Library dependencies

## Status

Proposed. `AGENTS.md` says to ask before adding dependencies. These were added by the agent to build E01–E03, and the owner reviews them in the PR.

## Context

D10 fixes the toolchain (GHC 9.10, cabal, tasty, tasty-quickcheck, tasty-hunit). D09 asks for JSON game records. Everything else was open.

## Decision

- Engine (`pylos`): `base`, `containers` (maps and sets), `text` and `bytestring`, which ship with GHC, plus `aeson` for JSON. `aeson` is the standard Haskell JSON library. Writing JSON by hand would be more code to read and to get wrong.
- Bitboard engine: `array` (ships with GHC) for the lookup tables.
- Tests: `tasty`, `tasty-quickcheck`, `tasty-hunit` and `QuickCheck` (D10), plus `directory` and `filepath` (ship with GHC) for the test that scans `reference/` for imports.

Rejected: `random`, see 0018. Rejected: `optparse-applicative` for the command lines. The commands are few enough to match by hand.

## Consequences

- The first `cabal build` downloads and builds about 30 packages, mostly for `aeson`.
- Version bounds in `pylos.cabal` keep a future `cabal update` from silently changing the build.

## Brief ids

D09, D10
