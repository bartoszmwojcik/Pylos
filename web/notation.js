// notation.js — the board geometry and the D09 move notation, in plain JS.
//
// This is the only place in the browser that knows how squares are named.
// It does NOT check whether a move is legal: the Haskell server is the
// authority on the rules. The viewer only needs to
//   * turn a square name like "b23" into (level, row, col),
//   * know which squares support which (R08), to draw "placeable" markers,
//   * split a move like "a11-b22 x a13 a14" into its parts,
//   * apply a move to a position (the mock server plays its canned games with
//     it, and the viewer rebuilds earlier positions for stepping back),
//   * and find the shapes (R07) a move completed, to draw rings and text.

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

// ---------------------------------------------------------------------------
// Display helpers for the viewer (ported from the accepted design prototype,
// .ai/prototypes/viewer-3d/pylos.js). Like applyMove they do NOT check
// legality; they only describe moves the server already played.
// ---------------------------------------------------------------------------

/** "white" -> "White". */
export const colourName = (colour) => colour[0].toUpperCase() + colour.slice(1);

/**
 * The shapes (R07) that the ball now on `sq` is part of, for `colour`:
 * a 2x2 square of that colour on level a, b or c, or a complete horizontal
 * or vertical row of 4 on level a. Returns [{ type: 'square'|'row'|'column',
 * squares: [4 names] }]. The viewer draws thin rings on these balls.
 */
export function shapesThrough(squares, sq, colour) {
  const { level, row, col } = parseSquare(sq);
  const n = sideOf(level);
  const mine = (name) => squares[name] === colour;
  const found = [];
  if (level <= 2) {
    // Every 2x2 block that contains (row, col): its top-left corner is at
    // (row-1 or row, col-1 or col), as long as the block fits on the level.
    for (let r = Math.max(1, row - 1); r <= Math.min(n - 1, row); r++) {
      for (let c = Math.max(1, col - 1); c <= Math.min(n - 1, col); c++) {
        const block = [squareName(level, r, c), squareName(level, r, c + 1), squareName(level, r + 1, c), squareName(level, r + 1, c + 1)];
        if (block.every(mine)) found.push({ type: 'square', squares: block });
      }
    }
  }
  if (level === 0) {
    const line = (f) => [1, 2, 3, 4].map(f);
    const across = line((c) => squareName(0, row, c));
    const down = line((r) => squareName(0, r, col));
    if (across.every(mine)) found.push({ type: 'row', squares: across });
    if (down.every(mine)) found.push({ type: 'column', squares: down });
  }
  return found;
}

/**
 * Every position of a game, from the start: history[0] is the empty board and
 * history[k] is the position after ply k. Each entry is
 *   { ply, position, move }   where move = null for ply 0, else
 *   { text, kind, from, to, takeBack, by, shapes }.
 * The server sends only the move texts and the CURRENT position, so the
 * earlier positions are rebuilt here with applyMove (display only).
 */
export function buildHistory(moveTexts) {
  const history = [{ ply: 0, position: startPosition(), move: null }];
  for (const text of moveTexts) history.push(nextEntry(history[history.length - 1], text));
  return history;
}

/** The history entry after playing `text` on `prev` (see buildHistory). */
export function nextEntry(prev, text) {
  const ev = applyMove(prev.position, text);
  // Shapes are judged on the board right after the ball lands, before the
  // take-backs (a ball taken back may itself have been part of the shape).
  const landed = { ...prev.position.squares, [ev.action.to]: ev.by };
  if (ev.action.from) delete landed[ev.action.from];
  return {
    ply: prev.ply + 1,
    position: ev.position,
    move: { text, ...ev.action, takeBack: ev.takeBack, by: ev.by, shapes: shapesThrough(landed, ev.action.to, ev.by) },
  };
}

/** One sentence about a move, e.g. "White raised a31 to b23, completing square a11–a22." */
export function describeMove(m) {
  if (!m) return 'Start position. White to move.';
  const who = colourName(m.by);
  let s = m.kind === 'raise' ? `${who} raised ${m.from} to ${m.to}` : `${who} placed ${m.to}`;
  if (m.shapes.length) {
    const names = m.shapes.map((x) => `${x.type} ${x.squares[0]}–${x.squares[3]}`);
    s += `, completing ${names.join(' and ')}`;
  }
  if (m.takeBack.length) s += `, and took back ${m.takeBack.join(' and ')}`;
  else if (m.shapes.length) s += ', and took nothing back';
  return `${s}.`;
}
