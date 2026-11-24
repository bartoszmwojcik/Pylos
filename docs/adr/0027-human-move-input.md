# 0027. Entering a move with the mouse and by touch

## Status

Proposed. D18 (legal moves only, no undo) and D19 (phone and large screen may differ, mouse and touch) are the owner's decisions. Q08 asked how a raise and a take-back are entered; the brief left it to the S5 work, with the owner's review. Everything below is the agent's answer for E05-S03 (#33) and E05-S04 (#34). The owner reviews it in the PR.

## Context

A Pylos move has up to three parts (D08): an action (place a reserve ball, or raise one of your free balls, R03), and, if the action completed a shape (R07), a take-back of 0, 1 or 2 of your own free balls, one after the other (R04). The board is a 3D view that the player turns and zooms with the same mouse drags and finger gestures (OrbitControls). Four things needed a choice:

1. How the browser knows which choices are legal, so that only legal ones respond (D18).
2. How each part of a move is entered, the same way or differently for mouse and touch.
3. How a tap is told apart from a gesture that turns or zooms the view, so that no move is made by accident (#34).
4. Where the move controls go on a large screen and on a phone.

## Decision

**The browser computes the legal moves itself.** `web/rules.js` is a port of `reference/Pylos/Reference/Rules.hs`, function for function, with the rule ids in its comments. It lists the legal moves of the shown position. Small pure functions (`choices`, `click`, `draftMove`) say which squares may be clicked next and what a click does, so only choices that lead to a legal move respond. The server is still the judge: it checks the posted move again, and a refusal (HTTP 400) is shown with the server's own message. The port is checked against the golden perft counts (`web/README.md` has the command). Rejected: a server endpoint that lists the legal moves. It would add to the protocol, and every click would wait for the network. Also rejected: guessing from the R08 "placeable" squares in `notation.js`. That knows nothing about raises, free balls or shapes.

**One way to enter a move, the same for mouse and touch.** Only the words differ ("click" or "tap").

- **Place: one click on a marked square.** Every legal target square has a bright marker. A place that completes no shape is sent at once, without a confirm step. Most moves are places, and one click is what a player expects.
- **Raise: choose the ball, then the square.** Your balls that can be raised have a thin ring. Click one and it lifts a little. The markers then show only the squares it can go to (R03). Click a marker to raise it there. Click the lifted ball again (or Cancel, or Escape) to go back. Click another ringed ball to switch. With no ball lifted, a square is always a place; with a ball lifted, it is always a raise. So a square that could be both is never ambiguous. Rejected: drag and drop. A drag already turns the view, and dragging a small ball on a phone is fiddly. Also rejected: square first, then the ball. A first click on a square would then mean "place here" or "raise to here", and the player would have to say which.
- **Take-back: after the action, choose 0–2 balls, then confirm.** When the action completes a shape, the ball is shown on its new square and the shape is ringed. Your balls that are free right now have a thin ring. Click them one at a time. A chosen ball turns see-through, and the next choice is judged on the board without it, so a ball that the first choice freed can be chosen second (R04). After two balls, nothing else responds (R07). Click the last chosen ball to put it back. The confirm button says what will happen: "Take back nothing" or "Take back a11 and a12". "Cancel move" drops the whole move. The confirm step is always there, even for nothing, because choosing nothing is a decision too.
- **No undo (D18).** Until the move is sent, everything is a draft that can be changed or cancelled. Once it is sent, it is final. Input is only possible on the newest position. Stepping back through the moves drops the draft, and the play bar offers "Back to the game".

**A tap is a press that barely moves, with one pointer.** The board counts a press as a tap only if (a) the pointer moved less than 5 px (mouse) or 10 px (finger) from where it went down, and (b) no second pointer touched the screen during the press. A drag that turns the view moves further than that. A pinch uses two fingers. Neither can make a move, even if it starts or ends on a marker. Only the primary mouse button taps. What you see is what you click: the nearest ball or marker under the pointer wins. The invisible "hit" sphere round a marker (radius 0.3) is smaller than a ball (0.5). Seen from the side, an empty upper square hangs in front of the balls below it, and a ball-sized hit area there caught clicks meant for those balls; the browser test found this. With the mouse, the cursor turns into a hand over anything clickable, and the tooltip names the square. A ball hidden behind others is reached by turning the view, the Top camera, or the level filter.

**Layout.** The play bar (whose turn, what to do next, the take-back buttons, "bot is thinking", the result, the server's refusal) sits on the board.

- On a large screen it floats at the top of the board, under the camera and level controls, where it covers sky and not the plate's front row.
- On a phone (≤ 36rem wide) it sits right under the board, with buttons big enough for a thumb. The board takes `clamp(18rem, 46vh, 26rem)`. At 390×844 the top bar, the camera controls, the board, the play bar and the move transport fit on one screen without zooming. The new-game form stays below the game panel. After "Play", the page scrolls the board into view.

**The bot's turn.** The play bar says "<colour> (<bot spec>) is thinking…" with a blinking mark, and the board takes no input. A fast bot answers before the human's move has finished animating. So the moves of a human game are shown one after another: the bot's reply waits until the balls have landed, plus a short pause.

## Consequences

- There are now three implementations of the rules: the reference engine, the bitboard engine and `rules.js`. A wrong `rules.js` could hide a legal move from the player or offer an illegal one. The server would refuse the illegal one, but nothing in the browser would show the missing one. The perft check in `web/README.md` guards against this, but it is not part of `cabal test`, so CI does not run it.
- Places are sent on one click, so a mis-click is a played move, with no undo (D18). The tap rules, the smaller hit spheres, the hover cursor and the tooltip make it less likely. If it still happens in practice, a confirm step for places is a small change.
- There is no keyboard-only way to enter a move yet, apart from Escape (cancel) and Enter (confirm a take-back).
- Any browser that watches a human game while it waits can move for the human. There are no accounts (N05), and every browser is the owner's.

## Brief ids

Q08, D18, D19, D08, R03, R04, R07, R08, D14, N05
