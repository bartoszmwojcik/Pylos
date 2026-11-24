// mock.js — an in-browser fake of the Pylos web server, for ?mock=1.
//
// It provides `mockFetch` and `MockEventSource`, drop-in stand-ins for the
// browser's fetch and EventSource, implementing the endpoints and the event
// sequence of docs/web-protocol.md. app.js loads this file only in mock mode.
//
// The games are canned: the move lists below are random playouts produced by
// the reference engine (`pylos-ref playout 28` and `pylos-ref playout 5`), so
// every move is legal. Game 28 includes raises ("a31-b23", "b31-c22") and
// take-backs, among them a two-ball one ("a32 x a12 a32") and a ball taken
// back right after being placed ("a13 x a13"). The mock does not play Pylos
// itself: whatever bot specs you enter, a new game replays the seed-28 moves.

import { applyMove, startPosition } from './notation.js';

const CANNED = {
  seed28: {
    result: 'white',
    moves: [
      'a41', 'a34', 'a44', 'a23', 'a14', 'a12', 'a24', 'a33', 'a31', 'a43',
      'a31-b23', 'a13 x a13', 'a14-b33', 'a14', 'a13', 'a42', 'b13', 'a32 x a12 a32',
      'a31', 'a22', 'a32', 'b31', 'a12', 'b32', 'a11', 'a21', 'a11-b22', 'b31-c22',
      'a11', 'b31', 'b12 x b13', 'b11', 'b21', 'c21', 'b13 x b12', 'b12', 'c12',
      'c11', 'd11',
    ],
  },
  seed5: {
    result: 'white',
    moves: [
      'a33', 'a21', 'a34', 'a23', 'a12', 'a13', 'a44', 'a41', 'a14', 'a43',
      'a24 x a34', 'a34', 'a22', 'b13', 'a44-b23', 'a41-b12', 'a44', 'a32', 'b22',
      'a31', 'a41', 'c12', 'a42', 'b32', 'b33', 'b31', 'b21', 'c21', 'c22', 'a11',
      'b11', 'c11', 'd11',
    ],
  },
};

const BOTS = [
  { kind: 'random', example: 'random', help: 'Plays a uniformly random legal move.' },
  { kind: 'greedy', example: 'greedy:reserve=10,free=1', help: 'One-ply search; weights for reserve and free balls.' },
  { kind: 'alphabeta', example: 'alphabeta:depth=3', help: 'Alpha-beta search to a fixed depth (1-8).' },
  { kind: 'mcts', example: 'mcts:iterations=2000', help: 'Monte Carlo tree search (1-200000 iterations).' },
];

/** Check a bot spec like the server would; return an error message or null. */
function badSpec(side, spec) {
  if (typeof spec !== 'string' || spec.trim() === '') return `${side}: empty bot spec`;
  const [kind, knobs] = spec.split(':');
  if (!BOTS.some((b) => b.kind === kind)) return `${side}: unknown bot kind "${kind}" in spec "${spec}"`;
  if (knobs !== undefined && !/^[a-z]+=-?\d+(,[a-z]+=-?\d+)*$/.test(knobs)) {
    return `${side}: bad knobs in spec "${spec}" (expected knob=value[,knob=value])`;
  }
  return null;
}

// ---- the fake server's state ---------------------------------------------

const games = new Map(); // id -> game
let nextId = 1;

/** Start a game that replays `canned` with `delayMs` between plies. */
function startGame({ white, black, delayMs = 800, plyCap = 300 }, canned, { instant = false } = {}) {
  const game = {
    id: String(nextId++),
    white,
    black,
    status: 'running',
    result: null,
    plyCap,
    delayMs,
    moves: [],
    position: startPosition(),
    listeners: new Set(), // MockEventSource instances watching this game
  };
  games.set(game.id, game);

  const step = () => {
    if (game.status !== 'running') return;
    if (game.moves.length >= game.plyCap) return finish(game, 'capped');
    if (game.moves.length >= canned.moves.length) return finish(game, canned.result);
    const ev = applyMove(game.position, canned.moves[game.moves.length]);
    game.moves.push(ev.move);
    game.position = ev.position;
    broadcast(game, 'move', { ply: game.moves.length, ...ev });
    if (!instant) setTimeout(step, game.delayMs);
  };
  if (instant) {
    while (game.status === 'running') step();
  } else {
    setTimeout(step, game.delayMs);
  }
  return game;
}

function finish(game, result) {
  game.status = 'finished';
  game.result = result;
  broadcast(game, 'end', { result });
}

function broadcast(game, name, data) {
  for (const es of game.listeners) es._emit(name, data);
}

function snapshot(game) {
  const { id, white, black, status, result, plyCap, delayMs, moves, position } = game;
  return { id, white, black, status, result, plyCap, delayMs, moves: [...moves], position };
}

function summary(game) {
  const { moves, position, ...rest } = snapshot(game);
  return { ...rest, plies: moves.length };
}

// Two games exist when the page loads: one already finished, one running.
// `?mock=1&mockdelay=3000` slows the running game down (handy for screenshots).
const loadDelay = Number(new URLSearchParams(window.location.search).get('mockdelay')) || 900;
startGame({ white: 'greedy:reserve=10,free=1', black: 'random', delayMs: 0, plyCap: 300 }, CANNED.seed5, { instant: true });
startGame({ white: 'alphabeta:depth=3', black: 'mcts:iterations=2000', delayMs: loadDelay, plyCap: 300 }, CANNED.seed28);

// ---- fetch ----------------------------------------------------------------

function json(status, body) {
  return Promise.resolve(
    new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } }),
  );
}

/** A fake `fetch` serving the /api endpoints. */
export async function mockFetch(path, init = {}) {
  const method = (init.method || 'GET').toUpperCase();
  const url = new URL(path, window.location.href);
  const p = url.pathname;

  if (method === 'GET' && p === '/api/bots') return json(200, BOTS);
  if (method === 'GET' && p === '/api/games') {
    return json(200, [...games.values()].reverse().map(summary)); // newest first
  }
  if (method === 'POST' && p === '/api/games') {
    let body;
    try {
      body = JSON.parse(init.body);
    } catch {
      return json(400, { error: 'request body is not JSON' });
    }
    const err = badSpec('white', body.white) || badSpec('black', body.black);
    if (err) return json(400, { error: err });
    const game = startGame(
      {
        white: body.white,
        black: body.black,
        delayMs: Number.isFinite(body.delayMs) ? body.delayMs : 800,
        plyCap: Number.isFinite(body.plyCap) ? body.plyCap : 300,
      },
      CANNED.seed28,
    );
    return json(201, { id: game.id });
  }
  const m = p.match(/^\/api\/games\/([^/]+)$/);
  if (method === 'GET' && m) {
    const game = games.get(decodeURIComponent(m[1]));
    return game ? json(200, snapshot(game)) : json(404, { error: 'no such game' });
  }
  return json(404, { error: `mock: no route for ${method} ${p}` });
}

// ---- EventSource ------------------------------------------------------------

/** A fake EventSource for /api/games/:id/events. */
export class MockEventSource {
  constructor(path) {
    this.url = path;
    this.readyState = 0; // CONNECTING, as in the real EventSource
    this.onerror = null;
    this._handlers = new Map();
    const m = new URL(path, window.location.href).pathname.match(/^\/api\/games\/([^/]+)\/events$/);
    this._game = m ? games.get(decodeURIComponent(m[1])) : undefined;
    // Like the real server: send the snapshot right after connecting.
    setTimeout(() => {
      if (this.readyState === 2) return;
      if (!this._game) {
        this.readyState = 2;
        if (this.onerror) this.onerror(new Event('error'));
        return;
      }
      this.readyState = 1; // OPEN
      this._game.listeners.add(this);
      this._emit('snapshot', snapshot(this._game));
      // A finished game's stream stays open but has no more moves; the real
      // server sends no second "end" after the snapshot either.
    }, 0);
  }

  addEventListener(name, fn) {
    if (!this._handlers.has(name)) this._handlers.set(name, []);
    this._handlers.get(name).push(fn);
  }

  close() {
    this.readyState = 2; // CLOSED
    if (this._game) this._game.listeners.delete(this);
  }

  _emit(name, data) {
    if (this.readyState !== 1) return;
    // Real EventSource delivers MessageEvents whose .data is the raw text.
    const ev = new MessageEvent(name, { data: JSON.stringify(data) });
    for (const fn of this._handlers.get(name) || []) fn(ev);
  }
}
