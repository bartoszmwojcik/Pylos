# Pylos — product brief

- Date: 2026-11-22 (refreshed 2026-11-22; Q02 and Q03 answered 2026-11-23)
- Mode: own; Owner: project owner; Pass: full (refresh, three interview rounds with the owner)
- Evidence basis: two sources, both from the owner. The first is the owner's direct account of their situation and goals. The second is the owner's answers in this refresh session (three rounds), which settle every game rule and confirm the agent's design proposals. The owner is the only intended user, so no claim is made about other users. Several rules began as agent proposals that the owner then confirmed, and R06 and D08 are accepted agent recommendations. The rule answers come from the owner's memory of the game, not from a rulebook that was read. They define the rules this project implements. Whether they match the official Gigamic rules is the most consequential untested belief (A01).
- Coverage: 41 claims — 33 sourced (interview 6, data 0, document 26, product 1, benchmark 0), 0 synthetic, 8 assumed; 0 entries on the collection plan
- Synthetic hypotheses outside Coverage: 0
- Definition of Ready signed by: not yet signed. Ready for: implementation planning of the stated Now scope, once the backlog issues are updated to the new rule ids (see the Definition of Ready addendum).
- Sources: `.ai/specs/research/interviews/2026-11-22-owner-account.md`, `.ai/specs/research/decisions/2026-11-22-owner-direction.md`, `.ai/specs/research/decisions/2026-11-22-owner-rules-and-proposals.md`, `.ai/specs/briefs/2026-11-22-pylos-reference-engine.md`, `.ai/specs/backlog.md`

## Decision summary

The owner is building a Pylos game engine in Haskell. A readable reference engine comes first, then a fast bitboard engine that is checked against it. Bots and a browser viewer for watching them follow (D01–D05). The owner is the only user. They develop on a headless server, so games have to be watched in a browser. They also want to understand the code and why it is built that way (P01–P02).

This refresh settles the rules the engine encodes. Taking balls back after completing a shape is optional, 0–2 balls in total per move (R07). A complete horizontal or vertical row of 4 on the bottom level is a shape, as well as a 2×2 square (R07, R08, D14), so the earlier non-goal N01 is superseded. An empty reserve loses (R05). A raise goes only upward and never onto a square the ball supports (R03). Take-backs happen one at a time (R04). The engine has no draw rule: the match runner's ply cap stops endless games (R06). The compound move (D08) and the earlier proposals D09–D13 and N02–N04 are now confirmed, so no rule or decision in Now is still a proposal. R06 and D08 began as agent recommendations, which the owner accepted.

**Now** is the toolchain and the two engines. Bots, the web viewer and human play are **Later**.

The rules come from the owner's memory. Perft counts and properties only prove that the two engines agree with each other, not that they follow the official game (A01). Backlog issue #8 still has an acceptance criterion requiring 1 or 2 take-backs, which contradicts R07.

Next action: update backlog issues #2 and #5–#12 to the new ids and confirmed statuses, then start the toolchain story #5. The owner may compare the rules with the rulebook before the golden values are frozen (A01). This is optional.

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
- What must not get worse: the bitboard engine must match the reference engine on the frozen perft and playout golden values (D05, D11). `[DOCUMENT]` owner-rules-and-proposals

## Scope

- **Now:**
  - Toolchain setup (D10).
  - S1, the reference engine: rules R03–R08 (R01 and R02 are superseded), moves D08, notation and records D09, QuickCheck properties, bounded playout D12, a perft CLI and golden files (D04, D11).
  - S2, the bitboard engine, verified against S1 (D05).
  - Decision records for every choice (D13).
  - S3, bots (random, greedy, alpha-beta, MCTS, one knob each) and a match runner with a ply cap (D02, D12, D15). Added 2026-11-23.
  - S4, a live 3D web viewer of bot-vs-bot games served by the backend (D01, D03, D16, D17). Added 2026-11-23.
- **Next:**
  - S5, human-vs-bot play in the browser. The owner expects it soon, so S3 and S4 are designed for it (D16).
- **Later:**
  - Replay of recorded games in the viewer (not requested for S4, D17).
- **Not doing:** see Non-goals.

## Domain glossary

| Term | Meaning | Owned by | Visible to |
|---|---|---|---|
| Reserve | The balls a player has not yet placed (15 at start) | rules | all |
| Free ball | A ball with no ball resting on it (R04) | rules | all |
| Raise | Moving one's own free ball to a higher empty supported square (R03) | rules | all |
| Shape | A 2×2 square of one's own colour on level a, b or c, or a complete horizontal or vertical row of 4 of one's own colour on level a (R07) | rules | all |
| Take-back | Optionally returning 0–2 of one's own free balls to the reserve after completing one or more shapes (R07) | rules | all |
| Compound move | An action (place or raise) plus its take-backs, counted as one move (D08) | engine | developer |
| Perft | Count of the move sequences of depth n from a position (D08) | engine | developer |
| Reference / bitboard engine | Readable oracle implementation / optimised implementation | engine | developer |

## Key flows

- Current state: no Haskell code and no Haskell toolchain exist yet. The repository holds the agent skills, the pipeline configuration, and the filed backlog #1–#12. `[PRODUCT]` repository and `.ai/specs/backlog.md`
- Future state (Now):
  - The owner runs `cabal test`, which runs the properties and rule tests.
  - The owner runs the perft CLI on a position and gets matching counts from both engines.
  - The owner reads the decision records next to the code.
  - `[ASSUMPTION]` agent proposal

## Business rules

| Id | Rule | Applies to | Source | Status | Review by | Required path to change | Owner | Supersedes |
|---|---|---|---|---|---|---|---|---|
| R01 | Standard Gigamic Pylos without the "lines" variant. 30 positions on four levels: a 4×4, b 3×3, c 2×2, d 1. A square on levels b–d can be used only when all 4 squares beneath it are occupied. Each player has 15 balls. | all engines | `[ASSUMPTION]` agent proposal | superseded by R08 | — | — | project owner | none |
| R02 | Completing a 2×2 of one's own colour on level a, b or c, by placing or by raising, obliges the player to take back 1 or 2 of their own free balls. The ball just moved always qualifies. Alternative: take-back is optional (0–2). | all engines | `[ASSUMPTION]` agent proposal | superseded by R07 | — | — | project owner | none |
| R03 | A raise moves one's own free ball to an empty supported square on a strictly higher level. The ball must not be one of that square's supports, and support is evaluated after the ball leaves its origin. A raise replaces placing from the reserve. | all engines | `[DOCUMENT]` owner-rules-and-proposals (owner's answer from memory; A01) | active | A01 | owner approves a superseding row | project owner | none |
| R04 | A ball is free when no ball rests on it. Take-backs are applied one after another, so removing the first ball may free a second. | all engines | `[DOCUMENT]` owner-rules-and-proposals (owner's answer from memory; A01) | active | A01 | owner approves a superseding row | project owner | none |
| R05 | The player to move who has an empty reserve loses. Placing the apex therefore ends the game. | all engines | `[DOCUMENT]` owner-rules-and-proposals (owner's answer from memory; A01) | active | A01 | owner approves a superseding row | project owner | none |
| R06 | The engine has no draw rule. Take-backs can make positions repeat, so termination is handled by the match runner's ply cap (D12). | all engines | `[DOCUMENT]` owner-rules-and-proposals (an agent recommendation the owner accepted over a draw rule in the engine) | active | before S3 | owner approves a superseding row | project owner | none |
| R07 | A player who completes a shape, by placing or by raising, may take back 0, 1 or 2 of their own free balls. A shape is a 2×2 square of their own colour on level a, b or c, or a complete horizontal or vertical row of 4 of their own colour on level a. Diagonal rows and rows on level b do not count. A move takes back at most 2 balls in total, however many shapes it completes. | all engines | `[DOCUMENT]` owner-rules-and-proposals (owner's answer from memory; A01) | active | A01 | owner approves a superseding row | project owner | R02 |
| R08 | Pylos as remembered by the owner, including the row rule of R07. 30 positions on four levels: a 4×4, b 3×3, c 2×2, d 1. A square on levels b–d can be used only when all 4 squares beneath it are occupied. Each player has 15 balls. | all engines | `[DOCUMENT]` owner-rules-and-proposals (owner's answer from memory; A01) | active | A01 | owner approves a superseding row | project owner | R01 |

## Non-goals

| Id | We are not building | Why | Owner | Status | Review by | Required path to change | Source | Supersedes |
|---|---|---|---|---|---|---|---|---|
| N01 | The "lines" rule variant. Only a variant hook in the rules type is built. | It keeps the oracle small. | project owner | superseded by D14 | — | — | `[ASSUMPTION]` agent proposal | none |
| N02 | Online multiplayer, accounts or public deployment | One user on one server | project owner | active | before S4 | owner | `[DOCUMENT]` owner-rules-and-proposals | none |
| N03 | A database or persistence beyond game-record files | Records are files (D09) | project owner | active | before S3 | owner | `[DOCUMENT]` owner-rules-and-proposals | none |
| N04 | Performance work in the reference engine | Readability first (D04, D06); speed belongs in S2 | project owner | active | none | owner | `[DOCUMENT]` owner-rules-and-proposals | none |

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
| D08 | 2026-11-22 | One move is a compound value: an action (`Place p` or `Raise from to`) plus a set of 0–2 take-backs. Two moves are equal when they have the same action and the same take-back set. A set is legal when at least one removal order is legal. Perft counts these move values, not distinct positions. Sanity values from the start position are 16, 240, 3360 and 43680. | Fixes the perft oracle. The alternative, treating each take-back as its own ply, was rejected because it inflates the tree and changes the notation. This began as an agent recommendation, which the owner accepted. | project owner | active | A01 | owner | `[DOCUMENT]` owner-rules-and-proposals | none |
| D09 | 2026-11-22 | Positions are written `<level><row><col>`, from `a11` to `d11`. A place is written `a23`, a raise `a11-b22`, and take-backs are appended as ` x a23 a24`. Game records are JSON (`rules`, `white`, `black`, `result`, `moves`, `plies`). | One shared format for perft diffs, logs and replay. This began as an agent recommendation, confirmed as written by the owner. | project owner | active | before S1 spec | owner | `[DOCUMENT]` owner-rules-and-proposals | none |
| D10 | 2026-11-22 | The toolchain is GHC 9.10.x installed through ghcup, built with cabal and tested with tasty, tasty-quickcheck and tasty-hunit. | Nothing is installed on the server today (see Key flows). This began as an agent recommendation, confirmed as written by the owner; whether it installs cleanly is A03. | project owner | active | A03 | owner | `[DOCUMENT]` owner-rules-and-proposals | none |
| D11 | 2026-11-22 | Perft values for the start position and for fixed mid-game positions, plus the outcomes of seeded playouts, are frozen as golden files from S1. S2 must match them. | Perft does not check how a game ends, so the seeded playouts cover that. This began as an agent recommendation, confirmed as written by the owner. | project owner | active | before S2 spec | owner | `[DOCUMENT]` owner-rules-and-proposals | none |
| D12 | 2026-11-22 | S1 provides a bounded random playout that returns an outcome or `Capped`. The draw-by-ply-cap policy lives in the S3 runner. | R06. This began as an agent recommendation, confirmed as written by the owner. | project owner | active | before S3 | owner | `[DOCUMENT]` owner-rules-and-proposals | none |
| D13 | 2026-11-22 | Every decision gets a decision record in `docs/adr/`. Every rule function's Haddock documentation cites the rule id it implements. | P02. This began as an agent recommendation, confirmed as written by the owner; literate Haskell was the alternative. Whether it works for the owner is A02. | project owner | active | A02 | owner | `[DOCUMENT]` owner-rules-and-proposals | none |
| D14 | 2026-11-22 | The engine implements the row rule: a complete horizontal or vertical row of 4 on level a triggers the take-back (R07). It is part of the standard rules, not a variant behind a hook. | The owner's rule answer; the owner approved replacing N01 and R01's exclusion of the lines rule. | project owner | active | A01 | owner | `[DOCUMENT]` owner-rules-and-proposals | N01 |
| D15 | 2026-11-23 | The bots are random, greedy, alpha-beta and MCTS. Each has at most one knob: the evaluation weights for greedy, the search depth for alpha-beta, the iteration count for MCTS. A bot is written as a one-line spec (`alphabeta:depth=3`), so any two configurations can play each other. Greedy and alpha-beta share one evaluation function. Bots run on the bitboard engine. | Owner's answer to Q03, choosing "fewer knobs" over a richer set of parameters per bot. How bots are judged (win rate, Elo) is not decided; the match runner reports wins, losses and draws. | project owner | active | before S5 | owner | `[INTERVIEW]` owner answers 2026-11-23 | none |
| D16 | 2026-11-23 | The web stack is scotty on warp. The server serves plain JavaScript ES modules with a vendored Three.js and no build step. Commands go up as HTTP requests, and game updates come down over Server-Sent Events. Human moves (S5) will be one more `POST` on the same stream, so no WebSocket is needed. | Owner accepted the agent's proposal on 2026-11-23, with the note that human-vs-bot play comes soon. scotty is the most readable Haskell web library; SSE fits one-way watching and also serves S5 with a POST; Three.js gives 3D without a JS toolchain. servant and WebSockets were rejected as more to learn for no current need. | project owner | active | before S5 | owner | `[INTERVIEW]` owner answers 2026-11-23 | none |
| D17 | 2026-11-23 | The viewer shows live games in 3D. Replay of recorded games is not part of S4. | Owner's answer to Q02: "live games, 3D". | project owner | active | before S5 | owner | `[INTERVIEW]` owner answers 2026-11-23 | none |

## Riskiest assumptions

| Id | Assumption | Importance | Evidence today | If false | Smallest test | Owner | By when | Result |
|---|---|---|---|---|---|---|---|---|
| A01 | The owner's remembered rules (R03, R04, R05, R07, R08) match the official Gigamic rules. `[ASSUMPTION]` owner's memory | medium | The owner answered from memory on 2026-11-22; no rulebook was read. The engine follows the owner's chosen rules either way. | Both engines encode the same non-official rule and pass every differential check. That matters only if the owner wants the official game. | Read the printed or publisher's rulebook and compare R03, R04, R05, R07, R08 and D14 one by one. | project owner | before golden values are frozen (#10) | untested |
| A02 | Decision records plus Haddock rule citations make the code understandable to the owner. `[ASSUMPTION]` agent proposal | medium | The owner read the decision records and the reference rules module on 2026-11-23. | P02 is not met, and the documentation style must change. | The owner reads the first decision record and the first rules module, then says what was unclear. | project owner | after first S1 story | confirmed 2026-11-23: the owner can read the rules and the code (#6) |
| A03 | ghcup with GHC 9.10 installs and builds on the headless server. `[ASSUMPTION]` agent proposal | medium | No Haskell tools are found on the PATH. | The toolchain decision D10 changes (for example to nix or stack). | Install it and run `cabal build` and `cabal test` on a hello-world project with QuickCheck. | project owner | first task | untested |
| A04 | Random-play games end, by a win or the cap, within a few hundred plies. `[ASSUMPTION]` agent proposal | low | none | The ply cap and the playout bound need retuning. | Run 10,000 seeded playouts in S1 and look at the length distribution. | project owner | during S1 | untested |

## Kill criteria

None were stated. For a personal learning project the relevant signal was A02: if the owner could not follow the reference engine, the documentation approach would change. A02 was confirmed on 2026-11-23. Whether to stop the project entirely is the owner's call and has not been discussed.

## Hypotheses to test

None. No synthetic material was used.

## Open questions

| Id | Question | Blocking | Who can answer | Status |
|---|---|---|---|---|
| Q01 | Do R01–R06 and D08 match the official rules? In particular: is the take-back mandatory or optional (R02), what happens with an empty reserve (R05), and can a raised ball land on a square it was supporting (R03)? | No | project owner, with the rulebook | closed 2026-11-22: superseded by the owner's chosen rules (R03–R08, D08, D14). The official match is A01. |
| Q02 | What form should the web demo take: replay, live, or both; 2D or 3D? What frontend technology? | No, it blocks S4 only. | project owner | closed 2026-11-23: live games in 3D (D17); scotty + SSE + Three.js (D16) |
| Q03 | Which bots should be built, and how are they judged (win rate, Elo, time or depth limit)? | No, it blocks S3 only. | project owner | closed 2026-11-23: greedy, alpha-beta and MCTS with one knob each (D15); judging is still open and does not block S3 |
| Q04 | Which GitHub repository (or other tracker) will hold the backlog? | No | project owner | closed: the backlog is filed as #1–#12 in the project's GitHub repository (`.ai/specs/backlog.md`) |
| Q05 | Clarify open points OP1–OP9, listed in `.ai/specs/briefs/2026-11-22-pylos-reference-engine.md` under "Open points for om-discover". | No | project owner, via `om-discover --refresh` | partly answered 2026-11-22: OP1, OP2, OP3, OP4 principle (D11), OP7 toolchain (D10), OP8 (D13). OP9 is settled by the Scope confirmed with this brief. OP5 and OP6 remain as Q03 and Q02; OP7's web layer and frontend remain with Q02. |
| Q06 | Confirm or correct R04 (free ball; take-backs in order) and R06 (no draw rule in the engine). | No | project owner | closed 2026-11-22: both confirmed (R04, R06) |

## Definition of Ready addendum (own)

P01–P03 and the target group (the owner alone) rest on the owner's direct account, within its scope.

Every rule and decision that Now relies on (R03–R08, D08–D14, N02–N04) is active, with the owner as decider. The rules come from the owner's memory. Their match with the official game is untested (A01). The owner sets the rules for this personal project, so that does not block the work. No blocking question is open.

Ready for: implementation planning of the toolchain, S1 and S2 (#5–#12). Issues #2, #7, #8 and #10 cite the superseded R01, R02 or N01, and #5–#12 all say they are not ready until the proposals are confirmed (#6 still lists D13 as a proposal). #8's criterion "every move from that square carries 1 or 2 take-backs" contradicts R07. Those issues need updating before implementation (`om-auto-manage-issues`). The brief itself is not the blocker.

## Collection plan

No material is needed for the current decision. The rulebook comparison is A01's test, not a blocker, because the owner chose the rules.
