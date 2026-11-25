# Pylos rules

These are the rules this program plays. They are the owner's rules of Pylos,
written from memory. They have not yet been compared line by line with the
publisher's printed rulebook, so details may differ from the boxed game.

The rule ids in brackets (R03, R07, …) point to the rows in
`.ai/specs/product-brief.md`, which is the binding version. The code cites the
same ids.

## The board and the balls (R08)

- Two players, **White** and **Black**. Each starts with **15 balls** in their
  reserve.
- The balls are stacked into a pyramid of **30 squares on four levels**:

  | Level | Size | Squares |
  |---|---|---|
  | a (bottom, on the board) | 4 × 4 | 16 |
  | b | 3 × 3 | 9 |
  | c | 2 × 2 | 4 |
  | d (the apex) | 1 | 1 |

- A square on level b, c or d rests on the **4 squares directly beneath it**.
  You may put a ball there only when all four are occupied, by balls of either
  colour.
- White moves first. Players take turns.

## Your turn

On your turn you do exactly one of these two things:

1. **Place.** Take a ball from your reserve and put it on any empty square
   that is supported. On an empty board that means any of the 16 squares of
   level a.
2. **Raise** (R03). Instead of placing, move one of **your own free balls** that
   is already on the pyramid to an empty, supported square on a **higher
   level**. This saves a ball from your reserve.
   - A ball is **free** when no ball rests on it (R04).
   - The ball may not be one of the four balls supporting the square it moves
     to. Support is checked after the ball has left its old square.

## Shapes and taking balls back (R07)

When your move (a place or a raise) completes a **shape** in your own colour,
you may take back **0, 1 or 2** of your own free balls from the pyramid into
your reserve. A shape is:

- a **2 × 2 square** of your colour on level a, b or c, or
- a **full row of 4** of your colour on level a, horizontal or vertical.

Diagonal lines do not count, and rows on level b do not count.

You take the balls back one after the other (R04). Taking the first ball may
free a ball that was under it, and that ball may then be the second one. A
move takes back at most 2 balls, however many shapes it completes at once.

Taking balls back is the heart of the game: every ball you save is a ball your
opponent has to outlast.

## The end of the game (R05)

**The player to move with an empty reserve loses.** In practice the pyramid
fills up, and whoever places the last ball on the apex has just won, because
the opponent then has no balls left.

The rules themselves have no draw (R06). Because balls can be taken back,
positions can repeat, so a game in this program has a **ply cap** (300 half
moves by default). A game that reaches the cap is a **draw** (D12).

## How moves are written (D09)

The move list in the viewer, game records and the command-line tools all use
the same short notation.

- A **square** is `<level><row><column>`: `a11` is a corner of the board,
  `a44` the opposite corner, `b22` the centre of level b, `d11` the apex.
- A **place** is the square: `a23`.
- A **raise** is from–to: `a11-b22`.
- **Take-backs** follow an `x`: `a22 x a11 a12` places on a22 and takes back
  a11 and a12. `b13 x a34` takes back one ball.

## Example

```
1.  a22        a33
2.  a23        a32
3.  a12        a21
4.  a13 x a13  …
```

On move 4 White places a13 and completes the square a12–a13–a22–a23. White
takes the same ball straight back, so this turn cost White no ball at all.
Both players now have 12 balls in reserve, but it is Black who must spend
the next one.
