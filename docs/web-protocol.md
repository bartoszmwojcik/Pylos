# Web protocol: server ↔ browser (S4, D16)

The Haskell server (`pylos-web`) serves the browser files from `web/` and a small JSON API under `/api`. Commands go **up** as plain HTTP requests. Game updates come **down** as Server-Sent Events (SSE). Human play (S5, D18) adds one command, `POST /api/games/:id/move`, and uses the same event stream, so there is no second protocol. See [Human play](#human-play-s5-d18) and `docs/adr/0025-human-play-protocol.md`. A human game can be a training game, whose stream also carries the bot's scores (D22). See [Training games](#training-games-s5-d22).

All squares use the D09 notation (`a11` … `d11`). Colours are `"white"` and `"black"`.

## Shared JSON shapes

**Position**

```json
{
  "squares": { "a11": "white", "a12": "black", "b11": "white" },
  "whiteReserve": 13,
  "blackReserve": 14,
  "toMove": "black"
}
```

`squares` lists occupied squares only.

**Game snapshot**

```json
{
  "id": "3",
  "white": "alphabeta:depth=3",
  "black": "mcts:iterations=2000",
  "human": null,
  "waitingFor": null,
  "status": "running",
  "result": null,
  "plyCap": 300,
  "delayMs": 800,
  "training": false,
  "moves": ["a11", "a12", "a11-b11 x b11"],
  "position": { "...": "Position, as above" },
  "score": null
}
```

- `white` and `black` are each side's player: a bot spec, or `"human"`.
- `human` is the colour the human plays (`"white"` or `"black"`), or `null` in a bot-vs-bot game.
- `waitingFor` is the human's colour while the game waits for the human's move. It is `null` otherwise: while the bot thinks, after the game ends, and always in a bot-vs-bot game.
- `status` is `"running"` or `"finished"`.
- `result` is `null` while running, then `"white"` or `"black"` (the winner), or `"capped"` (the ply cap was reached; the match runner counts it as a draw, D12).
- `training` is `true` in a training game (D22), `false` otherwise.
- `score` is the newest `PlyScore` of a training game (see [Training games](#training-games-s5-d22)), or `null`: always in a real game, and in a training game before the first score.

**Game summary** (in lists) is the snapshot without `moves`, `position` and `score`, plus `"plies": <number>`.

## HTTP endpoints

| Method and path | Body | Response |
|---|---|---|
| `GET /` | — | `web/index.html` |
| `GET /static/<file>` | — | a file from `web/` (e.g. `/static/app.js`, `/static/vendor/three.module.min.js`) |
| `GET /api/bots` | — | `[{"kind": "greedy", "example": "greedy:reserve=10,free=1", "help": "..."}]`, one entry per bot kind |
| `GET /api/games` | — | `[GameSummary]`, newest first |
| `POST /api/games` | `{"white": "<player>", "black": "<player>", "delayMs": 800, "plyCap": 300, "training": false}` (`delayMs`, `plyCap` and `training` optional). A player is a bot spec or `"human"`; at most one side is `"human"`. `"training": true` needs a human player. | `201 {"id": "3"}`, or `400 {"error": "<message naming the bad spec>"}` |
| `GET /api/games/:id` | — | `GameSnapshot`, or `404 {"error": "no such game"}` |
| `GET /api/games/:id/events` | — | an SSE stream, see below |
| `POST /api/games/:id/move` | `{"move": "<D09 move>"}`, e.g. `{"move": "a22 x a11"}` | `200` with the move's `move` event data, or `400 {"error": "..."}`, or `404 {"error": "no such game"}`. See [Human play](#human-play-s5-d18). |

A bot spec is `kind` or `kind:knob=value[,knob=value]`:

| Kind | Knobs | Example |
|---|---|---|
| `random` | none | `random` |
| `greedy` | `reserve`, `free` (evaluation weights, integers) | `greedy:reserve=10,free=1` |
| `alphabeta` | `depth` (1–8) | `alphabeta:depth=3` |
| `mcts` | `iterations` (1–200000) | `mcts:iterations=2000` |

## SSE stream `GET /api/games/:id/events`

Each event has a name (`event:`) and a JSON `data:` line.

1. `snapshot`: sent once, immediately on connect. Data: a `GameSnapshot`. A browser that reconnects simply gets a fresh snapshot.
2. `move`: one per ply. Data:

   ```json
   {
     "ply": 7,
     "move": "a22 x a11",
     "action": { "kind": "place", "from": null, "to": "a22" },
     "takeBack": ["a11"],
     "by": "white",
     "position": { "...": "Position after the move" }
   }
   ```

   `action.kind` is `"place"` or `"raise"`. For a raise, `from` is the origin square. `ply` is the 1-based number of this move in the game, so after the event the game has `ply` moves.
3. `score`: training games only (D22). Data: a `PlyScore`, the bot's score of the position after ply `ply`. See [Training games](#training-games-s5-d22).
4. `end`: once, when the game finishes. Data: `{"result": "white"}` (or `"black"` / `"capped"`).

The server keeps the stream open after `end`, so the browser should close it itself. A watcher that connects to a game that has already finished gets only the `snapshot`, with `status: "finished"`. `end` is not sent again.

Without an event for 15 seconds the server sends an SSE comment line (`: keep-alive`), which browsers ignore. Files under `/static/` are served with their content type (`.js` as `text/javascript`, which ES modules require).

## Human play (S5, D18)

A game with `"human"` as one player runs like any other, except that the game waits whenever the human is to move. One human plays one bot. Only legal moves are accepted, and there is no undo (D18).

- **Starting.** If the bot plays first (the human is `black`), it moves at once. Otherwise the game waits with `waitingFor` set to the human's colour.
- **Moving.** `POST /api/games/:id/move` with `{"move": "<text>"}`. The text is a move in D09 notation, written as in the snapshot's `moves` list: `a11`, `a11-b22`, `a22 x a11 a12`. The take-backs may come in any order.
  - A legal move on the human's turn is applied. The answer is `200` with the same data as the `move` event, which is also sent on the stream. The bot then thinks and sends its own `move` event. The POST does not wait for the bot.
  - Every refused move answers `400 {"error": "<message>"}` and leaves the game unchanged. A move is refused when the body is not `{"move": "<string>"}`, the text is not a move (`not a move: …`), the move is not legal in the position (`illegal move: "…"`), the bot is to move (`it is not your turn: …`), the game is over (`the game is over`), or no side is human (`this game has no human player`).
  - An unknown game is `404 {"error": "no such game"}`.
- **Pace.** `delayMs` paces bot-vs-bot games only. In a human game the bot replies as soon as it has chosen its move.
- **Reconnecting.** The `snapshot` has the moves so far and `waitingFor`. A browser that reconnects mid-game enables input when `waitingFor` is its colour.
- **The end.** A win, a loss or the ply cap (a draw, D12) sends `end` as in any game. The snapshot keeps `"human"` as that side's player.
- **Limits.** A game that waits for the human does not count against the limit of 8 running games when a new game starts, so abandoned games never block new ones. Separately, at most 8 bots think at the same time across all games. A bot whose turn comes while all 8 are busy waits for a free place, so its reply may come a little later, but no request is refused.

## Training games (S5, D22)

A game against a bot is either a real game or a training game. `POST /api/games` with `"training": true` starts a training game. The mode is fixed for the whole game (D22). `"training"` is optional and defaults to `false`. A training game needs a human player: `"training": true` in a bot-vs-bot game is `400 {"error": "training needs a human player (D22)"}`.

In a **real game** nothing changes: no `score` event is sent, the snapshot's `score` is `null`, and the bot only chooses its move. In a **training game** the bot also says how it scores the position, after every move, the human's and its own. The bot plays the same moves in both kinds of game: with the same seed, it plays the same game (ADR 0026).

**Score.** Every score is from **White's point of view**: a higher number is better for White, whoever the human plays (ADR 0026). One of:

```json
{ "kind": "eval", "value": 37, "decided": false }
{ "kind": "winRate", "value": 0.63 }
{ "kind": "none" }
```

- `eval`: greedy's evaluation of the position, or alpha-beta's search score at its depth. An integer. `decided` is `true` when the value is a won (`value >= winScore`) or lost (`value <= -winScore`) game for White. `winScore` is 1000000 (`Pylos.Bot.Eval`). Alpha-beta adds the plies it had left, so of two decided values the larger is the sooner win.
- `winRate`: MCTS, White's share of its random games through the move it chose, from 0 to 1 (a capped game counts as half). An evaluation and a win rate are different scales; label them differently.
- `none`: the bot has no score for this position. The previous score no longer applies, so the screen should clear it.

**PlyScore**, the data of a `score` event and the snapshot's `score`:

```json
{ "ply": 7, "score": { "kind": "eval", "value": 37, "decided": false } }
```

`ply` says which position is scored: the one after `ply` moves, so it matches the `ply` of a `move` event.

**When scores arrive.** Every ply gets exactly one `score` event, sent after that ply's `move` event:

| Bot | After the human's move | After the bot's move |
|---|---|---|
| `greedy` | `eval`: the evaluation of the position, at once | `eval`: the evaluation of the position after its move |
| `alphabeta` | `eval`: the root value of the bot's search, sent together with its reply | `eval`: its search score of the move, the same value |
| `mcts` | `none`, at once | `winRate` of the move it chose |
| `random` | `none`, at once | `none` |

The human's move is scored by the game, not by `POST /api/games/:id/move`. The POST answer stays the `move` event data and never waits for a search. Alpha-beta's score of the human's position comes from the same search that chooses its reply, so it arrives together with the reply's `move` event: `score` (ply N), `move` (ply N+1), `score` (ply N+1). Searching twice would show it sooner but double the bot's thinking time (ADR 0026, Server).

When the human's move ends the game, that position gets no `score` event; `end` follows. When the bot's move ends it, its `score` event comes before `end`.

**Reconnecting.** The snapshot's `score` is the newest `PlyScore`. Its `ply` is the snapshot's number of moves, or one less while alpha-beta is still searching after the human's move, and after a human move that ended the game. In a training game it is `null` only before the first score.
