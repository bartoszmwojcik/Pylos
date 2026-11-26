# Pylos — product brief

- Date: 2026-11-22 (refreshed 2026-11-22; Q02 and Q03 answered 2026-11-23; S5 refresh 2026-11-24; S6 refresh 2026-11-26)
- Mode: own (the S6 refresh adds the checks for an existing product); Owner: project owner; Pass: full (refresh, three interview rounds with the owner on 2026-11-22; a further refresh of three rounds on 2026-11-24 for S5; a one-round refresh on 2026-11-26 for S6)
- Evidence basis: all sources come from the owner. The first is the owner's direct account of their situation and goals. The second is the owner's answers in the 2026-11-22 refresh session (three rounds), which settle every game rule and confirm the agent's design proposals. The third is the owner's answers on 2026-11-23 (bots and viewer), 2026-11-24 (human-vs-bot play) and 2026-11-26 (a prebuilt install and release 0.1.0). The owner is the only user with a recorded account. The owner also wants the game to be playable by "anyone who installs this game"; no such person is named or interviewed, so nothing is claimed about their needs (A05). Several rules began as agent proposals that the owner then confirmed, and R06 and D08 are accepted agent recommendations. The rule answers come from the owner's memory of the game, not from a rulebook that was read. They define the rules this project implements. Whether they match the official Gigamic rules is the most consequential untested belief (A01).
- Coverage: 71 claims — 56 sourced (interview 9, data 0, document 40, product 7, benchmark 0), 0 synthetic, 15 assumed; 0 entries on the collection plan
- Synthetic hypotheses outside Coverage: 0
- Definition of Ready signed by: not yet signed. Ready for: a backlog and implementation plan for S6 (see the Definition of Ready addendum).
- Sources: `.ai/specs/research/interviews/2026-11-22-owner-account.md`, `.ai/specs/research/decisions/2026-11-22-owner-direction.md`, `.ai/specs/research/decisions/2026-11-22-owner-rules-and-proposals.md`, `.ai/specs/research/decisions/2026-11-23-owner-bots-and-viewer.md`, `.ai/specs/research/decisions/2026-11-24-owner-human-vs-bot.md`, `.ai/specs/research/decisions/2026-11-26-owner-prebuilt-install.md`, `.ai/specs/briefs/2026-11-22-pylos-reference-engine.md`, `.ai/specs/backlog.md`

## Decision summary

The owner is building Pylos in Haskell as a learning project: a readable reference engine, a bitboard engine checked against it, bots, and a 3D browser viewer served by the same backend (D01–D05, D15–D17). The owner develops on a headless server, so games are watched in a browser (P01). They also want to understand the code and why it is built that way (P02). The rules are the owner's remembered rules (R03–R08, D08, D14); whether they match the official game is untested (A01).

The toolchain, both engines, the bots, the match runner and the live viewer are built and merged (E01–E04, closed 2026-11-24).

S5, human-vs-bot play in the browser with a phone layout, opt-in home-network listening and a training mode, was moved into Now on 2026-11-24 (D18–D22, N05). S5 is built and merged (E05, #39). `[PRODUCT]` repository, `main` at `f07b746`

This refresh moves **S6, a prebuilt install, into Now**. Today Pylos can be installed only by building it from source with the Haskell toolchain (P05). The owner asked for an Ubuntu package, a first version 0.1.0 published as a GitHub Release with an executable and the package, and a README section on installing without compiling. S6 is a `.deb` for Ubuntu 24.04 amd64 and a `.tar.gz` with the `pylos-web` executable and its web files (D23). Only the game server is packaged, and it is started by hand; there is no service, and it still listens on 127.0.0.1 by default (D24). A GitHub Actions workflow builds both files and publishes the Release when the tag `v0.1.0` is pushed (D25). D23 supersedes D21; building from source stays documented for other systems and for the developer tools.

Unknowns that do not block S6: who besides the owner will install it (A05), and whether the binary built on GitHub's runner starts on a clean Ubuntu 24.04 with only the package's declared libraries (A07); the workflow checks that before it publishes. The installed server finds its web files by D26.

Next action: implement S6 on one PR (not started; the owner chose to stop after the brief on 2026-11-26); after it is merged, push the tag `v0.1.0`.

## Vision

The owner wants a Pylos implementation they fully understand, whose bots they can develop and then watch play each other in a web browser. This is the owner's intended direction, not a demonstrated benefit. `[INTERVIEW]` owner account 2026-11-22

The owner also wants to play the bots themselves, and wants the game to be playable by anyone who installs it. `[DOCUMENT]` owner-human-vs-bot 2026-11-24

## Target group and stakeholders

- Customer (pays): none. This is a personal project. `[DOCUMENT]` owner-direction
- User (uses): the project owner, developing on a server without a display. `[INTERVIEW]` owner account 2026-11-22
- Intended future users: people who install the game, from source or (after S6) from the Ubuntu package, and play it against a bot. The owner chose this audience, but no such person is named and nothing is known about their needs (A05). `[DOCUMENT]` owner-human-vs-bot 2026-11-24
- Stakeholders (decides, blocks, operates): the owner, in every role.
- Decider for scope decisions: the project owner

## Problems, with evidence

- P01 — The owner develops on a headless server, so a local GUI cannot show bot games. A demo has to be watchable over the web. `[INTERVIEW]` owner account 2026-11-22
- P02 — The owner wants to understand the code and the reasons for its decisions, not only to obtain a working engine. `[INTERVIEW]` owner account 2026-11-22
- P03 — An optimised engine needs an independent correctness oracle, otherwise its bugs go unnoticed. This is the owner's stated rationale for the reference-then-bitboard order. `[INTERVIEW]` owner account 2026-11-22
- P04 — The owner wants to play them to judge whether the bot's position evaluation is good, to improve their own play, and to get a feel for how the different bots play. `[DOCUMENT]` owner-human-vs-bot 2026-11-24. That no human can play today is a repository fact: the web protocol has no move command (`docs/web-protocol.md`). The first sentence is the agent's framing of why watching is not enough. `[PRODUCT]` repository
- P05 — Installing Pylos today needs ghcup, GHC 9.10.1, several system libraries and a build of a few minutes (README, Install). `[PRODUCT]` repository, README at `f07b746`
- P05 (request) — The owner asked for an install on Ubuntu without compiling, published as release 0.1.0. They did not say who it is for or why now; no other installer is known (A05). `[DOCUMENT]` owner-prebuilt-install 2026-11-26

## Product and how it stands out

- What it is: a Haskell Pylos engine (a reference version and a bitboard version), bots, and a browser viewer served by the same backend. See Scope. `[DOCUMENT]` owner-direction D01–D05
- What makes it different: nothing is claimed. This is a learning project and comparison with other products does not affect the decision.

| reference | what it does well | where it falls short for our users | checked on | link |
|---|---|---|---|---|

Benchmarks are deferred because they do not inform the current decision.

## Goals and success criteria

- Business goal: none. This is a personal learning project.
- User outcome: the owner watches a bot-vs-bot game in a browser and can explain why each engine part is built the way it is. `[INTERVIEW]` owner account 2026-11-22
- User outcome (S5): the owner plays a full game against any bot spec, on a laptop and on a phone, entering only legal moves, and the game ends with a result. The phone part depends on A06. `[ASSUMPTION]` agent proposal, derived from D18–D20
- User outcome (S6): on a clean Ubuntu 24.04 amd64 machine without Haskell tools, a person downloads the `.deb` from Release `v0.1.0`, installs it, starts `pylos-web`, opens the page and plays a game. `[ASSUMPTION]` agent proposal, derived from D23–D25
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
  - S1–S4 are built and merged (E01–E04). `[PRODUCT]` repository, `main` at `08bfd92`
  - S5, human-vs-bot play in the browser: one human against one bot, legal moves only, no undo (D18); phone and large-screen layouts (D19); opt-in home-network listening (D20, N05); install by building from source (D21, superseded by D23 for Ubuntu 24.04 amd64); an optional training mode that shows the bot's score (D22). Moved from Next on 2026-11-24.
  - S6, a prebuilt install: a `.deb` for Ubuntu 24.04 amd64 and a `.tar.gz` with `pylos-web` and its web files (D23, D24), published as GitHub Release `v0.1.0` by a tag-triggered workflow (D25), and a README section on installing without compiling. Added 2026-11-26.
- **Next:**
  - Nothing is planned yet.
- **Later:**
  - Replay of recorded games in the viewer (not requested for S4, D17).
  - A fuller view of what the bot thinks, such as its best few moves with their scores, or scores from every bot kind on the same scale. S5's training mode (D22) is the small first version.
  - Human vs human on one browser, and taking over one side of a running bot game (not chosen for S5, D18).
  - Undo (excluded from S5, D18).
  - Packages for other Ubuntu versions, other distributions or architectures, the developer tools as packages, a service that starts at boot, or a container (D23, D24).
  - Deeper alpha-beta search, up to depth 9 (#29).
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

- Historical state (2026-11-22): no Haskell code and no Haskell toolchain existed yet. The repository holds the agent skills, the pipeline configuration, and the filed backlog #1–#12. `[PRODUCT]` repository and `.ai/specs/backlog.md`
- Future state (Now):
  - The owner runs `cabal test`, which runs the properties and rule tests.
  - The owner runs the perft CLI on a position and gets matching counts from both engines.
  - The owner reads the decision records next to the code.
  - `[ASSUMPTION]` agent proposal
- Current state (2026-11-24): the engines, bots, `pylos-match` and the live 3D viewer exist. The viewer only watches bot games, and the server listens only on 127.0.0.1. `[PRODUCT]` repository, `docs/web-protocol.md`
- Future state (S5), to be settled in the S5 spec:
  1. The owner opens the viewer on a laptop, or on a phone on the home network (D20).
  2. They start a game as "you vs bot": they pick their colour, the bot spec, and a real or training game (D22).
  3. On their turn they place a ball by tapping or clicking a legal empty square, or raise by choosing one of their free balls and then a legal higher square. Only legal choices respond (D18).
  4. When the move completes a shape, they choose 0, 1 or 2 of their own free balls to take back and confirm (R07, R04).
  5. The move is sent to the server; the bot replies; both moves appear on the same event stream (D16). In a training game, the bot's score appears after each move.
  6. The game ends with a win, a loss or the ply cap (R05, D12).
  - `[ASSUMPTION]` agent proposal; steps 3–4 are the input design the spec must work out for both touch and mouse

- Current state (2026-11-26): the game is installed only by building from source (README). `[PRODUCT]` repository
- Future state (S6), to be settled in the implementation:
  1. A person opens the project's Releases page and downloads `v0.1.0`: the `.deb`, or the `.tar.gz`.
  2. With the `.deb`: `sudo apt install ./<package>.deb`, then `pylos-web` from any folder. With the `.tar.gz`: unpack it and run `./pylos-web` inside.
  3. They open http://localhost:8080 and play as in S5. `--lan` and the port work as before (D20).
  4. To remove it: `sudo apt remove pylos`.
  - `[ASSUMPTION]` agent proposal; the web-file lookup is D26; package name and file names are for the implementation

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
| N02 | Online multiplayer, accounts or public deployment | One user on one server | project owner | superseded by N05 | — | — | `[DOCUMENT]` owner-rules-and-proposals | none |
| N03 | A database or persistence beyond game-record files | Records are files (D09) | project owner | active | before S3 | owner | `[DOCUMENT]` owner-rules-and-proposals | none |
| N04 | Performance work in the reference engine | Readability first (D04, D06); speed belongs in S2 | project owner | active | none | owner | `[DOCUMENT]` owner-rules-and-proposals | none |
| N05 | Online multiplayer, accounts, or deployment reachable from the internet. Listening on the home network is allowed only when the owner turns it on (D20); the default stays 127.0.0.1. | The owner allowed the home network for phone play (D20) and kept no accounts. That each player runs their own copy is the agent's reading of "anyone who installs this game" (D21). | project owner | active | before any feature that needs a second player or internet access | owner approves a superseding row | `[DOCUMENT]` owner-human-vs-bot 2026-11-24 | N02 |

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
| D15 | 2026-11-23 | The bots are random, greedy, alpha-beta and MCTS. Each has at most one knob: the evaluation weights for greedy, the search depth for alpha-beta, the iteration count for MCTS. A bot is written as a one-line spec (`alphabeta:depth=3`), so any two configurations can play each other. Greedy and alpha-beta share one evaluation function. Bots run on the bitboard engine. | Owner's answer to Q03, choosing "fewer knobs" over a richer set of parameters per bot. How bots are judged (win rate, Elo) is not decided; the match runner reports wins, losses and draws. | project owner | active | reviewed for S5 on 2026-11-24, unchanged | owner | `[INTERVIEW]` owner answers 2026-11-23 | none |
| D16 | 2026-11-23 | The web stack is scotty on warp. The server serves plain JavaScript ES modules with a vendored Three.js and no build step. Commands go up as HTTP requests, and game updates come down over Server-Sent Events. Human moves (S5) will be one more `POST` on the same stream, so no WebSocket is needed. | Owner accepted the agent's proposal on 2026-11-23, with the note that human-vs-bot play comes soon. scotty is the most readable Haskell web library; SSE fits one-way watching and also serves S5 with a POST; Three.js gives 3D without a JS toolchain. servant and WebSockets were rejected as more to learn for no current need. | project owner | active | reviewed for S5 on 2026-11-24, unchanged | owner | `[INTERVIEW]` owner answers 2026-11-23 | none |
| D17 | 2026-11-23 | The viewer shows live games in 3D. Replay of recorded games is not part of S4. | Owner's answer to Q02: "live games, 3D". | project owner | active | reviewed for S5 on 2026-11-24, unchanged | owner | `[INTERVIEW]` owner answers 2026-11-23 | none |
| D18 | 2026-11-24 | S5 is one human against one bot in the browser. Only legal moves can be entered; there is no undo. | P04. The owner chose "just me as a player" over human vs human on one browser and over taking over a side mid-game; those two are Later. "only legal move is possible. no undo." How a game is set up (a "human" player kind next to the bot specs, ADR 0023; the human picking the bot and their colour) is an agent proposal for the S5 spec. | project owner | active | before the S5 spec | owner | `[DOCUMENT]` owner-human-vs-bot 2026-11-24 | none |
| D19 | 2026-11-24 | The play screen works on a phone and on a large screen. The two may use different layouts, and input works by touch and by mouse. | The owner's words: "UX should be intuitive, so I assume mobile phone and big screen can be a bit different." What "intuitive" means in detail is for the S5 spec and its design pass. | project owner | active | before the S5 spec | owner | `[DOCUMENT]` owner-human-vs-bot 2026-11-24 | none |
| D20 | 2026-11-24 | The server keeps listening on 127.0.0.1 by default. An explicit start-up option makes it listen on the home network, so a phone on the same network can play. There are no accounts and no authentication. | A phone cannot reach 127.0.0.1 on the server. The agent proposed the option because, in the agent's view, an SSH tunnel is awkward on a phone. The owner answered "whatever technically in home network is feasible", delegating the technical choice. While the option is on, anyone on the same network can open the game and start or play games with no password; the owner accepted that: "it's ok." | project owner | active | A06 | owner | `[DOCUMENT]` owner-human-vs-bot 2026-11-24 | none |
| D21 | 2026-11-24 | People other than the owner install the game by building it from source, as the README describes. An easier install is Later. | The owner's answer: "yes full build for now". It was an agent recommendation; no other player is known yet (A05). | project owner | superseded by D23 (for Ubuntu 24.04 amd64) | — | — | `[DOCUMENT]` owner-human-vs-bot 2026-11-24 | none |
| D22 | 2026-11-24 | A game against a bot is started either as a real game or as a training game. In a training game, the screen shows after each move how the bot scores the position. Greedy and alpha-beta show the shared evaluation (alpha-beta its search score), MCTS its win rate for the move it chose, and random shows nothing. A real game shows no bot information. The mode is fixed when the game starts. | P04: the owner wants to judge whether the bot's evaluation is good. The owner asked for a small version that can be turned off: "propose a small version of it. it should be possible though to disable it in order to have choice of real game or training one". The details (which score, fixed at start rather than toggled mid-game) are an agent proposal. Fixing the mode at start keeps a real game free of hints. A fuller view (best moves with scores) is Later. | project owner | active | before the S5 spec | owner | `[DOCUMENT]` owner-human-vs-bot 2026-11-24 | none |
| D23 | 2026-11-26 | Ubuntu 24.04 amd64 users can install Pylos without compiling: a `.deb` package and a `.tar.gz` archive, both holding the `pylos-web` executable and its web files, are attached to a GitHub Release. The first release is version 0.1.0. Other systems and the developer tools are still built from source, as the README describes. | P05: the owner's request on 2026-11-26. The owner chose Ubuntu 24.04 amd64 (the agent's recommendation) over also building for 22.04; a binary built on one Ubuntu needs that version's C library or newer. | project owner | active | A05, A07 | owner approves a superseding row | `[DOCUMENT]` owner-prebuilt-install 2026-11-26 | D21 |
| D24 | 2026-11-26 | The package holds only `pylos-web` and its web files. It installs no service: the server is started by hand and keeps listening on 127.0.0.1 unless `--lan` is given (N05, D20). | The owner chose "only pylos-web" over all four commands (the agent's recommendation) and over a systemd service. Without a service the server never runs unattended, so the exposure of D20 is unchanged. | project owner | active | none | owner approves a superseding row | `[DOCUMENT]` owner-prebuilt-install 2026-11-26 | none |
| D25 | 2026-11-26 | A GitHub Actions workflow builds the `.deb` and the `.tar.gz` and publishes the GitHub Release when a version tag (`v0.1.0`) is pushed. The agent pushes `v0.1.0` after the S6 PR is merged to `main`. | The owner chose the agent's recommendation over creating the tag by hand. Building on GitHub's runner makes every release repeatable from a tag. It adds CI, which AGENTS.md lists under "Ask first"; this answer is that approval. | project owner | active | none | owner approves a superseding row | `[DOCUMENT]` owner-prebuilt-install 2026-11-26 | none |
| D26 | 2026-11-26 | When `pylos-web` is started without WEB_DIR, it uses `./web` if that folder exists, as today; otherwise a `web` folder next to the executable (the `.tar.gz`); otherwise `/usr/share/pylos/web` (the `.deb`). An explicit WEB_DIR and the other arguments keep their meaning. | Lets the installed command run from any folder while a source checkout behaves as before. The owner chose this agent recommendation over a wrapper script, which would force a port whenever WEB_DIR is given and would not help the `.tar.gz`. | project owner | active | none | owner approves a superseding row | `[DOCUMENT]` owner-prebuilt-install 2026-11-26 | none |

## Riskiest assumptions

| Id | Assumption | Importance | Evidence today | If false | Smallest test | Owner | By when | Result |
|---|---|---|---|---|---|---|---|---|
| A01 | The owner's remembered rules (R03, R04, R05, R07, R08) match the official Gigamic rules. `[ASSUMPTION]` owner's memory | medium | The owner answered from memory on 2026-11-22; no rulebook was read. The engine follows the owner's chosen rules either way. | Both engines encode the same non-official rule and pass every differential check. That matters only if the owner wants the official game. | Read the printed or publisher's rulebook and compare R03, R04, R05, R07, R08 and D14 one by one. | project owner | before golden values are frozen (#10) | untested |
| A02 | Decision records plus Haddock rule citations make the code understandable to the owner. `[ASSUMPTION]` agent proposal | medium | The owner read the decision records and the reference rules module on 2026-11-23. | P02 is not met, and the documentation style must change. | The owner reads the first decision record and the first rules module, then says what was unclear. | project owner | after first S1 story | confirmed 2026-11-23: the owner can read the rules and the code (#6) |
| A03 | ghcup with GHC 9.10 installs and builds on the headless server. `[ASSUMPTION]` agent proposal | medium | No Haskell tools were on the PATH on 2026-11-22. | The toolchain decision D10 changes (for example to nix or stack). | Install it and run `cabal build` and `cabal test` on a hello-world project with QuickCheck. | project owner | first task | confirmed: E01 installed GHC 9.10.1 through ghcup, and `cabal build all` and `cabal test all` pass on the server and in CI (`main` at `08bfd92`) |
| A04 | Random-play games end, by a win or the cap, within a few hundred plies. `[ASSUMPTION]` agent proposal | low | none | The ply cap and the playout bound need retuning. | Run 10,000 seeded playouts in S1 and look at the length distribution. | project owner | during S1 | untested |
| A05 | People other than the owner will install the game and play it. `[ASSUMPTION]` owner's belief | low | The owner said "anyone who installs this game"; no such person is named. | Only the owner plays. D23 and the phone layout still serve the owner, so S5 does not change. | Note whether anyone asks for or installs it; no test is planned. | project owner | none | untested |
| A06 | A phone on the owner's home network can reach the headless server when D20's option is on. `[ASSUMPTION]` agent proposal | medium | The owner says the server is on the same home network as the phone ("yes. this is assumption for now", 2026-11-24). It has not been tried; a firewall could still block it. The owner reaches the server today through an SSH tunnel from a laptop (README). | Phone play needs another route (a tunnel, or a different network setup), and D20 needs revisiting. | Start the server with the option and open it from the phone; this is part of the first S5 story. | project owner | first S5 story | untested |

| A07 | The `pylos-web` binary built on GitHub's ubuntu-24.04 runner starts on a clean Ubuntu 24.04 amd64 with only the libraries the `.deb` declares. `[ASSUMPTION]` agent proposal | medium | none; no packaged binary exists yet. Expected dynamic libraries are glibc, libgmp, likely libffi and libz (`cabal.project.freeze` builds `zlib` against the system library); confirm with `ldd` in the workflow. | The package does not start, or needs libraries it does not declare; D23's install promise fails. | In the release workflow, install the `.deb` in a clean `ubuntu:24.04` container, start `pylos-web`, fetch the page and one of its script files, and start a bot game through the API; the Release is published only when each request succeeds and a game event arrives. | project owner | before `v0.1.0` is published | untested |

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
| Q07 | Is there anyone specific expected to install and play the game? | No | project owner | open; asked 2026-11-24 and not answered. Affects only A05 and D23. |
| Q08 | How a raise and a take-back are entered on touch and on mouse, and what the phone layout looks like. | No; it is settled in the S5 spec, not in this brief. | S5 spec, with the owner's review | open |
| Q09 | How the installed `pylos-web` finds its web files, and whether the cabal version `0.1.0.0` becomes `0.1.0`. | No | project owner; S6 implementation | closed 2026-11-26: the web-file lookup is D26 (#44); the cabal version is now `0.1.0` and the release tag must match it (#45, ADR 0028), pending the owner's review in the PR. |

## Definition of Ready addendum (own)

P01–P03 and the target group (the owner alone) rest on the owner's direct account, within its scope.

Every rule and decision that Now relies on (R03–R08, D08–D14, N02–N04) is active, with the owner as decider. The rules come from the owner's memory. Their match with the official game is untested (A01). The owner sets the rules for this personal project, so that does not block the work. No blocking question is open.

Ready for (2026-11-22, now historical; S1–S4 are built): implementation planning of the toolchain, S1 and S2 (#5–#12). Issues #2, #7, #8 and #10 cite the superseded R01, R02 or N01, and #5–#12 all say they are not ready until the proposals are confirmed (#6 still lists D13 as a proposal). #8's criterion "every move from that square carries 1 or 2 take-backs" contradicts R07. Those issues need updating before implementation (`om-auto-manage-issues`). The brief itself is not the blocker.

**S5 refresh, 2026-11-24.** P04 rests on the owner's own account of what they want from playing the bots. The S5 user is the owner. The wider audience in Target group is the owner's choice, not evidence (A05), and S5 does not depend on it. Expected outcome and check: the S5 user outcome in Goals. Out of scope: the Later items in Scope and N05. D18–D22 and N05 are active, with the owner as decider. No blocking question is open: Q07 does not block, and Q08 belongs to the S5 spec. A06 rests on the owner's statement only and is checked by the first S5 story; the phone stories depend on it.

Ready for: a backlog for S5 (`om-backlog --dry-run`), and an S5 spec that works out the input design (Q08). Implementation touches protected surfaces: the web protocol (`docs/web-protocol.md`, a new `POST /api/games/:id/move`, a human player kind and the training-mode score in move events), the bot interface (a bot must also return its score for D22; `chooseMove` today returns only a move) and the 127.0.0.1 rule in `AGENTS.md` and ADR 0023, which N05 and D20 change to "127.0.0.1 by default".

**S6 refresh, 2026-11-26.** P05 rests on a repository fact (the README's build steps) and on the owner's request. Who besides the owner will install the package is unknown (A05); S6 does not depend on it, because the owner chose to publish it. Expected outcome and check: the S6 user outcome in Goals, checked by A07's test in the release workflow. Out of scope: the Later install items and the developer tools (D24). D23–D26 are active, with the owner as decider, confirmed on 2026-11-26. No blocking question is open; the rest of Q09 (the cabal version) belongs to the implementation.

Ready for: one implementation PR for S6. The release workflow pins `runs-on: ubuntu-24.04` (not `ubuntu-latest`, which `ci.yml` uses), so D23's reasoning about the C library holds when `latest` moves. It touches: CI (a new release workflow next to `.github/workflows/ci.yml`, with ADR 0024 or a new decision record), the README's Install section, the `pylos-web` default web folder (D26; `app/web/WebArgs.hs` with a test, `docs/technical.md` and the web-server ADR 0023), and the `pylos.cabal` version. The release itself (the `v0.1.0` tag) happens only after that PR is merged to `main`.

## Collection plan

No material is needed for the current decision. The rulebook comparison is A01's test, not a blocker, because the owner chose the rules.
