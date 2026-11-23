// Display-only replay of D09 notation for the prototype.
// It applies recorded moves; it does NOT check legality. In the product the
// Haskell backend replays and validates the record (pylos-ref replay) and the
// browser only draws positions it is sent.

export const LEVELS = ['a', 'b', 'c', 'd'];

export function squareOf(id) {
  return { id, level: LEVELS.indexOf(id[0]), row: +id[1], col: +id[2] };
}

export function allSquares() {
  const out = [];
  LEVELS.forEach((l, li) => {
    const n = 4 - li;
    for (let r = 1; r <= n; r++) for (let c = 1; c <= n; c++) out.push(`${l}${r}${c}`);
  });
  return out;
}

export function parseMove(text) {
  const [action, takes] = text.split(' x ');
  const takeBacks = takes ? takes.trim().split(/\s+/) : [];
  if (action.includes('-')) {
    const [from, to] = action.split('-');
    return { kind: 'raise', from, to, takeBacks, text };
  }
  return { kind: 'place', to: action.trim(), takeBacks, text };
}

// Shapes of R07: 2x2 squares on levels a-c, full rows/columns of 4 on level a.
function shapesThrough(board, id, colour) {
  const s = squareOf(id);
  const L = LEVELS[s.level];
  const n = 4 - s.level;
  const found = [];
  const mine = (k) => board[k] === colour;
  if (s.level <= 2) {
    for (let r = Math.max(1, s.row - 1); r <= Math.min(n - 1, s.row); r++)
      for (let c = Math.max(1, s.col - 1); c <= Math.min(n - 1, s.col); c++) {
        const ks = [`${L}${r}${c}`, `${L}${r}${c + 1}`, `${L}${r + 1}${c}`, `${L}${r + 1}${c + 1}`];
        if (ks.every(mine)) found.push({ type: 'square', squares: ks });
      }
  }
  if (s.level === 0) {
    const row = [1, 2, 3, 4].map((c) => `a${s.row}${c}`);
    const col = [1, 2, 3, 4].map((r) => `a${r}${s.col}`);
    if (row.every(mine)) found.push({ type: 'row', squares: row });
    if (col.every(mine)) found.push({ type: 'column', squares: col });
  }
  return found;
}

// Returns one snapshot per ply (index 0 = start position).
export function replay(record) {
  const snaps = [];
  let board = {};
  const reserve = { W: 15, B: 15 };
  let toMove = 'W';
  snaps.push({ ply: 0, board: { ...board }, reserve: { ...reserve }, toMove, move: null });
  record.moves.forEach((text, i) => {
    const m = parseMove(text);
    const colour = toMove;
    board = { ...board };
    if (m.kind === 'raise') delete board[m.from];
    else reserve[colour] -= 1;
    board[m.to] = colour;
    const shapes = shapesThrough(board, m.to, colour);
    m.takeBacks.forEach((k) => { delete board[k]; reserve[colour] += 1; });
    toMove = colour === 'W' ? 'B' : 'W';
    snaps.push({ ply: i + 1, board, reserve: { ...reserve }, toMove, move: { ...m, colour, shapes } });
  });
  return snaps;
}

export function endReason(record, snaps) {
  const last = snaps[snaps.length - 1];
  if (record.result === 'capped') return { code: 'capped', text: `Stopped at the ply cap (${record.plies} plies)`, rule: 'D12' };
  if (last.board.d11) return { code: 'apex', text: `${colourName(last.move.colour)} placed the apex; ${colourName(last.toMove)} has no ball left`, rule: 'R05' };
  return { code: 'reserve', text: `${colourName(last.toMove)} has an empty reserve on their turn`, rule: 'R05' };
}

export const colourName = (c) => (c === 'W' ? 'White' : 'Black');

export function describeMove(m) {
  if (!m) return 'Start position. White to move.';
  const who = colourName(m.colour);
  let s = m.kind === 'raise' ? `${who} raised ${m.from} to ${m.to}` : `${who} placed ${m.to}`;
  if (m.shapes.length) {
    const names = m.shapes.map((x) => (x.type === 'square' ? `square ${x.squares[0]}–${x.squares[3]}` : `${x.type} ${x.squares[0]}–${x.squares[3]}`));
    s += `, completing ${names.join(' and ')}`;
  }
  if (m.takeBacks.length) s += `, and took back ${m.takeBacks.join(' and ')}`;
  else if (m.shapes.length) s += ', and took nothing back';
  return s + '.';
}
