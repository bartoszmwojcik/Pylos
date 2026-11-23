# web/ — the browser viewer (S4)

Plain JavaScript ES modules, no build step. The Haskell server serves
`index.html` at `/` and every other file here under `/static/<path>`; the API
and the event stream are specified in `docs/web-protocol.md`.

| File | What it does |
|---|---|
| `index.html`, `style.css` | Page layout: new-game form and game list, 3D board, game panel. |
| `app.js` | Controller: form, game list (refreshed every 3 s), side panel, watching a game's event stream. |
| `api.js` | The only code that knows the URLs: JSON requests and the `EventSource` subscription. |
| `board.js` | The Three.js scene: board, balls, stacking geometry (explained at the top), markers, animations. |
| `notation.js` | Square names, supports (R08), D09 move parsing; `applyMove` is used only by the mock. |
| `mock.js` | An in-browser fake server, loaded only with `?mock=1`. It replays reference-engine playouts. |
| `vendor/` | Three.js r170 (`three.module.min.js`, `OrbitControls.js`, MIT licence in `THREE-LICENSE`). `OrbitControls.js` is patched in one line to import `./three.module.min.js` instead of `three`. |

URL parameters:

- `?mock=1`: use the fake server (no Haskell server needed). `&mockdelay=3000` slows its running game.
- `?game=ID`: watch that game on load. Without it, the newest running game is watched.
- `?slowmo=5`: play move animations five times slower.

To try it without the server, serve this directory so that `/` is `index.html` and
`/static/` maps here, then open `/?mock=1`.
