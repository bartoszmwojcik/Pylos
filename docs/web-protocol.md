# Web protocol: server ↔ browser (S4, D16)

The Haskell server (`pylos-web`) serves the browser files from `web/` and a small JSON API under `/api`. Commands go **up** as plain HTTP requests. Game updates come **down** as Server-Sent Events (SSE). Human play (S5) will add one more command (`POST /api/games/:id/move`) and use the same event stream, so no second protocol is needed.

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
  "status": "running",
  "result": null,
  "plyCap": 300,
  "delayMs": 800,
  "moves": ["a11", "a12", "a11-b11 x b11"],
  "position": { "...": "Position, as above" }
}
```

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
| `POST /api/games` | `{"white": "<bot spec>", "black": "<bot spec>", "delayMs": 800, "plyCap": 300}` (`delayMs` and `plyCap` optional) | `201 {"id": "3"}`, or `400 {"error": "<message naming the bad spec>"}` |
| `GET /api/games/:id` | — | `GameSnapshot`, or `404 {"error": "no such game"}` |
| `GET /api/games/:id/events` | — | an SSE stream, see below |

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
