# Web protocol: server ↔ browser (S4, D16)

The Haskell server (`pylos-web`) serves the browser files from `web/` and a small JSON API under `/api`. Commands go **up** as plain HTTP requests. Game updates come **down** as Server-Sent Events (SSE). Human play (S5, D18) adds one command, `POST /api/games/:id/move`, and uses the same event stream, so there is no second protocol. See [Human play](#human-play-s5-d18) and `docs/adr/0025-human-play-protocol.md`.

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
  "moves": ["a11", "a12", "a11-b11 x b11"],
  "position": { "...": "Position, as above" }
}
```

- `white` and `black` are each side's player: a bot spec, or `"human"`.
- `human` is the colour the human plays (`"white"` or `"black"`), or `null` in a bot-vs-bot game.
- `waitingFor` is the human's colour while the game waits for the human's move. It is `null` otherwise: while the bot thinks, after the game ends, and always in a bot-vs-bot game.
- `status` is `"running"` or `"finished"`.
- `result` is `null` while running, then `"white"` or `"black"` (the winner), or `"capped"` (the ply cap was reached; the match runner counts it as a draw, D12).

**Game summary** (in lists) is the snapshot without `moves` and `position`, plus `"plies": <number>`.

## HTTP endpoints

| Method and path | Body | Response |
|---|---|---|
| `GET /` | — | `web/index.html` |
| `GET /static/<file>` | — | a file from `web/` (e.g. `/static/app.js`, `/static/vendor/three.module.min.js`) |
| `GET /api/bots` | — | `[{"kind": "greedy", "example": "greedy:reserve=10,free=1", "help": "..."}]`, one entry per bot kind |
| `GET /api/games` | — | `[GameSummary]`, newest first |
| `POST /api/games` | `{"white": "<player>", "black": "<player>", "delayMs": 800, "plyCap": 300}` (`delayMs` and `plyCap` optional). A player is a bot spec or `"human"`; at most one side is `"human"`. | `201 {"id": "3"}`, or `400 {"error": "<message naming the bad spec>"}` |
| `GET /api/games/:id` | — | `GameSnapshot`, or `404 {"error": "no such game"}` |
| `GET /api/games/:id/events` | — | an SSE stream, see below |
| `POST /api/games/:id/move` | `{"move": "<D09 move>"}`, e.g. `{"move": "a22 x a11"}` | `200` with the move's `move` event data, or `400 {"error": "..."}`, or `404 {"error": "no such game"}`. See [Human play](#human-play-s5-d18). |

A bot spec is `kind` or `kind:knob=value[,knob=value]`:

| Kind | Knobs | Example |
|---|---|---|
| `random` | none | `random` |
| `greedy` | `reserve`, `free` (evaluation weights, integers) | `greedy:reserve=10,free=1` |
| `alphabeta` | `depth` (1–6) | `alphabeta:depth=3` |
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
3. `end`: once, when the game finishes. Data: `{"result": "white"}` (or `"black"` / `"capped"`).

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
- **Limit.** A game that waits for the human does not count against the limit of 8 running games, so abandoned games never block new ones.
