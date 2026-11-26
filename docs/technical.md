# Pylos: technical description

This document is for developers. For what the project is and how to play, see
the [README](../README.md); for the game rules, see [rules.md](rules.md).

## How it is built

- **The reference engine** (`reference/`) is pure and readable Haskell. It is
  the oracle: every rule function cites the rule it implements (R03–R08, D08
  in `.ai/specs/product-brief.md`).
- **The bitboard engine** (`bitboard/`) implements the same rules with bit
  masks, for speed. It is checked against the reference on golden perft and
  playout values and on random positions.
- **The bots** (`bots/`) choose moves with the bitboard engine. Each bot has
  one knob (D15).
- **The web server** (`server/`, scotty + Server-Sent Events) runs games and
  serves the **browser viewer** (`web/`, plain JavaScript and vendored
  Three.js, no build step). The API and the event stream are described in
  [web-protocol.md](web-protocol.md); the viewer's files are described in
  [web/README.md](../web/README.md).
- **Decision records:** [docs/adr/](adr/) holds one record per non-obvious
  choice.

## Install details

The README has the short install. Notes:

- `cabal.project` pins `with-compiler: ghc-9.10.1` (D10), so cabal uses that
  version even if another GHC is the default.
- The first build downloads and compiles the dependencies (a few minutes).
- The exact dependency versions are frozen in `cabal.project.freeze`
  (ADR 0024).

### No libgmp-dev

If the build fails with `cannot find -lgmp`, the runtime library is installed
but the development link `libgmp.so` is not. Install `libgmp-dev`. If you
cannot use `sudo`, point the linker at a private symlink:

```sh
mkdir -p ~/.local/lib/pylos-gmp
ln -sf /usr/lib/x86_64-linux-gnu/libgmp.so.10 ~/.local/lib/pylos-gmp/libgmp.so
export LIBRARY_PATH="$HOME/.local/lib/pylos-gmp${LIBRARY_PATH:+:$LIBRARY_PATH}"   # add to ~/.bashrc
```

## Command-line tools

Moves use the notation of [rules.md](rules.md#how-moves-are-written-d09):
`a23` places a ball, `a11-b22` raises one, and `a22 x a11 a12` takes back
balls after completing a shape. Each move is one command-line argument, so
quote a move that contains spaces.

```sh
alias pylos-ref="$(cabal list-bin pylos-ref)"
alias pylos-bit="$(cabal list-bin pylos-bit)"

pylos-ref show a11 a12 a21 a22         # print the position after these moves
pylos-ref moves a11 a12 a21 a22        # list the legal moves there
pylos-ref perft 4                      # perft 1..4 from the start, with times
pylos-ref divide 3 a11                 # perft 2 below each reply to a11
pylos-ref playout 7 > game.json        # one random game (seed 7) as a JSON record
pylos-ref replay game.json             # replay and check a record
pylos-ref golden                       # regenerate golden/ (see below)

pylos-bit perft 6                      # the bitboard engine
pylos-bit bench 6                      # both engines: nodes per second and speed-up
pylos-bit compare 4 a11 a12            # find the first move where the engines differ
pylos-bit parity                       # check the bitboard engine against golden/
```

An illegal move makes any command exit non-zero and name the move, for example
`illegal move at ply 2: "b11"`.

## Tests

The validation gate, in order (also run by CI, `.github/workflows/ci.yml`):

```sh
cabal build all
cabal test all                 # about 30 s
node test/web-rules-perft.mjs  # about 1 s; Node 22
```

`cabal test all` runs one suite, grouped by backlog story:

| Group | Story | What |
|---|---|---|
| E01-S01 toolchain | #5 | one QuickCheck property, one HUnit test, the pinned GHC version |
| E02-S01 board | #7 | 30 squares, supports, rendering |
| E02-S02 moves | #8 | ball conservation, no floating balls, no duplicate moves, raises (R03), empty reserve loses (R05) |
| E02-S05 shapes | #15 | squares, rows, take-backs of 0–2, a ball freed by a take-back, diagonals and level-b rows are not shapes |
| E02-S03 notation | #9 | render/parse round trip, JSON record replay, parse errors |
| E02-S04 perft | #10 | 16 / 240 / 3360 / 43680, symmetry, bounded playouts |
| Golden files | #10, #12 | the reference reproduces `golden/`, the bitboard engine matches it |
| Bitboard engine | #11, #12 | same moves, same positions, same playouts as the reference; an injected bug is found |

Most of the 30 seconds is the reference engine recomputing the golden perft
values. Properties run over *reachable* positions, made by random legal play
from the start (`test/Gen.hs`).

`test/web-rules-perft.mjs` checks the browser's copy of the rules
(`web/rules.js`) against the golden perft counts.

To see a failing property, run the deliberate failure. It exits non-zero and
prints the counterexample:

```sh
PYLOS_DEMO_FAILURE=1 cabal test all
```

## Golden files

`golden/perft.json` and `golden/playouts.json` freeze what the reference
engine computes (D11). They hold perft for the start position (to depth 6) and
four mid-game positions, and the outcome of 200 seeded random games.
Regenerate them with `pylos-ref golden` **only** after an owner-approved rule
change, and explain the change in the PR (`CODE_REVIEW.md`,
`BACKWARD_COMPATIBILITY.md`).

## Match runner

`pylos-match` plays bots against each other without the browser:

```sh
$(cabal list-bin pylos-match) alphabeta:depth=3 mcts:iterations=1000 10 300 games/
```

This plays 10 games with alternating colours and a 300-ply cap (a capped game
is a draw), and writes each game to `games/` as a JSON record
(`pylos-ref replay games/game-1.json`).

## Web server

```
pylos-web [--lan] [PORT] [WEB_DIR]
```

- Without WEB_DIR it serves `./web` if that folder exists (a source
  checkout), else a `web` folder next to the executable (the unpacked
  `.tar.gz`), else `/usr/share/pylos/web` (the `.deb`). It prints the folder
  it serves, and stops with the list of folders it tried when none exists
  (D26, `resolveWebDir` in `app/web/WebArgs.hs`). An explicit WEB_DIR is used
  as given.
- Without `--lan` it listens on 127.0.0.1 only. With `--lan` it listens on
  0.0.0.0 and prints the LAN address (D20). There is no password; never
  forward the port to the internet (N05).
- `http://localhost:8080/?mock=1` runs the viewer against a built-in fake
  server in the browser, with no Haskell server needed for the game itself.
- The page and the browser files are sent with `Cache-Control: no-cache`.

## Releases

A release is a `.deb` for Ubuntu 24.04 amd64 and a `.tar.gz`, both holding
`pylos-web` and its web files, attached to a GitHub Release (D23, D24,
[ADR 0028](adr/0028-release-packages.md)).

To cut one:

1. Set `version:` in `pylos.cabal` (for example `0.1.0`) and merge to `main`.
2. Push the tag `v<version>` on that `main` commit:
   `git tag v0.1.0 && git push origin v0.1.0`.
3. `.github/workflows/release.yml` runs the validation gate, builds both
   files, installs and plays a game with each in a clean `ubuntu:24.04`
   container, and only then publishes the Release. If any step fails, nothing
   is published.

The same workflow, without publishing, runs on every pull request that
changes `packaging/`, the workflow, `pylos.cabal` or the cabal project files.
To build the files locally (needs `dpkg-dev`):

```sh
cabal build exe:pylos-web
packaging/build-packages.sh "$(cabal list-bin pylos-web)" 0.1.0 dist
```

## Layout

```
reference/Pylos/Reference/   the reference engine (library "pylos")
  Board.hs      squares, supports, positions, printing       R08
  Move.hs       the compound move                             D08
  Rules.hs      legal moves, shapes, take-backs, game end     R03-R08
  Notation.hs   a23, a11-b22, " x a23 a24"                    D09
  Record.hs     JSON game records                             D09
  Perft.hs      perft and divide                              D08
  Playout.hs    bounded random games                          D12
  Random.hs     the engine's own seeded random generator
  Symmetry.hs   the 8 board symmetries
  Golden.hs     what goes into golden/                        D11
bitboard/Pylos/              the bitboard engine (internal library "bitboard")
  Bitboard.hs   positions as two Word32 masks
  Compare.hs    engine-against-engine comparison (divide)
bots/Pylos/                  the bots and the match runner (internal library "bots")
server/Pylos/Server/         the live game server (internal library "server")
web/                         the browser viewer (plain JS + vendored Three.js)
packaging/                   release package scripts (ADR 0028)
app/                         pylos-ref, pylos-bit, pylos-match, pylos-web
test/                        the test suite
golden/                      frozen perft and playout values
docs/adr/                    decision records
docs/images/                 README screenshots
```
