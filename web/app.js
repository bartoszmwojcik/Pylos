// app.js — the page's controller: the new-game form, the game list, the side
// panel, the transport bar, and the live event stream that drives the board.
//
// State flows one way: the server (or the mock) sends a snapshot or a move,
// we store it, then redraw the panels and the board from what we stored.
//
// What we store about the watched game:
//   game     — the latest GameSnapshot (docs/web-protocol.md), kept up to date
//              by the "move" and "end" events.
//   history  — every position of the game, history[k] = after ply k
//              (buildHistory in notation.js). The server only sends the moves
//              and the current position; earlier positions are rebuilt here.
//   viewPly  — the ply shown on the board. While `following` is true it is
//              always the newest ply. Clicking an earlier move (or the
//              transport's step buttons) sets following = false: new moves
//              still arrive and are listed, but the board stays where you
//              are until you press "Jump to live".
//   conn     — the state of the event stream: connecting, open, lost (with a
//              reconnect countdown), or gone (the game no longer exists).

import { createApi, ApiError } from './api.js';
import { BoardView } from './board.js';
import { buildHistory, nextEntry, describeMove, colourName, otherColour } from './notation.js';

const params = new URLSearchParams(window.location.search);
const MOCK = params.get('mock') === '1';
const LIST_REFRESH_MS = 3000;
// After a lost connection we wait 5 s, then 10, 15 … up to 30 s between tries.
const RETRY_STEP_S = 5;
const RETRY_MAX_S = 30;

const RESULT_TEXT = { white: 'White wins', black: 'Black wins', capped: 'Draw (ply cap)' };

/** Tiny DOM helper: el('li', { className: 'x', onclick }, 'text', childNode). */
function el(tag, props = {}, ...children) {
  const node = Object.assign(document.createElement(tag), props);
  for (const c of children) if (c !== null && c !== undefined && c !== false) node.append(c);
  return node;
}

/** An icon from the <symbol>s in index.html. */
function icon(name) {
  const svg = document.createElementNS('http://www.w3.org/2000/svg', 'svg');
  svg.setAttribute('class', 'pv-ic');
  svg.setAttribute('aria-hidden', 'true');
  const use = document.createElementNS('http://www.w3.org/2000/svg', 'use');
  use.setAttribute('href', `#pv-${name}`);
  svg.append(use);
  return svg;
}

const $ = (id) => document.getElementById(id);

/**
 * Why a finished game ended, for the game-over card: the rule and a sentence.
 *   capped — the match runner stopped it at the ply cap (D12): a draw.
 *   apex   — the winner placed the apex; then the loser had no ball left (R05).
 *   reserve— the loser had an empty reserve on their turn (R05).
 */
function endReason(game) {
  if (game.result === 'capped') {
    return { rule: 'D12', text: `Stopped at the ply cap (${game.plyCap} plies). The match runner counts it as a draw.` };
  }
  const winner = colourName(game.result);
  const loser = colourName(otherColour(game.result));
  if (game.position.squares.d11) return { rule: 'R05', text: `${winner} placed the apex; ${loser} has no ball left.` };
  return { rule: 'R05', text: `${loser} has an empty reserve on their turn.` };
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

  // The hover tooltip: "b12 · White · level b".
  const tip = $('tip');
  const board = new BoardView($('board'), {
    onHover(hit) {
      if (!hit) {
        tip.hidden = true;
        return;
      }
      tip.hidden = false;
      tip.textContent = `${hit.square} · ${colourName(hit.colour)} · level ${hit.square[0]}`;
      // Position it next to the pointer, inside the stage.
      const canvas = $('board');
      tip.style.left = `${canvas.offsetLeft + hit.x + 14}px`;
      tip.style.top = `${canvas.offsetTop + hit.y + 10}px`;
    },
  });

  let game = null;
  let history = [];
  let viewPly = 0;
  let following = true;
  let gameId = null;
  const conn = { state: 'idle', stop: () => {}, generation: 0, timer: null, retryIn: 0, attempt: 0 };
  let listOk = true; // did the last game-list request work?

  const newestPly = () => history.length - 1;

  /** Draw history[ply] on the board (no "placeable" markers once the game is over). */
  function showPly(ply, animate = false) {
    const over = game.status === 'finished' && ply === newestPly();
    board.show(history[ply], animate, { markers: !over });
  }

  // ---- watching a game ------------------------------------------------------

  /** Start watching game `id` (closing the previous game's stream first). */
  function watch(id) {
    disconnect();
    gameId = id;
    game = null;
    history = [];
    viewPly = 0;
    following = true;

    const url = new URL(window.location.href);
    url.searchParams.set('game', id);
    window.history.replaceState(null, '', url);

    connect();
    renderAll();
    renderList();
  }

  /** Close the stream and cancel any pending reconnect. */
  function disconnect() {
    conn.generation++; // events from older streams are ignored from now on
    conn.stop();
    conn.stop = () => {};
    clearInterval(conn.timer);
    conn.timer = null;
  }

  /** Open the event stream of the watched game. */
  function connect() {
    disconnect();
    const generation = conn.generation;
    const current = () => generation === conn.generation; // still the stream we opened?
    conn.state = 'connecting';
    conn.stop = api.watchGame(gameId, {
      onSnapshot(snap) {
        if (!current()) return;
        // Sent on every (re)connect: it replaces whatever we had.
        conn.state = 'open';
        conn.attempt = 0;
        game = snap;
        history = buildHistory(snap.moves);
        // The server is the authority on the position: use its copy.
        history[newestPly()].position = snap.position;
        if (following || viewPly > newestPly()) viewPly = newestPly();
        showPly(viewPly);
        if (game.status === 'finished') disconnect(); // no more events will come
        renderAll();
        renderList();
      },
      onMove(ev) {
        if (!current() || !game) return;
        if (ev.ply <= game.moves.length) return; // already have it
        if (ev.ply !== game.moves.length + 1) {
          // We missed a move: reconnect, and the fresh snapshot resyncs us.
          connect();
          return;
        }
        game.moves.push(ev.move);
        game.position = ev.position;
        const entry = nextEntry(history[newestPly()], ev.move);
        entry.position = ev.position;
        history.push(entry);
        if (following) {
          // Animate only if the board shows the ply just before this one.
          const animate = viewPly === entry.ply - 1;
          viewPly = entry.ply;
          showPly(viewPly, animate);
        }
        renderAll();
      },
      onEnd({ result }) {
        if (!current() || !game) return;
        game.status = 'finished';
        game.result = result;
        disconnect(); // api.js has closed the stream already; this is for our state
        conn.state = 'open';
        if (viewPly === newestPly()) board.hideMarkers(); // nobody moves any more
        renderAll();
        refreshList();
      },
      onError() {
        if (!current()) return;
        if (game && game.status === 'finished') return;
        lost();
      },
    });
  }

  /**
   * The stream broke (server stopped, network gone). We close it ourselves —
   * rather than relying on EventSource's silent auto-reconnect — so that we
   * can show a countdown and a Retry button, and check first that the game
   * still exists (a restarted server has forgotten its games).
   */
  function lost() {
    disconnect();
    conn.state = 'lost';
    conn.attempt++;
    conn.retryIn = Math.min(RETRY_MAX_S, RETRY_STEP_S * conn.attempt);
    conn.timer = setInterval(() => {
      conn.retryIn--;
      if (conn.retryIn <= 0) retry();
      else renderStatus();
    }, 1000);
    renderAll();
  }

  /** Try to reconnect now (the countdown ran out, or Retry was pressed). */
  async function retry() {
    disconnect();
    conn.state = 'connecting';
    renderAll();
    const generation = conn.generation;
    try {
      await api.getGame(gameId);
    } catch (e) {
      if (generation !== conn.generation) return; // the user switched games meanwhile
      if (e instanceof ApiError && e.status === 404) {
        conn.state = 'gone';
        renderAll();
      } else {
        lost(); // still unreachable: count down again
      }
      return;
    }
    if (generation === conn.generation) connect(); // the snapshot will resync us
  }

  /** Show ply `ply` on the board. Stepping one ply forward animates the move. */
  function go(ply) {
    if (!game) return;
    ply = Math.max(0, Math.min(ply, newestPly()));
    const animate = ply === viewPly + 1;
    viewPly = ply;
    following = ply === newestPly();
    showPly(ply, animate);
    renderAll();
  }

  // ---- rendering ----------------------------------------------------------------

  function renderAll() {
    renderTop();
    renderStatus();
    renderPlayers();
    renderCurrent();
    renderMoves();
    renderTransport();
  }

  function renderTop() {
    $('top-game').textContent = game ? `game ${game.id} · ${game.white} vs ${game.black}` : '';
    const status = $('server-status');
    // The top bar is about the server only: a missing game is shown in the side panel.
    const lostNow = conn.state === 'lost' || !listOk;
    status.classList.toggle('is-lost', lostNow);
    const where = MOCK ? 'mock server' : window.location.host;
    $('server-text').textContent = `${where} · ${lostNow ? 'reconnecting' : conn.state === 'connecting' ? 'connecting' : 'connected'}`;
  }

  /** The card at the top of the side panel: connection trouble, or the result. */
  function renderStatus() {
    const box = $('status');
    box.replaceChildren();
    box.hidden = true;
    const show = (kind, role, ...children) => {
      box.hidden = false;
      box.className = `pv-status ${kind}`;
      box.setAttribute('role', role);
      box.append(...children);
    };
    const button = (label, iconName, onclick, primary = false) =>
      el('button', { type: 'button', className: `pv-btn${primary ? ' pv-btn-primary' : ''}`, onclick }, icon(iconName), label);

    if (conn.state === 'lost') {
      show('pv-banner-warn', 'status',
        el('div', { className: 'pv-banner-title' }, icon('plug'), 'Connection to the server lost'),
        el('p', {}, `The board stays at ply ${Math.max(0, newestPly())}. Reconnecting in `,
          el('b', { className: 'pv-count pv-num' }, String(conn.retryIn)), ' s; missed moves arrive with the fresh snapshot.'),
        el('div', { className: 'pv-banner-actions' }, button('Retry now', 'refresh', retry)));
      return;
    }
    if (conn.state === 'gone') {
      show('pv-banner-error', 'alert',
        el('div', { className: 'pv-banner-title' }, icon('warn'), 'Game not found'),
        el('p', {}, `The server no longer has game ${gameId} (it may have been restarted). Pick a game from the list or start a new one.`));
      return;
    }
    // The game-over card is shown on the final position only (as in the
    // prototype): step back and it goes away, the "behind" bar takes over.
    if (game && game.status === 'finished' && viewPly === newestPly()) {
      const end = endReason(game);
      const capped = game.result === 'capped';
      show(capped ? 'pv-banner-neutral' : 'pv-banner-result', 'status',
        el('div', { className: 'pv-banner-title', id: 'result' }, icon(capped ? 'pause' : 'flag'), RESULT_TEXT[game.result] || `Finished: ${game.result}`),
        el('p', {}, `${end.text} `, el('span', { className: 'pv-ref' }, end.rule)));
    }
  }

  function renderPlayers() {
    const box = $('players');
    box.replaceChildren();
    if (!game) {
      const text = conn.state === 'connecting' ? 'Connecting…' : 'Start a game or pick one from the list.';
      box.append(el('p', { className: 'pv-empty-note' }, text));
      return;
    }
    const pos = history[viewPly].position;
    const over = game.status === 'finished' && viewPly === newestPly();
    const row = (colour) => {
      const n = colour === 'white' ? pos.whiteReserve : pos.blackReserve;
      const turn = !over && pos.toMove === colour;
      const pips = el('div', { className: 'pv-pips', role: 'img', ariaLabel: `${n} of 15 balls in reserve` },
        ...Array.from({ length: 15 }, (_, i) => el('i', { className: i < n ? 'on' : '' })));
      return el('div', { className: `pv-player pv-player-${colour}${turn ? ' is-turn' : ''}` },
        el('span', { className: `pv-ball pv-ball-${colour}`, ariaHidden: 'true' }),
        el('div', { className: 'pv-player-main' },
          el('div', { className: 'pv-player-name' }, el('b', {}, colourName(colour)),
            turn ? el('span', { className: 'pv-tag' }, 'To move') : null),
          el('code', { className: 'pv-player-bot', title: game[colour] }, game[colour]),
          pips),
        el('span', { className: 'pv-reserve pv-num' }, String(n), el('small', {}, '/15')));
    };
    box.append(row('white'), row('black'),
      el('p', { className: 'pv-meta pv-num', id: 'ply' }, `Ply ${game.moves.length} · cap ${game.plyCap} · delay ${game.delayMs} ms`));
  }

  function renderCurrent() {
    const box = $('current');
    box.replaceChildren();
    box.hidden = !game;
    if (!game) return;
    const m = history[viewPly].move;
    const tags = [];
    if (m) {
      tags.push(m.kind === 'raise' ? 'Raise' : 'Place');
      for (const s of m.shapes) tags.push(s.type === 'square' ? 'Square' : s.type === 'row' ? 'Row of 4' : 'Column of 4');
      if (m.takeBack.length) tags.push(`Take-back ×${m.takeBack.length}`);
    }
    box.append(
      el('div', { className: 'pv-current-head pv-num' }, `Ply ${viewPly} / ${newestPly()}${m ? ` · ${colourName(m.by)}` : ''}`),
      el('div', { className: 'pv-notation' }, m ? m.text : '—'),
      el('p', { className: 'pv-desc' }, describeMove(m)),
      tags.length ? el('div', { className: 'pv-tags' }, ...tags.map((t) => el('span', { className: 'pv-tag' }, t))) : null,
    );
  }

  /** The move list, two plies per row (White starts, so White is the left column). */
  function renderMoves() {
    const list = $('moves');
    const keepScroll = list.scrollTop;
    list.replaceChildren();
    if (!game) return;
    const cell = (ply) => {
      if (ply > newestPly()) return el('span');
      const classes = [ply === viewPly ? 'is-current' : '', ply === newestPly() ? 'is-latest' : ''].join(' ').trim();
      return el('button', { type: 'button', className: classes, onclick: () => go(ply), title: `Show the position after ply ${ply}` }, game.moves[ply - 1]);
    };
    list.append(el('li', { className: 'pv-mv-start' },
      el('button', { type: 'button', className: viewPly === 0 ? 'is-current' : '', onclick: () => go(0) }, 'Start')));
    for (let ply = 1; ply <= newestPly(); ply += 2) {
      list.append(el('li', {}, el('span', { className: 'pv-mv-no' }, String((ply + 1) / 2)), cell(ply), cell(ply + 1)));
    }
    // Keep the shown move in view: follow the bottom while following,
    // otherwise keep the user's scroll unless the current move is off screen.
    list.scrollTop = keepScroll;
    const cur = list.querySelector('.is-current');
    if (following) list.scrollTop = list.scrollHeight;
    else if (cur) {
      const top = cur.offsetTop - list.offsetTop;
      if (top < list.scrollTop || top > list.scrollTop + list.clientHeight - 28) list.scrollTop = top - list.clientHeight / 2;
    }
  }

  function renderTransport() {
    const max = Math.max(0, newestPly());
    const range = $('ply-range');
    range.max = String(max);
    range.value = String(viewPly);
    range.disabled = !game;
    $('ply-text').textContent = `${viewPly} / ${max}`;
    for (const b of document.querySelectorAll('.pv-transport [data-act]')) {
      const a = b.dataset.act;
      if (a === 'first' || a === 'prev') b.disabled = !game || viewPly === 0;
      if (a === 'next' || a === 'last') b.disabled = !game || viewPly === max;
    }
    const running = game && game.status === 'running';
    $('follow').hidden = !running;
    $('follow').classList.toggle('is-behind', !following);
    $('finished-pill').hidden = !(game && game.status === 'finished');

    // The slim bar over the board while you look at an earlier ply.
    const behind = $('behind');
    behind.replaceChildren();
    behind.hidden = !game || viewPly === max;
    if (!behind.hidden) {
      const live = running;
      behind.append(
        el('p', {}, live ? `Viewing ply ${viewPly}. The match is at ply ${max}.` : `Viewing ply ${viewPly}. The game ended at ply ${max}.`),
        el('button', { type: 'button', className: 'pv-btn pv-btn-primary', id: 'jump-live', onclick: () => go(max) }, icon('next'), live ? 'Jump to live' : 'Jump to end'),
      );
    }
  }

  // ---- board controls ------------------------------------------------------------

  document.querySelector('.pv-stage').addEventListener('click', (e) => {
    const b = e.target.closest('button');
    if (!b) return;
    if (b.dataset.cam) {
      board.setCamera(b.dataset.cam);
      for (const o of document.querySelectorAll('[data-cam]')) o.setAttribute('aria-pressed', String(o === b));
    } else if (b.dataset.lv) {
      board.setMaxLevel(Number(b.dataset.lv));
      for (const o of document.querySelectorAll('[data-lv]')) o.setAttribute('aria-pressed', String(o === b));
    } else if (b.dataset.act) {
      // go() clamps to 0 … newest ply, so "first" and "last" can overshoot.
      go({ first: 0, prev: viewPly - 1, next: viewPly + 1, last: Infinity, follow: Infinity }[b.dataset.act]);
    }
  });
  $('ply-range').addEventListener('input', (e) => go(Number(e.target.value)));
  // Arrow keys step while the board has focus; Home and End jump.
  $('board').addEventListener('keydown', (e) => {
    const to = { ArrowLeft: viewPly - 1, ArrowRight: viewPly + 1, Home: 0, End: newestPly() }[e.key];
    if (to === undefined) return;
    e.preventDefault();
    go(to);
  });

  // ---- game list ----------------------------------------------------------------

  let summaries = [];

  async function refreshList() {
    try {
      summaries = await api.listGames();
      $('list-error').textContent = '';
      listOk = true;
    } catch (e) {
      $('list-error').textContent = e.message;
      listOk = false;
    }
    renderList();
    renderTop();
    return summaries;
  }

  function renderList() {
    const ul = $('games');
    ul.replaceChildren(
      ...summaries.map((g) => {
        const state = g.status === 'running'
          ? [el('span', { className: 'pv-pill pv-pill-live' }, el('i'), 'Live'), `ply ${g.plies}`]
          : [el('span', { className: 'pv-pill' }, RESULT_TEXT[g.result] || g.result), `${g.plies} plies`];
        const button = el('button', { type: 'button', onclick: () => watch(g.id), title: `Watch game ${g.id}: ${g.white} vs ${g.black}` },
          el('div', { className: 'pv-game-line' }, el('span', { className: 'pv-game-id' }, `#${g.id}`),
            el('span', { className: 'pv-game-bots' }, `${g.white} vs ${g.black}`)),
          el('div', { className: 'pv-game-state pv-num' }, ...state));
        if (gameId === g.id) button.setAttribute('aria-current', 'true');
        return el('li', {}, button);
      }),
    );
    if (summaries.length === 0) ul.append(el('li', { className: 'pv-muted' }, 'No games yet.'));
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

  renderAll();
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
