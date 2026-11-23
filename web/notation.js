// notation.js — the board geometry and the D09 move notation, in plain JS.
//
// This is the only place in the browser that knows how squares are named.
// It does NOT check whether a move is legal: the Haskell server is the
// authority on the rules. The viewer only needs to
//   * turn a square name like "b23" into (level, row, col),
//   * know which squares support which (R08), to draw "placeable" markers,
//   * split a move like "a11-b22 x a13 a14" into its parts,
//   * and (for the mock server only) apply a move to a position.

// Levels a..d. Level index 0 is the 4x4 bottom, 3 is the single apex (R08).
export const LEVELS = ['a', 'b', 'c', 'd'];

/** Number of squares per side on a level: a=4, b=3, c=2, d=1. */
export function sideOf(level) {
  return 4 - level;
}

/** Build a square name from its parts: (1, 2, 3) -> "b23". */
export function squareName(level, row, col) {
  return `${LEVELS[level]}${row}${col}`;
}

/** Parse "b23" -> { level: 1, row: 2, col: 3 }. Rows and columns start at 1. */
export function parseSquare(name) {
  const level = LEVELS.indexOf(name[0]);
  const row = Number(name[1]);
  const col = Number(name[2]);
  if (level < 0 || !(row >= 1 && row <= sideOf(level)) || !(col >= 1 && col <= sideOf(level))) {
    throw new Error(`bad square: ${name}`);
  }
  return { level, row, col };
}

/** All 30 squares, bottom level first: a11 … a44, b11 … b33, c11 … c22, d11. */
export const ALL_SQUARES = (() => {
  const out = [];
  for (let level = 0; level < 4; level++) {
    for (let row = 1; row <= sideOf(level); row++) {
      for (let col = 1; col <= sideOf(level); col++) out.push(squareName(level, row, col));
    }
  }
  return out;
})();

/**
 * The four squares a square rests on (R08): square (r,c) on a higher level
 * sits in the hollow between (r,c), (r,c+1), (r+1,c), (r+1,c+1) one level
 * down. Level-a squares rest on the board, so they have no supports.
 */
export function supportsOf(name) {
  const { level, row, col } = parseSquare(name);
  if (level === 0) return [];
  const below = level - 1;
  return [
    squareName(below, row, col),
    squareName(below, row, col + 1),
    squareName(below, row + 1, col),
    squareName(below, row + 1, col + 1),
  ];
}

/**
 * Squares where a ball could go right now: empty, and every support occupied.
 * (This is the "usable square" part of R08 only; it ignores whose turn it is.)
 * `squares` is the protocol's map of occupied squares, e.g. { a11: "white" }.
 */
export function placeableSquares(squares) {
  return ALL_SQUARES.filter(
    (sq) => !squares[sq] && supportsOf(sq).every((s) => squares[s]),
  );
}

/**
 * Split a D09 move into its parts.
 *   "a23"              -> { kind: "place", from: null,  to: "a23", takeBack: [] }
 *   "a11-b22"          -> { kind: "raise", from: "a11", to: "b22", takeBack: [] }
 *   "a22 x a11 a12"    -> { kind: "place", from: null,  to: "a22", takeBack: ["a11", "a12"] }
 */
export function parseMove(text) {
  const [main, takes = ''] = text.trim().split(/\s+x\s+/);
  const takeBack = takes.split(/\s+/).filter(Boolean);
  if (main.includes('-')) {
    const [from, to] = main.split('-');
    return { kind: 'raise', from, to, takeBack };
  }
  return { kind: 'place', from: null, to: main, takeBack };
}

export function otherColour(colour) {
  return colour === 'white' ? 'black' : 'white';
}

/** The position before any move: empty board, 15 balls each, White starts. */
export function startPosition() {
  return { squares: {}, whiteReserve: 15, blackReserve: 15, toMove: 'white' };
}

/**
 * Apply a move to a position WITHOUT checking legality (used by the mock
 * server, which replays a game the reference engine already produced).
 * Returns the same shape as the protocol's "move" event, minus "ply".
 */
export function applyMove(position, text) {
  const m = parseMove(text);
  const by = position.toMove;
  const squares = { ...position.squares };
  const reserveKey = by === 'white' ? 'whiteReserve' : 'blackReserve';
  let reserve = position[reserveKey];

  if (m.kind === 'raise') {
    delete squares[m.from]; // a raise moves a ball already on the board…
  } else {
    reserve -= 1; // …a place takes one from the reserve.
  }
  squares[m.to] = by;
  for (const sq of m.takeBack) {
    // Take-backs (R07) return the mover's own free balls to their reserve.
    delete squares[sq];
    reserve += 1;
  }
  return {
    move: text,
    action: { kind: m.kind, from: m.from, to: m.to },
    takeBack: m.takeBack,
    by,
    position: { ...position, squares, [reserveKey]: reserve, toMove: otherColour(by) },
  };
}
