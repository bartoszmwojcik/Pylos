# Pylos viewer: 3D design prototype

Source: `.ai/specs/product-brief.md`, scope S4 (the web viewer, a Later item;
D01, D02, D03, Q02). There is no S4 spec or backlog story yet.

The owner's direction (2026-11-23): 3D board views like the ones in hpylos
(sourceforge.net/projects/hpylos) are acceptable. The look should be cold and
metallic, with sans-serif fonts and slightly squarish shapes.

## Status

- Verification: passed for the scope listed below. Run in agent-browser
  v0.41.1 (headless Chrome, SwiftShader WebGL) at 1440, 820 and 390 px.
- Acceptance: **accepted** 2026-11-23 by the owner ("reviewed. please commit, push, merge"), version `4c3fb3f`. This accepts the visual direction only: Q02 (framework, live transport) stays open, and the brief is unchanged.
- The hpylos page could not be fetched during design (web fetch was blocked).
  The 3D look follows the owner's description only, not the hpylos screenshots.

## Screens

| ID | Screen | Requirements | States |
|---|---|---|---|
| `#s1` | Game library | S4, D09, N03 | records list, the live-match card, a broken record |
| `#s2` | Replay (representative) | R03, R04, R07, D08, D09 | place, raise (arc), shape rings, take-back ghosts, levels, cameras |
| `#s3` | Game over | R05, D12 | apex, empty reserve, capped (open the `cap60` record) |
| `#s4` | Live match | D02, D03, P01 | follows new plies; stepping back pauses following; Jump to live |
| `#s5` | Live: connection lost | P01 | reconnect countdown; earlier plies stay browsable |
| `#s6` | Record cannot be replayed | D09, D11 | board at the last legal ply; illegal move struck through |
| `#s7` | Library with no records | N03 | empty state with the command that makes a record |

## How it is built

- Portable HTML with ES modules. The review toolbar is the skill's unchanged
  `prototype.js`, `comments.js` and its CSS. The product UI is in `viewer.css`,
  scoped to `.pv-app`.
- `board3d.js`: three.js r170 (pinned, jsDelivr). The balls form a true square
  pyramid: a level rises by 2r/√2. The plate is a brushed, engraved steel slab
  with 16 drilled cups (owner feedback 2026-11-23: the painted holes did not look
  real). Each cup is a spherical recess concentric with a resting ball, its rim
  diameter is 0.83 of the ball's, so a level-a ball sinks in until its centre
  is √(r² − 0.416²) ≈ 0.28 above the surface.
  The balls are polished silver (White) and gunmetal (Black). Lighting is a cool
  key light plus a blue rim light. There are four camera presets, and the
  visible levels can be limited to A, A–B or A–C to look inside the pyramid.
- `pylos.js`: replays D09 notation for display only. It does not check legality.
- `games.js`: four real records produced by `pylos-ref playout` (seeds 1234, 42
  and 7, plus 7 capped at 60 plies). Their file names and dates are fictional.
- Fonts (proposal): Chakra Petch (UI labels), Barlow (text) and JetBrains Mono
  (notation), all pinned `@fontsource` files on jsDelivr.

## Simulated (not real)

- The live stream (`#s4`) gets a new ply every 2.4 s from a fixture. The real
  transport is undecided (Q02).
- The reconnect countdown and Retry (`#s5`) do nothing.
- Replay validation (`#s6`) uses a hand-edited fixture with a scripted message.
  The real server would run the reference engine's replay.

## Checks run (2026-11-23)

- Every screen loads with no console errors and five WebGL canvases.
- Replay: the transport buttons, slider, move list, Arrow, Home and End keys,
  camera presets, level filter and the hover tooltip (`b12 · White · level b`).
- Library → replay: the `cap60` row opens it in `#s2`, and its last ply shows "Capped … D12".
- Live: a step back pauses following while the match keeps advancing (5 → 25),
  and Jump to live returns to the newest ply and clears the bar.
- Layout at 1440, 820 and 390 px: no overflow, and status messages never cover the board.
- Not checked: the review-comment engine (unchanged scaffold), real GPUs or
  browsers other than Chromium, touch orbit, and screen reader output.

## Launch

From this directory: `python3 -m http.server 8000 --bind 127.0.0.1`, then
open `http://127.0.0.1:8000/index.html#s2`. It needs internet access for
three.js and the fonts. Browser comments stay in that origin's localStorage
until you export them.
