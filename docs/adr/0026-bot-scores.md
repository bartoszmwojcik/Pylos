# 0026. Bots return a score with their move

## Status

Proposed. D22 (training mode, owner) is active. Which score each bot shows is an agent proposal in D22; the details below are implementation choices the owner reviews in the PR.

## Context

D22 adds a training game: after each move the screen shows how the bot scores the position. Greedy and alpha-beta show the shared evaluation (alpha-beta its search score), MCTS its win rate for the move it chose, and random shows nothing. Until now a bot only returned a move (`chooseMove`, ADR 0022). The bots must stay pure and deterministic: the same seed must give the same move whether or not the score is asked for (issue #35).

A score is shown at two moments:

1. After the bot's own move: the score of the position it moved into.
2. After the human's move: the score of the position the bot now faces, before it moves.

## Decision

In `bots/Pylos/Bot.hs`:

- `data BotScore = EvalScore Int | WinRate Double | NoScore`.
  - `EvalScore`: greedy's evaluation, or alpha-beta's search score.
  - `WinRate`: the share of MCTS's random games won through the chosen move, 0 to 1. A capped game counts as half (ADR 0022).
  - `NoScore`: random. MCTS too, for a position it did not search.
- `chooseMoveScored :: BotSpec -> Gen -> BPosition -> Maybe (BMove, Gen, BotScore)` returns the move, the next generator and the score of the position after the move.
- `chooseMove` keeps its type. It is now `chooseMoveScored` with the score dropped. There is only one code path, so the move and the generator are the same whether or not the score is used. Haskell is lazy, so a dropped score is never computed. A QuickCheck property checks this for every bot kind.
- `scorePosition :: BotSpec -> BPosition -> BotScore` scores a position without choosing a move. That is moment 2. It takes no generator, so it cannot change the bot's next move. Greedy gives the evaluation of the position. Alpha-beta gives its search score at its own depth, which is the same number `chooseMoveScored` then reports for its move (a test checks this). MCTS and random give `NoScore`. MCTS would need a search of its own to score a position, and D22 asks only for its win rate of the move it chose.
- `winScore` is re-exported, so a client can recognise a won or lost game.

**Point of view: every score is from White's side.** A higher number is better for White, whichever side the bot plays and whoever moves next. For a win rate, it is White's share of the games. So the screen shows one number whose meaning never changes during a game: it goes up when White does well. This is how chess programs usually show scores. Inside the search, scores stay "for the player to move" (negamax). Only the value handed out is turned round to White's side (`forWhite`).

Rejected: scores from the bot's side. "Good for the bot" is natural for a single number, but the human's colour changes between games, and for the score after the human's move the human must remember whose side the number is on. Rejected: scores from the side to move. The sign would then flip on every ply, so the number could not be read as a trend.

**Win scores.** A finished game evaluates to `-winScore` for the player to move (ADR 0022). Alpha-beta adds the plies it had left when it found the end, so a win found sooner scores higher. So, for White, `EvalScore s` with `s >= winScore` is a won game and `s <= -winScore` a lost one. Rendering that as "wins" is the client's choice.

Rejected: a separate scoring search inside `chooseMove` behind a flag. It would be a second code path that could drift from the move choice. Rejected: an `IO` or stateful score callback. The bots are pure (ADR 0022).

## Consequences

- The server can ask for the score only in a training game and ignore it in a real game. In both cases the bot plays the same move.
- `scorePosition` for alpha-beta costs one full search at the bot's depth. A training game against alpha-beta therefore searches about twice per bot turn: once to score the human's move and once to choose the reply. A real game does not pay this.
- An evaluation and a win rate are different scales. The screen must label them differently. Putting every bot on one scale is Later in the brief.
- The alpha-beta score is exact for the chosen move, not a bound. The first root move is searched with a full window, and a later move replaces it only when its score is inside the window.

## Brief ids

D22, D15, D12, R05. See ADR 0022 for how the bots work.

## Server

Added with the server part of issue #35. The protocol is in `docs/web-protocol.md`, section "Training games". The code is in `server/Pylos/Server/Games.hs` (`runGame`, `publishScore`) and `server/Pylos/Server/Json.hs` (`scoreJson`).

**The flag.** `POST /api/games` takes `"training": true|false`, default `false`. It is stored in the game's setup (`ngTraining`) and never changes (D22). The snapshot and the summary show it as `"training"`. `"training": true` without a human player is refused with a 400, not ignored. A training game exists to show the bot's score to a human. In a bot-vs-bot game the flag is a mistake in the request, and silently dropping it would hide that mistake.

**Real games stay clean.** In a real game the game thread calls `chooseMove` only, sends no `score` event, and the snapshot's `score` is `null`. In a training game it calls `chooseMoveScored`. Both use the same code path and the same generator (see Decision), so the bot plays the same moves. A test plays a real and a training game against each bot kind, with the same seed and a scripted human, and compares the moves.

**One event for every score.** Each scored ply gets its own `score` event, `{"ply": N, "score": ...}`, sent after that ply's `move` event. The snapshot carries the newest one in the same shape, so a browser that reconnects shows the same score.

Rejected: putting the score inside the `move` event. That works for the bot's moves, but not for the human's. The human's `move` event is the answer to the POST, and alpha-beta's score of that position is not known until its search ends. So the human's move would need a separate event anyway, and the browser would have two ways to receive a score. With one `score` event, the `move` event has the same shape in every game, and the client has one handler.

**Who scores the human's move.** The game thread does, never the POST handler. The POST stays as fast as in a real game: it checks the move and applies it.

- Greedy, MCTS and random: the thread calls `scorePosition` as soon as it wakes up for its turn, and sends the score before it starts thinking. Greedy's evaluation costs almost nothing; MCTS and random give `none`, which tells the browser to clear the old score.
- Alpha-beta: `scorePosition` would be a full search at the bot's depth, and choosing the reply is a second one with the same result. The search value of the chosen move *is* the root value of the position the bot faces (see Decision; a bot test checks it). So the thread searches once, with `chooseMoveScored`, and sends three events in one STM transaction: the human's ply's score, the reply's `move`, and the reply's score. The two scores are equal. The cost: against a deep alpha-beta, the score of the human's move appears only with the bot's reply. Halving the bot's thinking time is worth more than showing that number a little earlier.

Rejected: scoring the human's move in the POST handler. For alpha-beta it would block the request for a whole search, and the bot would then search again.

**State.** The game state keeps the newest score (`gsScore`), written by the same transaction that sends the `score` event. A watcher reads the snapshot and subscribes in one transaction (ADR 0025), so it never misses a score or gets one twice. `publish` now reads the state inside its transaction instead of being handed it, so a score written just before a move is not overwritten.

**Edge cases.** When the human's move ends the game, the thread ends it and sends no score for that position: there is no bot turn to score it in, and the `end` event says more than a score would. When the bot's move ends the game, its score is sent before `end`, so a won game shows as `decided`.
