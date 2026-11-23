// app.js — the page's controller: the new-game form, the game list, the side
// panel, and the live event stream that drives the 3D board.
//
// State flows one way: the server (or the mock) sends a snapshot or a move,
// we store it in `game`, then redraw the panel and the board from `game`.

import { createApi, ApiError } from './api.js';
import { BoardView } from './board.js';
import { parseMove, otherColour } from './notation.js';

const params = new URLSearchParams(window.location.search);
const MOCK = params.get('mock') === '1';
const LIST_REFRESH_MS = 3000;

/** Tiny DOM helper: el('li', { className: 'x', onclick }, 'text', childNode). */
function el(tag, props = {}, ...children) {
  const node = Object.assign(document.createElement(tag), props);
  for (const c of children) node.append(c);
  return node;
}

const $ = (id) => document.getElementById(id);

const RESULT_TEXT = { white: 'White wins', black: 'Black wins', capped: 'Draw (ply cap)' };
const cap = (s) => s[0].toUpperCase() + s.slice(1);

/** A ball icon (a coloured dot) for the panel. */
const dot = (colour) => el('span', { className: `dot ${colour}`, title: colour });

/**
 * Rebuild the protocol's move-event shape from a move's text, for the last
 * move of a snapshot (so the board can highlight it). The mover is the side
 * NOT to move now.
 */
function lastMoveOf(game) {
  const text = game.moves[game.moves.length - 1];
  if (!text) return null;
  const m = parseMove(text);
  return { action: { kind: m.kind, from: m.from, to: m.to }, takeBack: m.takeBack, by: otherColour(game.position.toMove) };
}

async function main() {
  // In mock mode, swap fetch/EventSource for the in-browser fake server.
  let deps = {};
  if (MOCK) {
    const mock = await import('./mock.js');
    deps = { fetch: mock.mockFetch, EventSource: mock.MockEventSource };
    $('mock-badge').hidden = false;
  }
  const api = createApi(deps);
  const board = new BoardView($('board'));

  let game = null; // the GameSnapshot being watched, kept up to date by events
  let stopWatching = () => {};
  let connection = ''; // shown under the players: '', 'connecting…', 'reconnecting…'

  // ---- watching a game ------------------------------------------------------

  function watch(id) {
    stopWatching(); // close the previous game's stream first
    game = null;
    connection = 'connecting…';
    renderPanel();

    const url = new URL(window.location.href);
    url.searchParams.set('game', id);
    window.history.replaceState(null, '', url);

    let stop = () => {};
    stop = api.watchGame(id, {
      onSnapshot(snap) {
        // Sent on every (re)connect: it replaces whatever we had.
        game = snap;
        connection = '';
        board.setPosition(game.position, lastMoveOf(game), false);
        if (game.status === 'finished') stop(); // no more events will come
        renderPanel();
        renderList();
      },
      onMove(ev) {
        if (!game) return;
        game.moves.push(ev.move);
        game.position = ev.position;
        board.setPosition(ev.position, ev, true);
        renderPanel();
      },
      onEnd({ result }) {
        if (!game) return;
        game.status = 'finished';
        game.result = result;
        renderPanel();
        refreshList();
      },
      onError() {
        if (game && game.status === 'finished') return;
        connection = 'reconnecting…';
        renderPanel();
      },
    });
    stopWatching = () => stop();
    renderList();
  }

  // ---- side panel -------------------------------------------------------------

  function renderPanel() {
    const panel = $('panel');
    panel.replaceChildren();
    if (!game) {
      panel.append(el('p', { className: 'muted' }, connection || 'Start a game or pick one from the list.'));
      return;
    }
    const pos = game.position;
    const reserveRow = (colour, n) =>
      el('div', { className: 'reserve' }, dot(colour), el('b', {}, `${cap(colour)} `),
        el('span', { className: 'muted' }, `${n} in reserve `),
        el('span', { className: 'balls' }, ...Array.from({ length: n }, () => dot(colour))));

    const status =
      game.status === 'finished'
        ? el('div', { className: 'result', id: 'result' }, RESULT_TEXT[game.result] || `Finished: ${game.result}`)
        : el('div', { className: 'turn' }, dot(pos.toMove), `${cap(pos.toMove)} to move`);

    panel.append(
      el('h2', {}, `Game ${game.id}`),
      el('div', { className: 'player' }, dot('white'), el('b', {}, 'White: '), el('code', {}, game.white)),
      el('div', { className: 'player' }, dot('black'), el('b', {}, 'Black: '), el('code', {}, game.black)),
      connection ? el('div', { className: 'muted' }, connection) : '',
      reserveRow('white', pos.whiteReserve),
      reserveRow('black', pos.blackReserve),
      status,
      el('div', { className: 'muted', id: 'ply' }, `Ply ${game.moves.length} (cap ${game.plyCap}) · delay ${game.delayMs} ms`),
    );

    // The move list, in D09 notation. White moves on odd plies (White starts).
    const list = el('ol', { className: 'moves', id: 'moves' });
    game.moves.forEach((text, i) => {
      const li = el('li', {}, dot(i % 2 === 0 ? 'white' : 'black'), el('code', {}, text));
      if (i === game.moves.length - 1) li.className = 'latest';
      list.append(li);
    });
    panel.append(el('h3', {}, 'Moves'), list);
    list.scrollTop = list.scrollHeight; // keep the latest move in view
  }

  // ---- game list ----------------------------------------------------------------

  let summaries = [];

  async function refreshList() {
    try {
      summaries = await api.listGames();
      $('list-error').textContent = '';
    } catch (e) {
      $('list-error').textContent = e.message;
    }
    renderList();
    return summaries;
  }

  function renderList() {
    const ul = $('games');
    ul.replaceChildren(
      ...summaries.map((g) => {
        const state = g.status === 'running' ? `running · ply ${g.plies}` : `${RESULT_TEXT[g.result] || g.result} · ${g.plies} plies`;
        const li = el('li', { onclick: () => watch(g.id), title: 'Watch this game' },
          el('div', {}, el('b', {}, `#${g.id} `), el('code', {}, g.white), ' vs ', el('code', {}, g.black)),
          el('div', { className: 'muted' }, state));
        if (game && game.id === g.id) li.className = 'current';
        return li;
      }),
    );
    if (summaries.length === 0) ul.append(el('li', { className: 'muted' }, 'No games yet.'));
  }

  // ---- new-game form ---------------------------------------------------------------

  async function loadBots() {
    let bots = [];
    try {
      bots = await api.listBots();
    } catch (e) {
      $('form-error').textContent = `Could not load bots: ${e.message}`;
    }
    for (const side of ['white', 'black']) {
      const select = $(`${side}-examples`);
      select.replaceChildren(el('option', { value: '' }, 'examples…'));
      for (const b of bots) select.append(el('option', { value: b.example, title: b.help }, `${b.example} — ${b.help}`));
      select.onchange = () => {
        if (select.value) $(side).value = select.value;
        select.value = '';
      };
    }
    // Sensible defaults: a greedy bot against a random one.
    const pick = (kind) => (bots.find((b) => b.kind === kind) || bots[0] || {}).example || kind;
    if (!$('white').value) $('white').value = pick('greedy');
    if (!$('black').value) $('black').value = pick('random');
  }

  $('new-game').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const button = $('start');
    button.disabled = true;
    $('form-error').textContent = '';
    try {
      const num = (id) => ($(id).value === '' ? undefined : Number($(id).value));
      const { id } = await api.createGame({
        white: $('white').value.trim(),
        black: $('black').value.trim(),
        delayMs: num('delay'),
        plyCap: num('plycap'),
      });
      await refreshList();
      watch(id);
    } catch (e) {
      // A 400 carries the server's message naming the bad spec; show it as is.
      $('form-error').textContent = e instanceof ApiError ? e.message : `Error: ${e.message}`;
    } finally {
      button.disabled = false;
    }
  });

  // ---- start-up ------------------------------------------------------------------------

  renderPanel();
  await loadBots();
  await refreshList();
  setInterval(refreshList, LIST_REFRESH_MS);

  // Watch ?game=ID if given, else the newest running game, else the newest game.
  const wanted = params.get('game');
  const first = summaries.find((g) => g.status === 'running') || summaries[0];
  if (wanted) watch(wanted);
  else if (first) watch(first.id);
}

main().catch((e) => {
  console.error(e);
  document.body.prepend(el('div', { className: 'fatal' }, `Viewer failed to start: ${e.message}`));
});
