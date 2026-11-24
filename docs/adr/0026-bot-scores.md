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
