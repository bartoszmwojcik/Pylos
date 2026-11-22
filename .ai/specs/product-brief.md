# Pylos — product brief

- Date: 2026-11-22
- Mode: own; Owner: project owner; Pass: Quick pass (autonomous, with inline review; the owner told the agent to proceed on reasonable assumptions)
- Evidence basis: one direct account: the owner's own messages. It covers the owner's situation and goals only. The owner is the only intended user, so no claim about other users is made. The owner stated directions D01–D07. Every rule of the game (R01–R06) and every design choice D08–D13 is an agent proposal, not yet checked against the printed rulebook or confirmed by the owner. The most consequential untested belief is A01: that R01–R06 read the official rules correctly.
- Coverage: 38 claims — 16 sourced (interview 6, data 0, document 10, product 0, benchmark 0), 0 synthetic, 22 assumed; 1 entry on the collection plan
- Synthetic hypotheses outside Coverage: 0
- Definition of Ready signed by: not yet signed. Rules R01–R06 and the move definition D08 are still proposals awaiting the owner. Ready for: implementation planning of the toolchain and the engine skeleton; stories that encode R01–R06 wait for Q01.
- Sources: `.ai/specs/research/interviews/2026-11-22-owner-account.md`, `.ai/specs/research/decisions/2026-11-22-owner-direction.md`, `.ai/specs/briefs/2026-11-22-pylos-reference-engine.md`

## Decision summary

The owner has agreed to build a Pylos game engine in Haskell. A readable reference engine comes first, then a fast bitboard engine checked against it. Bots and a web demo for watching them follow (D01–D05). The owner is the only user. They develop on a headless server, so watching games must happen in a browser, and they want to understand both the code and why it is built that way (Problems P01–P02).

**Now** covers the two engines plus the toolchain. Bots, the web viewer and human play are **Later**.

The uncertainty most likely to cause rework is whether the proposed rule readings R01–R06 and the move definition D08 match the official rules (A01, Q01). Perft counts and properties only prove that the two engines agree with each other. They do not prove that either engine follows the real rules.

Next action: the owner checks R01–R06 against the rulebook and confirms or corrects them (collection plan). Meanwhile, the backlog can be drafted as a dry run.

## Vision

The owner wants a Pylos implementation they fully understand, whose bots they can develop and then watch play each other in a web browser. This is the owner's intended direction, not a demonstrated benefit. `[INTERVIEW]` owner account 2026-11-22

## Target group and stakeholders

- Customer (pays): none. This is a personal project. `[DOCUMENT]` owner-direction
- User (uses): the project owner, developing on a server without a display. `[INTERVIEW]` owner account 2026-11-22
- Stakeholders (decides, blocks, operates): the owner, in every role.
- Decider for scope decisions: the project owner

## Problems, with evidence

- P01 — The owner develops on a headless server, so a local GUI cannot show bot games. A demo has to be watchable over the web. `[INTERVIEW]` owner account 2026-11-22
- P02 — The owner wants to understand the code and the reasons for its decisions, not only to obtain a working engine. `[INTERVIEW]` owner account 2026-11-22
- P03 — An optimised engine needs an independent correctness oracle, otherwise its bugs go unnoticed. This is the owner's stated rationale for the reference-then-bitboard order. `[INTERVIEW]` owner account 2026-11-22

## Product and how it stands out

- What it is: a Haskell Pylos engine (a reference version and a bitboard version), bots, and a browser viewer served by the same backend. See Scope. `[DOCUMENT]` owner-direction D01–D05
- What makes it different: nothing is claimed. This is a learning project and comparison with other products does not affect the decision.

| reference | what it does well | where it falls short for our users | checked on | link |
|---|---|---|---|---|

Benchmarks are deferred because they do not inform the current decision.

## Goals and success criteria

- Business goal: none. This is a personal learning project.
- User outcome: the owner watches a bot-vs-bot game in a browser and can explain why each engine part is built the way it is. `[INTERVIEW]` owner account 2026-11-22
- Primary metric: deferred. No numeric target was given, and none is needed for the current choice.
- What must not get worse: the bitboard engine must match the reference engine on the frozen perft and playout golden values (D05, D11). `[ASSUMPTION]` agent proposal

## Scope

- **Now:**
  - Toolchain setup (D10).
  - S1, the reference engine: rules R01–R06, moves D08, notation and records D09, QuickCheck properties, bounded playout D12, a perft CLI and golden files (D04, D11).
  - S2, the bitboard engine, verified against S1 (D05).
  - Decision records for every choice (D13).
- **Later:**
  - S3, bots and a match runner with a ply cap (D02, D12).
  - S4, a web viewer served by the backend, with replay and a live game (D01, D03, Q02).
  - S5, human-vs-bot play.
- **Not doing:** see Non-goals.

## Domain glossary

| Term | Meaning | Owned by | Visible to |
|---|---|---|---|
| Reserve | The balls a player has not yet placed (15 at start) | rules | all |
| Free ball | A ball with no ball resting on it (R04) | rules | all |
| Raise | Moving one's own free ball to a higher empty supported square (R03) | rules | all |
| Take-back | Returning 1–2 of one's own free balls to the reserve after completing a square (R02) | rules | all |
| Compound move | An action (place or raise) plus its take-backs, counted as one move (D08) | engine | developer |
| Perft | Count of the move sequences of depth n from a position (D08) | engine | developer |
| Reference / bitboard engine | Readable oracle implementation / optimised implementation | engine | developer |

## Key flows

- Current state: nothing exists. The repository holds only agent skills, and no Haskell toolchain is installed on the server. `[DOCUMENT]` brief 2026-11-22-pylos-reference-engine
- Future state (Now):
  - The owner runs `cabal test`, which runs the properties and rule tests.
  - The owner runs the perft CLI on a position and gets matching counts from both engines.
  - The owner reads the decision records next to the code.
  - `[ASSUMPTION]` agent proposal

## Business rules

| Id | Rule | Applies to | Source | Status | Review by | Required path to change | Owner | Supersedes |
|---|---|---|---|---|---|---|---|---|
| R01 | Standard Gigamic Pylos without the "lines" variant. 30 positions on four levels: a 4×4, b 3×3, c 2×2, d 1. A square on levels b–d can be used only when all 4 squares beneath it are occupied. Each player has 15 balls. | all engines | `[ASSUMPTION]` agent proposal | proposal | Q01 | owner approves a superseding row | project owner | none |
| R02 | Completing a 2×2 of one's own colour on level a, b or c, by placing or by raising, obliges the player to take back 1 or 2 of their own free balls. The ball just moved always qualifies. Alternative: take-back is optional (0–2). | all engines | `[ASSUMPTION]` agent proposal | proposal | Q01 | owner approves a superseding row | project owner | none |
| R03 | A raise moves one's own free ball to an empty supported square on a strictly higher level. The ball must not be one of that square's supports, and support is evaluated after the ball leaves its origin. A raise replaces placing from the reserve. | all engines | `[ASSUMPTION]` agent proposal | proposal | Q01 | owner approves a superseding row | project owner | none |
| R04 | A ball is free when no ball rests on it. Take-backs are applied one after another, so removing the first ball may free a second. | all engines | `[ASSUMPTION]` agent proposal | proposal | Q01 | owner approves a superseding row | project owner | none |
| R05 | The player to move who has an empty reserve loses. Placing the apex therefore ends the game. Alternative: "no legal move loses", which allows raises when the reserve is empty. | all engines | `[ASSUMPTION]` agent proposal | proposal | Q01 | owner approves a superseding row | project owner | none |
| R06 | The engine has no draw rule. Take-backs can make positions repeat, so termination is handled by the match runner's ply cap (D12). | all engines | `[ASSUMPTION]` agent proposal | proposal | Q01 | owner approves a superseding row | project owner | none |

## Non-goals

| Id | We are not building | Why | Owner | Status | Review by | Required path to change | Source | Supersedes |
|---|---|---|---|---|---|---|---|---|
| N01 | The "lines" rule variant. Only a variant hook in the rules type is built. | It keeps the oracle small. | project owner | proposal | after S2 | owner | `[ASSUMPTION]` agent proposal | none |
| N02 | Online multiplayer, accounts or public deployment | One user on one server | project owner | proposal | before S4 | owner | `[ASSUMPTION]` agent proposal | none |
| N03 | A database or persistence beyond game-record files | Records are files (D09) | project owner | proposal | before S3 | owner | `[ASSUMPTION]` agent proposal | none |
| N04 | Performance work in the reference engine | Readability first (D04, D06); speed belongs in S2 | project owner | proposal | none | owner | `[ASSUMPTION]` agent proposal | none |

## Decisions

| Id | Date | Decision | Why | Owner | Status | Review by | Required path to change | Source | Supersedes |
|---|---|---|---|---|---|---|---|---|---|
| D01 | 2026-11-22 | The backend is Haskell, and it serves the web frontend directly. | Owner's choice | project owner | active | none | owner | `[DOCUMENT]` owner-direction | none |
| D02 | 2026-11-22 | Bots come first, and bot-vs-bot games must be observable. | Owner's goal | project owner | active | none | owner | `[DOCUMENT]` owner-direction | none |
| D03 | 2026-11-22 | The demo runs in a web browser. | The server is headless (P01). | project owner | active | none | owner | `[DOCUMENT]` owner-direction | none |
| D04 | 2026-11-22 | Start with a readable pure reference engine checked by QuickCheck properties. | It is the oracle (P03) and serves understanding (P02). | project owner | active | none | owner | `[DOCUMENT]` owner-direction | none |
| D05 | 2026-11-22 | An optimised bitboard engine is checked against the reference by perft counts. | P03 | project owner | active | none | owner | `[DOCUMENT]` owner-direction | none |
| D06 | 2026-11-22 | Code and the reasons for decisions must be understandable. | P02 | project owner | active | none | owner | `[DOCUMENT]` owner-direction | none |
| D07 | 2026-11-22 | Discovery and a backlog come before any spec or code. | Owner's process preference | project owner | active | none | owner | `[DOCUMENT]` owner-direction | none |
| D08 | 2026-11-22 | One move is a compound value: an action (`Place p` or `Raise from to`) plus a set of 0–2 take-backs. Two moves are equal when they have the same action and the same take-back set. A set is legal when at least one removal order is legal. Perft counts these move values, not distinct positions. Sanity values from the start position are 16, 240, 3360 and 43680. | Fixes the perft oracle. The alternative, treating each take-back as its own ply, was rejected because it inflates the tree and changes the notation. This is an agent recommendation. | project owner | proposal | Q01 | owner | `[ASSUMPTION]` agent proposal | none |
| D09 | 2026-11-22 | Positions are written `<level><row><col>`, from `a11` to `d11`. A place is written `a23`, a raise `a11-b22`, and take-backs are appended as ` x a23 a24`. Game records are JSON (`rules`, `white`, `black`, `result`, `moves`, `plies`). | One shared format for perft diffs, logs and replay. This is an agent recommendation. | project owner | proposal | before S1 spec | owner | `[ASSUMPTION]` agent proposal | none |
| D10 | 2026-11-22 | The toolchain is GHC 9.10.x installed through ghcup, built with cabal and tested with tasty, tasty-quickcheck and tasty-hunit. | Nothing is installed on the server today (see Key flows). This is an agent recommendation. | project owner | proposal | before S1 spec | owner | `[ASSUMPTION]` agent proposal | none |
| D11 | 2026-11-22 | Perft values for the start position and for fixed mid-game positions, plus the outcomes of seeded playouts, are frozen as golden files from S1. S2 must match them. | Perft does not check how a game ends, so the seeded playouts cover that. This is an agent recommendation. | project owner | proposal | before S2 spec | owner | `[ASSUMPTION]` agent proposal | none |
| D12 | 2026-11-22 | S1 provides a bounded random playout that returns an outcome or `Capped`. The draw-by-ply-cap policy lives in the S3 runner. | R06 | project owner | proposal | before S3 | owner | `[ASSUMPTION]` agent proposal | none |
| D13 | 2026-11-22 | Every decision gets a decision record in `docs/adr/`. Every rule function's Haddock documentation cites the rule id it implements. | P02. This is an agent recommendation; literate Haskell was the alternative. | project owner | proposal | A02 | owner | `[ASSUMPTION]` agent proposal | none |

## Riskiest assumptions

| Id | Assumption | Importance | Evidence today | If false | Smallest test | Owner | By when | Result |
|---|---|---|---|---|---|---|---|---|
| A01 | R01–R06 and D08 match the official Gigamic rules. `[ASSUMPTION]` agent's recollection | high | none; no rulebook was read | Both engines encode the same wrong rule and pass every differential check. | Read the printed or official rulebook. Check each of R02, R03 and R05 and record the answer per id. | project owner | before S1 rule stories | untested |
| A02 | Decision records plus Haddock rule citations make the code understandable to the owner. `[ASSUMPTION]` agent proposal | medium | none | P02 is not met, and the documentation style must change. | The owner reads the first decision record and the first rules module, then says what was unclear. | project owner | after first S1 story | untested |
| A03 | ghcup with GHC 9.10 installs and builds on the headless server. `[ASSUMPTION]` agent proposal | medium | No Haskell tools are found on the PATH. | The toolchain decision D10 changes (for example to nix or stack). | Install it and run `cabal build` and `cabal test` on a hello-world project with QuickCheck. | project owner | first task | untested |
| A04 | Random-play games end, by a win or the cap, within a few hundred plies. `[ASSUMPTION]` agent proposal | low | none | The ply cap and the playout bound need retuning. | Run 10,000 seeded playouts in S1 and look at the length distribution. | project owner | during S1 | untested |

## Kill criteria

None were stated. For a personal learning project the relevant signal is A02: if the owner cannot follow the reference engine, revise the documentation approach before S2. Whether to stop the project entirely is the owner's call and has not been discussed.

## Hypotheses to test

None. No synthetic material was used.

## Open questions

| Id | Question | Blocking | Who can answer | Status |
|---|---|---|---|---|
| Q01 | Do R01–R06 and D08 match the official rules? In particular: is the take-back mandatory or optional (R02), what happens with an empty reserve (R05), and can a raised ball land on a square it was supporting (R03)? | Yes, for the S1 rule-encoding stories and the golden perft values. Not for the toolchain or the board-geometry skeleton. | project owner, with the rulebook | open |
| Q02 | What form should the web demo take: replay, live, or both; 2D or 3D? What frontend technology? | No, it blocks S4 only. | project owner | open |
| Q03 | Which bots should be built, and how are they judged (win rate, Elo, time or depth limit)? | No, it blocks S3 only. | project owner | open |
| Q04 | Which GitHub repository (or other tracker) will hold the backlog? | Yes, for filing the backlog; not for a dry run. | project owner | open |

## Definition of Ready addendum (own)

P01–P03 and the target group (the owner alone) rest on the owner's direct account, tier 1, within its scope.

Now relies on proposals R01–R06 and D08–D13. None of them has been tested or confirmed. The owner's instruction to proceed on assumptions accepts the risk of drafting, but does not confirm these choices.

Ready for: the toolchain and engine-skeleton work, and a backlog dry run. Rule-encoding stories stay held until Q01 is resolved. The repository has no `SDLC.md`, so its Definition of Ready is not configured.

## Collection plan

### Do R01–R06 and D08 match the official Pylos rulebook?

- What decision or work needs it: Q01, which unblocks the S1 rule stories and the golden perft values
- Who can answer it: project owner
- How: read the official Gigamic rulebook (the printed copy, or the publisher's PDF). Record confirm or correct for each id.
- Owner and by when: project owner; before the S1 rule stories start
- Template: `.ai/specs/research/templates/decision-record.md`
