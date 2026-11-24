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
// back right after being placed ("a13 x a13"). A new bot-vs-bot game replays
// the seed-28 moves, whatever bot specs you enter.
//
// Human games (S5, D18) are played for real: with "human" as one player the
// mock checks each posted move with rules.js (the browser's copy of the
// reference rules) and answers with a uniformly random legal move, whatever
// the bot spec says, after `?mockthink=MS` milliseconds (default 600). It
// refuses moves with the server's messages (docs/web-protocol.md).

import { applyMove, parseMove, parseSquare, startPosition } from './notation.js';
import { legalMoves, moveText, winner } from './rules.js';

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
  { kind: 'alphabeta', example: 'alphabeta:depth=3', help: 'Alpha-beta search to a fixed depth (1-6).' },
  { kind: 'mcts', example: 'mcts:iterations=2000', help: 'Monte Carlo tree search (1-200000 iterations).' },
];

/** Check a player (bot spec or "human") like the server would; return an error message or null. */
function badSpec(side, spec) {
  if (spec === 'human') return null;
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
    human: null,
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

const query = new URLSearchParams(window.location.search);
const THINK_MS = Number(query.get('mockthink')) || 600;

/** Start a game between "human" and a (random-playing) bot. */
function startHumanGame({ white, black, plyCap = 300 }) {
  const game = {
    id: String(nextId++),
    white,
    black,
    human: white === 'human' ? 'white' : 'black',
    status: 'running',
    result: null,
    plyCap,
    delayMs: 800,
    moves: [],
    position: startPosition(),
    listeners: new Set(),
  };
  games.set(game.id, game);
  if (game.human === 'black') setTimeout(() => botMove(game), THINK_MS); // the bot opens
  return game;
}

/** Play a move (already known to be legal) and end the game if it is over. */
function play(game, text) {
  const ev = applyMove(game.position, text);
  game.moves.push(ev.move);
  game.position = ev.position;
  const data = { ply: game.moves.length, ...ev };
  broadcast(game, 'move', data);
  const won = winner(game.position); // R05
  if (won) finish(game, won);
  else if (game.moves.length >= game.plyCap) finish(game, 'capped'); // D12
  return data;
}

/** The mock's bot: a uniformly random legal move. */
function botMove(game) {
  if (game.status !== 'running' || game.position.toMove === game.human) return;
  const legal = legalMoves(game.position);
  play(game, moveText(legal[Math.floor(Math.random() * legal.length)]));
}

/** The human's POST /move, with the server's checks and messages. */
function postMove(game, body) {
  if (!body || typeof body.move !== 'string') return [400, { error: 'expected a JSON body {"move": "<D09 move>"}' }];
  if (!game.human) return [400, { error: 'this game has no human player' }];
  if (game.status !== 'running') return [400, { error: 'the game is over' }];
  if (game.position.toMove !== game.human) return [400, { error: `it is not your turn: ${game.position.toMove} (the bot) is to move` }];
  let text;
  try {
    const m = parseMove(body.move);
    [m.from, m.to, ...m.takeBack].filter(Boolean).forEach(parseSquare);
    text = moveText(m); // take-backs in canonical order, as legalMoves writes them
  } catch {
    return [400, { error: `not a move: ${JSON.stringify(body.move)}` }];
  }
  if (!legalMoves(game.position).some((m) => moveText(m) === text)) {
    return [400, { error: `illegal move: ${JSON.stringify(body.move)}` }];
  }
  const data = play(game, text);
  if (game.status === 'running') setTimeout(() => botMove(game), THINK_MS);
  return [200, data];
}

/** The game waits for the human while it runs and the human is to move. */
function waitingFor(game) {
  return game.human && game.status === 'running' && game.position.toMove === game.human ? game.human : null;
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
  const { id, white, black, human, status, result, plyCap, delayMs, moves, position } = game;
  return { id, white, black, human, waitingFor: waitingFor(game), status, result, plyCap, delayMs, moves: [...moves], position };
}

function summary(game) {
  const { moves, position, ...rest } = snapshot(game);
  return { ...rest, plies: moves.length };
}

// Two games exist when the page loads: one already finished, one running.
// `?mock=1&mockdelay=3000` slows the running game down (handy for screenshots).
const loadDelay = Number(query.get('mockdelay')) || 900;
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
    if (body.white === 'human' && body.black === 'human') return json(400, { error: 'at most one player may be human' });
    const plyCap = Number.isFinite(body.plyCap) ? body.plyCap : 300;
    if (body.white === 'human' || body.black === 'human') {
      return json(201, { id: startHumanGame({ white: body.white, black: body.black, plyCap }).id });
    }
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
  const mv = p.match(/^\/api\/games\/([^/]+)\/move$/);
  if (method === 'POST' && mv) {
    const game = games.get(decodeURIComponent(mv[1]));
    if (!game) return json(404, { error: 'no such game' });
    let body;
    try {
      body = JSON.parse(init.body);
    } catch {
      body = null;
    }
    return json(...postMove(game, body));
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
