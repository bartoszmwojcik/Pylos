// rules.js — the legal moves of a position, in the browser, for human play.
//
// When the owner plays a bot (S5, D18), only legal choices may respond on the
// board. To know which clicks are legal the browser needs the legal moves of
// the shown position. This file computes them. It is a line-by-line port of
// the reference engine (reference/Pylos/Reference/Rules.hs): same function
// names, same rule ids (R03–R08, D08, from .ai/specs/product-brief.md), the
// same plain style and no speed tricks. The server is still the final judge:
// it checks every posted move again with its own engine (docs/web-protocol.md).
//
// A move here is a plain object
//   { kind: 'place' | 'raise', from: square | null, to: square, takeBack: [squares] }
// with takeBack sorted (see sortSquares), so that two moves that take back the
// same balls are written the same way (D08). moveText() turns it into D09
// notation, e.g. "a11-b22 x a13 a14". Positions are the protocol's JSON shape:
//   { squares: { a11: 'white', … }, whiteReserve, blackReserve, toMove }.
//
// The perft counts of these functions match golden/perft.json (see web/README.md).

import { ALL_SQUARES, parseSquare, supportsOf, shapesThrough } from './notation.js';

// ---------------------------------------------------------------------------
// Squares and balls

/**
 * The squares that rest on `sq`: the inverse of supportsOf. R08.
 * Used to decide whether a ball is free (R04).
 */
export function restingOn(sq) {
  return ALL_SQUARES.filter((q) => supportsOf(q).includes(sq));
}

/** Every support of `sq` holds a ball. Level a is always supported. R08. */
export function isSupported(squares, sq) {
  return supportsOf(sq).every((s) => squares[s]);
}

/** No ball on the square. A placement or a raise needs an empty target (R03, R08). */
export function isEmpty(squares, sq) {
  return !squares[sq];
}

/**
 * A ball is free when no ball rests on it. R04.
 * Only a free ball may be raised (R03) or taken back (R07).
 */
export function isFree(squares, sq) {
  return Boolean(squares[sq]) && restingOn(sq).every((q) => isEmpty(squares, q));
}

/** The free balls of one colour, in canonical order. R04. */
export function freeBallsOf(colour, squares) {
  return ALL_SQUARES.filter((sq) => squares[sq] === colour && isFree(squares, sq));
}

/**
 * Canonical square order: level, then row, then column — the order of the
 * reference engine's Pos. For names like "a11" … "d11" that is plain string
 * order, because each part is one character.
 */
export function sortSquares(list) {
  return [...list].sort();
}

// ---------------------------------------------------------------------------
// Shapes

/**
 * Does the ball just put on `sq` complete a shape of `colour`? R07, D14.
 * `squares` is the board after the action. `sq` was empty before, so any
 * complete shape through it is new. (shapesThrough in notation.js lists the
 * complete 2×2 squares on levels a–c and rows/columns of 4 on level a.)
 */
export function completesShape(colour, squares, sq) {
  return shapesThrough(squares, sq, colour).length > 0;
}

// ---------------------------------------------------------------------------
// Moves

/**
 * Every action the player to move can take, ignoring take-backs.
 *  * Place (R08): a reserve ball on any empty, supported square. Needs a ball
 *    in the reserve.
 *  * Raise (R03): one of the player's own free balls to an empty square on a
 *    strictly higher level, supported AFTER the ball has left its square. That
 *    is what forbids raising a ball onto a square it supports itself.
 * Returns [{ kind, from, to }].
 */
export function actions(position) {
  const b = position.squares;
  const me = position.toMove;
  const placements = reserveOf(me, position) > 0
    ? ALL_SQUARES.filter((sq) => isEmpty(b, sq) && isSupported(b, sq)).map((to) => ({ kind: 'place', from: null, to }))
    : [];
  const raises = [];
  for (const from of freeBallsOf(me, b)) {
    const without = { ...b };
    delete without[from];
    for (const to of ALL_SQUARES) {
      if (parseSquare(to).level > parseSquare(from).level && isEmpty(without, to) && isSupported(without, to)) {
        raises.push({ kind: 'raise', from, to });
      }
    }
  }
  return [...placements, ...raises];
}

/** The board after an action, before any take-back. R03. */
export function applyAction(colour, action, squares) {
  const after = { ...squares };
  if (action.kind === 'raise') delete after[action.from];
  after[action.to] = colour;
  return after;
}

/**
 * The take-back sets allowed after completing a shape. R07, R04, D08.
 * Nothing, one own free ball, or two. Two balls go one after the other (R04),
 * so the second only has to be free once the first is gone; a pair counts once
 * whichever order works (D08). The ball just moved is free, so it may be taken
 * back too. Returns sorted arrays, the empty one first.
 */
export function takeBackOptions(colour, squares) {
  const seen = new Map(); // "a11 a12" -> ['a11', 'a12'], to list each set once
  const add = (set) => seen.set(set.join(' '), set);
  add([]);
  for (const x of freeBallsOf(colour, squares)) {
    add([x]);
    const without = { ...squares };
    delete without[x];
    for (const y of freeBallsOf(colour, without)) if (y !== x) add(sortSquares([x, y]));
  }
  return [...seen.values()];
}

/**
 * All legal moves of the player to move, each once. D08.
 * An action that completes a shape (R07) comes with every take-back option,
 * including none; any other action comes with no take-back. A finished game
 * has no legal moves (R05).
 */
export function legalMoves(position) {
  if (isGameOver(position)) return [];
  const me = position.toMove;
  const moves = [];
  for (const a of actions(position)) {
    const after = applyAction(me, a, position.squares);
    const options = completesShape(me, after, a.to) ? takeBackOptions(me, after) : [[]];
    for (const takeBack of options) moves.push({ ...a, takeBack });
  }
  return moves;
}

/** A move in D09 notation: "a23", "a11-b22", "a22 x a11 a12". */
export function moveText(m) {
  const main = m.kind === 'raise' ? `${m.from}-${m.to}` : m.to;
  return m.takeBack.length ? `${main} x ${sortSquares(m.takeBack).join(' ')}` : main;
}

// ---------------------------------------------------------------------------
// End of the game

/** How many balls a player has not placed yet. */
export function reserveOf(colour, position) {
  return colour === 'white' ? position.whiteReserve : position.blackReserve;
}

/**
 * The winner, or null while the game goes on. R05: the player to move with
 * an empty reserve loses (placing the apex uses the last ball, so it ends the
 * game this way too). There is no draw rule (R06); the ply cap is outside the
 * rules (D12).
 */
export function winner(position) {
  if (reserveOf(position.toMove, position) === 0) return position.toMove === 'white' ? 'black' : 'white';
  return null;
}

/** The game is over when there is a winner. R05. */
export function isGameOver(position) {
  return winner(position) !== null;
}

// ---------------------------------------------------------------------------
// Entering a move step by step (the human's input; ADR 0027)
//
// On the board a move is entered in up to three steps:
//   1. the action: click an empty square to place, or click one of your free
//      balls (it is "selected") and then a higher square to raise it (R03);
//   2. if the action completes a shape (R07): click 0, 1 or 2 of your own
//      balls to take back, one at a time — each must be free at that moment
//      (R04);
//   3. confirm.
// A Draft records what has been chosen so far:
//   { selected: square | null, action: { kind, from, to } | null, takeBack: [squares in click order] }
// The functions below say, for a draft, which squares may be clicked next and
// what a click does. They only offer choices that lead to a legal move, so an
// illegal click does nothing. They are pure, so the app keeps no rules of its own.

export const emptyDraft = () => ({ selected: null, action: null, takeBack: [] });

const sameAction = (m, a) => m.kind === a.kind && m.from === a.from && m.to === a.to;

/** The legal moves that start with the draft's action. */
export function movesWithAction(legal, action) {
  return legal.filter((m) => sameAction(m, action));
}

/** Does the draft's action need a take-back choice (it completed a shape, R07)? */
export function needsTakeBack(legal, action) {
  return movesWithAction(legal, action).some((m) => m.takeBack.length > 0);
}

/**
 * What may be clicked now. Returns
 *   { targets: [squares], selectable: [squares] }
 * targets    — squares where a ball can go: empty squares to place on, or,
 *              with a ball selected, the squares it can be raised to;
 * selectable — balls that respond: own balls that can be raised (to select
 *              one, or click the selected one again to drop it), or in the
 *              take-back step the own balls that are free right now.
 */
export function choices(position, legal, draft) {
  const me = position.toMove;
  if (!draft.action) {
    const raisable = [...new Set(legal.filter((m) => m.kind === 'raise').map((m) => m.from))];
    if (draft.selected) {
      const to = legal.filter((m) => m.kind === 'raise' && m.from === draft.selected).map((m) => m.to);
      return { targets: [...new Set(to)], selectable: raisable };
    }
    const places = legal.filter((m) => m.kind === 'place').map((m) => m.to);
    return { targets: [...new Set(places)], selectable: raisable };
  }
  // Take-back step. The board is the one after the action, minus the balls
  // chosen so far. At most 2 (R07); the last chosen one can be clicked again
  // to put it back (it is the only one whose removal nothing else depends on).
  if (draft.takeBack.length >= 2) return { targets: [], selectable: [draft.takeBack[1]] };
  const board = applyAction(me, draft.action, position.squares);
  for (const sq of draft.takeBack) delete board[sq];
  const free = freeBallsOf(me, board);
  const last = draft.takeBack[draft.takeBack.length - 1];
  return { targets: [], selectable: last ? [...free, last] : free };
}

/**
 * The draft after clicking `sq`, or null when the click does nothing (it is
 * not one of choices()). The caller then checks isComplete().
 */
export function click(position, legal, draft, sq) {
  const { targets, selectable } = choices(position, legal, draft);
  if (!draft.action) {
    if (targets.includes(sq)) {
      const action = draft.selected
        ? { kind: 'raise', from: draft.selected, to: sq }
        : { kind: 'place', from: null, to: sq };
      return { selected: null, action, takeBack: [] };
    }
    if (selectable.includes(sq)) {
      // Click the selected ball again to drop it; click another to switch.
      return { ...draft, selected: draft.selected === sq ? null : sq };
    }
    return null;
  }
  if (!selectable.includes(sq)) return null;
  if (draft.takeBack.includes(sq)) return { ...draft, takeBack: draft.takeBack.filter((x) => x !== sq) };
  return { ...draft, takeBack: [...draft.takeBack, sq] };
}

/**
 * The finished move of a draft, or null while something is still to choose.
 * An action without a shape is complete at once. With a shape, the move is
 * complete when the player confirms (`confirmed`), with whatever 0–2 balls
 * they chose. The result is always one of `legal`.
 */
export function draftMove(legal, draft, confirmed) {
  if (!draft.action) return null;
  if (needsTakeBack(legal, draft.action) && !confirmed) return null;
  const want = sortSquares(draft.takeBack).join(' ');
  return movesWithAction(legal, draft.action).find((m) => m.takeBack.join(' ') === want) || null;
}
