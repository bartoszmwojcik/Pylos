# AGENTS.md

## Project overview

Pylos is a personal learning project: an implementation of the Pylos board game.

- **Backend:** Haskell. It also serves a web frontend.
- **Build order:**
  1. A readable, pure reference rules engine, checked by QuickCheck properties.
  2. An optimised bitboard engine, checked against the reference by perft counts.
  3. Bots, plus a browser viewer for watching bot-vs-bot games. Development happens on a headless server.
- **The owner must be able to understand the code and the reasons behind it.** Explaining decisions is part of every task, not an extra.

Product context lives in `.ai/specs/product-brief.md`. Read it before any feature work. Its Business rules (R01–R06), Non-goals (N01–N04) and Decisions (D01–D13) are the protected contract. Rows marked `proposal` are not yet confirmed by the owner. The open points to settle are OP1–OP9, listed in `.ai/specs/briefs/2026-11-22-pylos-reference-engine.md`.

The repository is greenfield: no Haskell code exists yet, and the Haskell toolchain is not installed on the server yet. Backlog item E01-S01 covers both.

## Task routing

| When the task involves… | Read first | Key rules |
|---|---|---|
| Game rules, moves, perft (reference engine) | `.ai/specs/product-brief.md` (R01–R06, D08, D09, D11, D12) | Pure, readable code (D04, N04). Every rule function's Haddock comment cites the rule id it implements (D13). No performance tricks here. |
| Bitboard engine | Product brief D05 and D11; the reference engine modules once they exist | Must match the reference golden perft and playout files. Reference modules never import bitboard modules. |
| Bots, match runner | Product brief Scope (Later), Q03 | TODO: not yet specified |
| Web server and viewer | Product brief D01, D03, Q02 | The backend serves the frontend. TODO: framework not yet chosen (OP7) |
| Decisions and explanations | `docs/adr/` (once created, D13) | Every non-obvious choice gets a decision record. A brief `proposal` is never recorded as accepted. |
| Specs, briefs, backlog | `.ai/specs/`, `SDLC.md` | Specs and briefs live under `.ai/specs/`. Backlog ids are `E01-S01` etc. |
| Agent pipeline | `.ai/agentic.config.json`, `.ai/trackers/github.md` | Tracker operations only through the descriptor |

## Validation commands

Run in order. All must pass. They become runnable once E01-S01 installs the toolchain.

- `cabal build all`
- `cabal test all`

## Pointers

- Process: `SDLC.md`
- Review rules: `CODE_REVIEW.md`
- Protected surfaces: `BACKWARD_COMPATIBILITY.md`
- Pipeline config: `.ai/agentic.config.json`
