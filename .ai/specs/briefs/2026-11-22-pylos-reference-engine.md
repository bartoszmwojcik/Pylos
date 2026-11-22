# Pylos S1: pure Haskell reference rules engine with notation, game records, QuickCheck properties and a perft CLI

- Date: 2026-11-22
- Category: feature
- Priority signal: high — every later slice (bitboard engine, bots, web demo) uses this engine as its correctness oracle
- Risk signal: medium — a rules misreading here passes every later differential test, because the fast engine is checked against this one
- Routing: Next: om-auto-write-spec "Pylos S1: pure Haskell reference rules engine with notation, game records, QuickCheck properties and perft CLI — brief: .ai/specs/briefs/2026-11-22-pylos-reference-engine.md"

## Problem

The user wants a Pylos web application with a Haskell backend that also serves the web frontend. The first priority is game-playing bots. Bot-vs-bot games must be watchable in a browser, because development happens on a headless server.

The user wants to understand the code and the reasons behind each decision. **Readability and explained decisions take priority over speed in this slice.**

A fast bitboard engine and the bots both need a trusted oracle first. That oracle is a small, obviously-correct, pure reference implementation of the rules. Its behaviour is pinned by QuickCheck properties and by perft counts (the number of legal move sequences of depth N from a position).

The repository is currently empty apart from installed agent skills. There is no Haskell toolchain on the dev server: `ghc`, `cabal`, `stack`, `ghcup` and `nix` are all missing. Node v22 is present.

## Agreed direction

The work is split into independently verifiable slices. **Only S1 is routed now.**

| Slice | Content | Depends on |
|-------|---------|------------|
| **S1 (this brief)** | Reference rules engine, move notation, game-record format, QuickCheck properties, bounded random playout, perft CLI | — |
| S2 | Bitboard engine (two colour masks in `Word32`/`Word64`), differential perft and playout comparison against S1 | S1 |
| S3 | Bots (random → greedy → alpha-beta → later MCTS), match/tournament runner with ply cap, win-rate stats, JSON game records | S1 (S2 for speed) |
| S4 | Web viewer: warp serves a static frontend; replay of recorded games plus live bot-vs-bot over SSE | S1 records, S3 |
| S5 | Human vs bot in the browser | S4 |

Rejected alternatives:

- **Build nothing / adopt an existing implementation or a generic game framework and only write bots.** Pylos implementations are scarce and rarely in Haskell. This option also defeats the stated learning goal.
- **Bitboard engine first.** It would have no oracle to check it against, so its bugs would be invisible.
- **Web viewer first.** There is nothing to show until the rules exist.

## Resolved unknowns

The user told the agent to proceed autonomously, so the rows marked **(default, verify)** are agent-chosen defaults. They are not confirmed by the user or checked against the printed rulebook.

The spec must list them as numbered decisions D1–D6. Each one needs a hand-built unit test that demonstrates it, so that changing a decision is a one-line flag change plus updated tests.

| # | Question | Answer |
|---|----------|--------|
| D1 | Rule variant | Standard Gigamic Pylos, no "lines" rule. The `Rules` record carries a variant field so the lines rule can be added later without restructuring. (default, verify) |
| D2 | Board geometry | 30 positions on 4 levels: a = 4×4, b = 3×3, c = 2×2, d = 1 (apex). Each square on levels b–d rests on the 4 squares beneath it. A position on levels b–d is placeable only when all 4 supporting squares are occupied. |
| D3 | Game end | The player to move with an empty reserve loses. Placing the apex ends the game, and the opponent then cannot move. Alternative to keep behind a flag: "no legal move loses", which counts raises as legal moves even with an empty reserve. (default, verify) |
| D4 | Square rule | Completing a 2×2 of own colour on levels a, b or c, by placing or by raising, obliges the player to take back **1 or 2** of their own free balls. At least one free own ball always exists: the ball just placed or raised has nothing on top. Alternative behind a flag: 0–2 (optional). (default, verify) |
| D5 | Raise | Moves an own **free** ball (nothing resting on it) to an empty, supported square on a strictly higher level. The ball must not be one of that square's supports. Supports are evaluated **after** the ball leaves its origin. A raise counts as a move instead of placing from reserve. (default, verify) |
| D6 | Free ball | A ball is free when no ball rests on it. Removals are evaluated sequentially: removing the first ball may free a second. |
| M1 | What one move is | A **compound move**: `Move { action :: Place Pos \| Raise Pos Pos, takeBack :: [Pos] }`. `takeBack` is empty when no own square was formed, otherwise of length 1–2 (per D4). |
| M2 | Canonical form / dedup | Two moves are equal iff they have the same action and the same **set** of taken-back positions. A set {x, y} is legal iff at least one removal order is legal (each ball free when it is removed). It is stored sorted, and is counted once even when only one order works. "Take back x" and "take back x and y" are distinct moves. |
| M3 | Perft definition | `perft n p` counts distinct canonical compound moves along all paths of length n. It is **not** a count of distinct positions. Sanity values from the start position: perft 1 = 16, perft 2 = 240, perft 3 = 3360, perft 4 = 43680. No square or raise is possible before ply 5. Values from depth 5 on are computed by S1 and frozen as golden numbers for S2. |
| N1 | Notation | Positions are written `<level><row><col>` with 1-based row and col: a11–a44, b11–b33, c11–c22, d11. Placement: `a23`. Raise: `a11-b22`. Take-back: ` x a23 a24` appended. The parser and printer must round-trip. |
| R1 | Game record | JSON: `{rules, white, black, result, moves: ["a23", "a11-b22 x b22", …], plies}`. The same format is used for replays in S3/S4. |
| T1 | Termination | The pure engine has **no draw rule**, because cycles are possible: taken-back balls return to the reserve. S1 provides a bounded `playout :: Int -> Seed -> Position -> (Outcome \| Capped)` helper. A draw-by-ply-cap policy belongs to the S3 runner. |
| K1 | Toolchain | ghcup-installed GHC **9.10.x** (the spec pins the exact minor) with cabal. Tests use `tasty` + `tasty-quickcheck` + `tasty-hunit`. The first task is to install the toolchain and get `cabal build && cabal test` green on a hello-world. |
| K2 | Explaining decisions | ADRs in `docs/adr/NNNN-*.md`: one for the slice plan, one per decision D1–D6/M1–M3, one for the toolchain. Haddock prose on every rule function cites the rule it implements, e.g. "D5". |
| S | Specs location | There is no `.ai/agentic.config.json`, so the default `.ai/specs` is used. |

## Acceptance (S1)

- `cabal build` and `cabal test` pass on the headless server from a clean checkout. The README lists the ghcup install steps.
- QuickCheck properties pass over random reachable positions, generated by random legal play from the start, not hand-built boards:
  - **Ball conservation:** on board plus in reserve = 15 per colour, always.
  - **No floating balls:** every occupied b–d square has 4 occupied supports.
  - **Closure:** every generated move is legal, and applying it yields a valid position.
  - **Notation round-trip:** `parse . render == Just` for every legal move.
  - **Symmetry:** the move count is invariant under the 8 square symmetries, tested on random positions and not only the start.
  - **Dedup:** generated move lists contain no duplicates under M2.
  - **Bounded playouts:** every bounded random playout returns either an outcome or `Capped`.
- At least one hand-built HUnit test per decision D3–D6. These are the rulebook cases.
- The CLI `pylos-ref perft <depth> [position-or-move-list]` prints perft 1..N, with timings, for the start position and for any position given as a move list.
- A frozen golden file of perft values (start position plus a few fixed mid-game positions) and of seeded playout outcomes. S2 will use it as its oracle, so perft and terminal or outcome semantics are both covered.
- The ADRs listed in K2 exist, and each D/M decision is cross-referenced from code.

## Non-goals

- No bitboard or other optimisation. Clarity beats speed, and performance is S2's job.
- No bots beyond the uniform-random mover that playouts need. No match runner or ply-cap draw policy (S3).
- No HTTP server, frontend or web demo (S4). No human play (S5).
- No lines-rule implementation, only the variant hook (D1).
- No persistence or database.

## Open points for om-discover to clarify with the owner

These are the 9 gaps named at the start of the brainstorm (2026-11-22). Each one currently has only an agent default. None of them is confirmed by the owner yet.

`om-discover --refresh` should walk the owner through them in the order below. It should record each answer as a decision record under `.ai/specs/research/decisions/` and update the matching row in `.ai/specs/product-brief.md`. The table's last column says when each point is best settled.

| # | Open point | Current agent default | Product-brief ids | Settle in |
|---|------------|-----------------------|-------------------|-----------|
| OP1 | **Exact rules.** Which variant: basic, or with the lines rule? Is take-back mandatory (1–2) or optional (0–2)? What exactly is a free ball, and what may a raise do? What ends the game, especially with an empty reserve? How are repetition and loops handled? | D1, D3–D6 above | R01–R06, Q01, A01 | om-discover. Check the official rulebook first. |
| OP2 | **What one move is.** A compound move (action plus take-backs), or each take-back as its own ply? What makes two moves "the same" for perft? | M1–M3 above | D08 | om-discover |
| OP3 | **Move notation and game-record format**, shared by perft diffs, logs, replays and the viewer | N1, R1 above | D09 | om-discover if the owner wants it fixed early; otherwise the S1 spec |
| OP4 | **What the perft check covers.** Which depths, which start and mid-game positions, whether symmetry is checked, and whether seeded playout outcomes are compared too | M3, acceptance above | D11 | S1 and S2 specs. om-discover only confirms the principle. |
| OP5 | **Which bots, and how they are judged.** Random, greedy, alpha-beta, MCTS? Judged by win rate, Elo, or time or depth limits? Who plays whom in a tournament? | random mover only in S1 | Q03, Scope Later (S3) | om-discover (which bots are Now or Later), then the backlog stories |
| OP6 | **What the demo is.** Live streaming of a running match (SSE or WebSocket), replay of recorded games, or both? A 2D or 3D board? Viewing only, or human play later? | replay and live over SSE, 2D, human play in S5 | Q02, D01, D03 | om-discover (Scope and Key flows) |
| OP7 | **Stack.** GHC version, and cabal, stack or nix? Which web layer (warp, scotty, servant)? Which frontend language and build: plain JS, TypeScript, or Haskell-to-JS? Is Node acceptable on the server? | K1: GHC 9.10 with ghcup, cabal and tasty; web layer and frontend open | D10, A03 | om-discover for the constraints; the specs for the library choices |
| OP8 | **How the owner learns from the code.** Decision records (ADRs), literate Haskell, a design doc per layer, or a mix? What makes a module "understood"? | K2: ADRs in `docs/adr/` and Haddock comments citing rule ids | D06, D13, A02 | om-discover (goal), then backlog acceptance criteria |
| OP9 | **Slicing.** Where does the first slice end, and what are the Now and Later slices? | S1 to S5 table above; Now = toolchain, S1 and S2 | Scope, backlog E01–E04 | om-discover (Scope), then om-backlog epics |

## Affected areas (if known)

- Greenfield repository. Suggested layout: a cabal package `pylos` with library modules `Pylos.Reference.{Board,Move,Rules,Notation,Record,Perft,Playout}`, executable `pylos-ref`, test-suite `pylos-ref-test`, and `docs/adr/`.
- Prerequisite: install the Haskell toolchain via ghcup. Nothing is installed on the server today.
