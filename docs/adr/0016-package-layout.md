# 0016. Two libraries: the reference engine cannot import the bitboard engine

## Status

Proposed. This is an implementation choice made by the agent while building E02 and E03. The owner reviews it in the PR.

## Context

The reference engine is the oracle for the bitboard engine (D05, P03). If reference code ever used bitboard code, a bitboard bug could leak into the oracle, and both engines would agree on the same wrong answer. `CODE_REVIEW.md` lists a broken oracle independence as a blocker. Issue #11 asks for proof that the reference modules do not import the bitboard modules.

## Decision

One cabal package, `pylos`, with two libraries:

- the main library (`reference/`) holds the reference engine;
- an internal library `bitboard` (`bitboard/`) holds the bitboard engine and the engine comparison. It depends on the main library.

Cabal does not allow cycles between libraries, so the reference engine **cannot** import the bitboard engine: the build would fail. A test also scans `reference/` for such imports, so the rule is visible in the test report too.

Rejected: one library with a naming convention only. Nothing would stop an accidental import. Rejected: two separate packages. That is more files and versions to keep in step, for no extra safety.

## Consequences

- The independence is enforced by the compiler, not by review.
- The bitboard engine may reuse reference code that is not about speed: the board geometry (to build its tables), the move type (to convert moves) and the random generator (so both engines play the same seeded games).
- The executables and tests depend on `pylos:bitboard` explicitly.

## Brief ids

D04, D05, P03, N04
