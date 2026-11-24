# web/ — the browser viewer (S4) and play screen (S5)

Plain JavaScript ES modules, no build step. The Haskell server serves
`index.html` at `/` and every other file here under `/static/<path>`; the API
and the event stream are specified in `docs/web-protocol.md`. Nothing is
loaded from the internet at runtime: three.js and the fonts are in `vendor/`.

## Design source

The look is the owner-accepted 3D design prototype in
`.ai/prototypes/viewer-3d/` (accepted 2026-11-23, version `4c3fb3f`; read its
`README.md`): cold and metallic, sans-serif, slightly squarish. What was taken
from it:

| Prototype | Here |
|---|---|
| `board3d.js`: brushed, engraved steel plate with 16 drilled cups (rim diameter 0.83 of a ball, so a level-a ball's centre sits ≈ 0.28 above the plate), silver and gunmetal balls, cool key light + blue rim light, four camera presets, level filter, hover picking, ice ring / shape rings / ghosts / dashed raise arc | `board.js` (plus placeable markers and a take-back that waits for the move to land) |
| `pylos.js`: shapes of a move, move descriptions | `notation.js` (`shapesThrough`, `buildHistory`, `describeMove`) |
| `viewer.css` (the product UI) | `tokens.css` (its colour and font variables) and `style.css` |
| Fonts: Chakra Petch (UI labels), Barlow (text), JetBrains Mono (notation), `@fontsource` 5.1.0 | `fonts.css` + `vendor/fonts/` (latin woff2 files and their OFL licences) |
| Screens `#s3` game over, `#s4` live match, `#s5` connection lost | `app.js` |

Not taken, by decision D17 (live games only; replay is Later): the game-record
library, replaying record files, the broken-record and empty-library screens,
the Play button and speed selector of replay. The prototype's `tokens.css`,
`theme.css`, `components.css` and `screens.css` are the generic scaffold of
its review document, and `prototype.js`, `comments.js`, `prototype.css` are
the review toolbar; none of them is part of the viewer's look.

## Files

| File | What it does |
|---|---|
| `index.html` | Page structure: top bar, new-game form ("Bot vs bot" or "You vs bot") and game list, the board with its camera/level controls, play bar and transport bar, the game panel. |
| `fonts.css`, `tokens.css`, `style.css` | Fonts, design tokens, and the styles and responsive layout (wide three columns, mid ≤ 64rem, narrow ≤ 36rem). |
| `app.js` | Controller: form, game list (refreshed every 3 s), side panel, move list and stepping, following the live game, reconnecting; in a human game the move being entered, posting it, and the play bar. |
| `api.js` | The only code that knows the URLs: JSON requests and the `EventSource` subscription. |
| `board.js` | The Three.js scene: plate, cups, balls, stacking geometry (explained at the top), marks, animations, camera presets, level filter, hover, and for human play the input marks and taps (`setInput`, `onPick`). |
| `notation.js` | Square names, supports (R08), D09 move parsing, applying a move, shapes (R07), the position history, move descriptions. |
| `rules.js` | The legal moves of a position (a port of `reference/Pylos/Reference/Rules.hs`, R03–R08, D08), and the steps of entering a move: what may be clicked next and what a click does (ADR 0027). |
| `mock.js` | An in-browser fake server, loaded only with `?mock=1`. It replays reference-engine playouts, and plays human games with a random bot. |
| `vendor/` | Three.js r170: `three.module.min.js`, `OrbitControls.js`, `RoomEnvironment.js` (reflections for the metal), `RoundedBoxGeometry.js` (the plate body); MIT licence in `THREE-LICENSE`. The three add-ons are patched in one line to import `./three.module.min.js` instead of `three`. `fonts/`: the woff2 files and `OFL-*.txt`. |

## How watching works

- The board follows the newest ply. Click an earlier move, use the transport
  buttons, the slider, or the arrow keys (Home/End) while the board has focus:
  following pauses, the Live pill turns grey, and a "Jump to live" bar appears.
  New moves keep arriving in the move list meanwhile.
- Earlier positions are rebuilt in the browser from the move texts
  (`buildHistory`); the newest position is always the server's own.
- If the event stream breaks, the side panel shows "Connection to the server
  lost" with a countdown (5 s, then 10, 15 … up to 30 s) and Retry now. A retry
  first asks `GET /api/games/:id`: if the game still exists, a new stream gives
  a fresh snapshot that replaces everything; if the server answers 404 (it was
  restarted and forgot its games), the panel says so.
- When a game ends the panel shows the result and why: the apex was placed or
  the side to move had an empty reserve (R05), or the ply cap was reached (D12).

## How playing works (S5)

Choose **You vs bot** in the New game form, your colour and a bot spec, then
**Play**. The play bar on the board says what to do; the full design and its
reasons are in `docs/adr/0027-human-move-input.md` (Q08).

- **Place:** click (or tap) a square with a bright marker.
- **Raise (R03):** click one of your ringed balls (it lifts), then a marked
  higher square. Click the lifted ball again, Cancel or Escape to go back.
- **Take-back (R07):** if the move completes a shape, click 0, 1 or 2 of your
  ringed balls one at a time (only balls free at that moment respond, R04),
  then the confirm button ("Take back nothing", "Take back a11 and a12").
- Only legal choices respond, computed by `rules.js`; the server checks the
  move again and shows its reason if it refuses. A sent move is final (D18).
- On the bot's turn the play bar says the bot is thinking and the board takes
  no input. The bot's reply is shown after your move has finished animating.
- Drags (turn the view) and two-finger pinches (zoom) never make a move: a
  tap must move less than 5 px (mouse) or 10 px (finger), with one pointer.
- On a phone (≤ 36rem) the play bar sits under the board, with big buttons.

`rules.js` must agree with the reference engine. It was checked against the
golden perft counts (depth 1–3 of every position in `golden/perft.json`), with
Node 22 from the repository root:

```sh
node --input-type=module -e '
import { legalMoves, moveText } from "./web/rules.js";
import { applyMove, startPosition } from "./web/notation.js";
import fs from "node:fs";
const perft = (p, d) => d === 0 ? 1 : legalMoves(p).reduce((n, m) => n + perft(applyMove(p, moveText(m)).position, d - 1), 0);
for (const g of JSON.parse(fs.readFileSync("golden/perft.json", "utf8"))) {
  const p = g.moves.reduce((q, t) => applyMove(q, t).position, startPosition());
  console.log(g.name, [1, 2, 3].map((d) => perft(p, d) === g.perft[d - 1] ? "ok" : "MISMATCH"));
}'
```

## Training games (S5, D22)

Under **You vs bot**, **Game** chooses **Real** (the default) or **Training**.
The choice is sent as `"training"` when the game starts and cannot change
during the game (D22). The play bar's title line says which kind of game it
is ("Real game" or "Training"); so do the players panel and the game list.

In a training game the play bar has a score strip under the instructions: the
bot's score of the position after the ply on the board, always from White's
point of view (`docs/web-protocol.md`, "Training games"; ADR 0026).

- `eval` (greedy, alpha-beta): "Bot's evaluation for White", a signed number
  (`+37`, `−12`, `0`). A won or lost game shows "decided: White wins" or
  "decided: Black wins" instead of the large number.
- `winRate` (MCTS): "White's win rate · MCTS", a percentage with a bar. It is
  a different scale from an evaluation, so it has its own label and the only
  meter.
- `none`: "Random has no score", or, for MCTS after your move, "No score for
  this position".

Every score that arrives is kept by ply, so stepping back with the transport
shows that ply's score. A reconnect (or a page reload) gets only the newest
score from the snapshot; older plies then say "Not known". Against alpha-beta
the score of your move arrives together with its reply (it comes from the same
search), so until then the strip says alpha-beta is scoring. A real game shows
no score at all.

The mock (`?mock=1`) supports training games too. Its bot still plays random
moves, but it sends score events in the server's order for the bot kind you
typed, with made-up values (ten times White's reserve lead).

## URL parameters

- `?mock=1`: use the fake server (no Haskell server needed). `&mockdelay=3000` slows its running game; `&mockthink=2000` makes its bot think 2 s in a human game (default 600 ms).
- `?play=1`: open the New game form on "You vs bot". `&training=1` preselects Training.
- `?debug=1`: expose `window.pylosDebug` (the board view, for `screenPoint` and `squareAt`, and the input state) for browser tests.
- `?game=ID`: watch that game on load. Without it, the newest running game is watched.
- `?slowmo=5`: play move animations five times slower.

To try it without the server, serve this directory so that `/` is `index.html` and
`/static/` maps here, then open `/?mock=1`.
