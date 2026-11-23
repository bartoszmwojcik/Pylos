# Pylos

A Pylos rules engine in Haskell, built to be understood.

- **The reference engine** (`reference/`) is pure and readable. It is the oracle: every rule function cites the rule it implements (R03–R08, D08 in `.ai/specs/product-brief.md`).
- **The bitboard engine** (`bitboard/`) implements the same rules with bit masks, for speed. It is trusted only because it matches the reference on golden perft and playout values and on random positions.
- **Why it is built this way:** `docs/adr/` holds one decision record per choice.

Bots and the browser viewer are later work (backlog E04).

## Install (Ubuntu, headless)

1. System libraries. GHC links against GMP:

   ```sh
   sudo apt install build-essential curl libffi-dev libgmp-dev libncurses-dev
   ```

   Without `sudo`, see [No libgmp-dev](#no-libgmp-dev) below.

2. The Haskell toolchain through ghcup, with the pinned compiler (D10):

   ```sh
   curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | sh
   source ~/.ghcup/env
   ghcup install ghc 9.10.1
   ghcup install cabal recommended
   cabal update
   ```

   `cabal.project` pins `with-compiler: ghc-9.10.1`, so cabal uses that version even if another GHC is the default.

3. Build and test:

   ```sh
   cabal build all
   cabal test all
   ```

   The first build downloads and compiles the dependencies (a few minutes). The test suite takes about 30 seconds. Most of that is the reference engine recomputing the golden perft values.

### No libgmp-dev

If the build fails with `cannot find -lgmp`, the runtime library is installed but the development link `libgmp.so` is not. Install `libgmp-dev`. If you cannot use `sudo`, point the linker at a private symlink:

```sh
mkdir -p ~/.local/lib/pylos-gmp
ln -sf /usr/lib/x86_64-linux-gnu/libgmp.so.10 ~/.local/lib/pylos-gmp/libgmp.so
export LIBRARY_PATH="$HOME/.local/lib/pylos-gmp${LIBRARY_PATH:+:$LIBRARY_PATH}"   # add to ~/.bashrc
```

## Using it

Moves are written as in D09: `a23` places a ball, `a11-b22` raises one, and `a22 x a11 a12` takes back balls after completing a shape. Each move is one command-line argument, so quote a move that contains spaces.

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

An illegal move makes any command exit non-zero and name the move, for example `illegal move at ply 2: "b11"`.

## What the tests check

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

Properties run over *reachable* positions, made by random legal play from the start (`test/Gen.hs`).

To see a failing property, run the deliberate failure. It exits non-zero and prints the counterexample:

```sh
PYLOS_DEMO_FAILURE=1 cabal test all
```

## Golden files

`golden/perft.json` and `golden/playouts.json` freeze what the reference engine computes (D11). They hold perft for the start position (to depth 6) and four mid-game positions, and the outcome of 200 seeded random games. Regenerate them with `pylos-ref golden` **only** after an owner-approved rule change, and explain the change in the PR (`CODE_REVIEW.md`, `BACKWARD_COMPATIBILITY.md`).

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
app/ref, app/bit             the pylos-ref and pylos-bit command lines
test/                        the test suite
golden/                      frozen perft and playout values
docs/adr/                    decision records
```
