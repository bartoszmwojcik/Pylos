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
//
// Human play (S5, D18; how input works is ADR 0027). In a game where one side
// is "human", the snapshot says which colour the human plays (`human`) and
// whether the game waits for the human's move (`waitingFor`). On the human's
// turn the board takes input; we also store
//   legal    — the legal moves of the newest position (rules.js),
//   draft    — the move entered so far (rules.js: action, then take-backs),
//   posting  — true while the move is on its way to the server.
// The board only offers choices that lead to a legal move; the server checks
// the move again and its refusal (HTTP 400) is shown as is. Once posted, a
// move is final: there is no undo (D18). Moves of a human game are shown one
// after the other: the bot's reply waits until the human's move has finished
// animating (moveQueue), so both can be seen.

import { createApi, ApiError } from './api.js';
import { BoardView } from './board.js';
import { buildHistory, nextEntry, describeMove, colourName, otherColour } from './notation.js';
import { legalMoves, moveText, emptyDraft, choices, click, draftMove, needsTakeBack, isGameOver } from './rules.js';

const params = new URLSearchParams(window.location.search);
const MOCK = params.get('mock') === '1';
const LIST_REFRESH_MS = 3000;
// After a lost connection we wait 5 s, then 10, 15 … up to 30 s between tries.
const RETRY_STEP_S = 5;
const RETRY_MAX_S = 30;

const RESULT_TEXT = { white: 'White wins', black: 'Black wins', capped: 'Draw (ply cap)' };
// After the human's move has landed, a short pause before the bot's reply is shown.
const REPLY_PAUSE_MS = 250;
// "click" with a mouse, "tap" on a touch screen: only the words differ (ADR 0027).
const TAP = window.matchMedia('(pointer: coarse)').matches ? 'tap' : 'click';
const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

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

  // The hover tooltip: "b12 · White · level b" (or "· empty" on a target square).
  const tip = $('tip');
  const board = new BoardView($('board'), {
    onHover(hit) {
      if (!hit) {
        tip.hidden = true;
        return;
      }
      tip.hidden = false;
      tip.textContent = `${hit.square} · ${hit.colour ? colourName(hit.colour) : 'empty'} · level ${hit.square[0]}`;
      // Position it next to the pointer, inside the stage.
      const canvas = $('board');
      tip.style.left = `${canvas.offsetLeft + hit.x + 14}px`;
      tip.style.top = `${canvas.offsetTop + hit.y + 10}px`;
    },
    onPick: (square) => pick(square),
  });
  // ?debug=1: let browser tests find squares on screen (board.screenPoint) and
  // read the input state. Nothing else uses it.
  if (params.get('debug') === '1') {
    window.pylosDebug = { board, state: () => ({ game, draft, legal: legal.map(moveText), posting, viewPly, moveError }) };
  }

  let game = null;
  let history = [];
  let viewPly = 0;
  let following = true;
  let gameId = null;
  const conn = { state: 'idle', stop: () => {}, generation: 0, timer: null, retryIn: 0, attempt: 0 };
  let listOk = true; // did the last game-list request work?
  // Human play (see the top of the file).
  let legal = [];
  let draft = emptyDraft();
  let posting = false;
  let moveError = '';
  let moveQueue = Promise.resolve();
  let watchToken = 0; // changes when we start watching another game

  const newestPly = () => history.length - 1;

  /** Is it the human's turn in the watched game (whatever ply is on the board)? */
  const humansTurn = () => Boolean(game && game.human && game.status === 'running' &&
    game.waitingFor === game.human && !isGameOver(game.position));
  /** Does the board take input now? Only on the newest ply, and not while a move is being sent. */
  const inputOn = () => humansTurn() && viewPly === newestPly() && !posting;

  /**
   * Draw history[ply] on the board. No faint "placeable" markers once the
   * game is over, nor on the human's turn (the input's own markers show then).
   */
  function showPly(ply, animate = false) {
    const over = game.status === 'finished' && ply === newestPly();
    const input = humansTurn() && ply === newestPly();
    board.show(history[ply], animate, { markers: !over && !input });
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
    watchToken++;
    resetDraft();
    moveError = '';

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
        resetDraft(); // a fresh snapshot (e.g. after a reconnect) starts the input over
        if (following || viewPly > newestPly()) viewPly = newestPly();
        // A human game is always followed: its moves are made on the newest ply.
        if (game.human && game.status === 'running') viewPly = newestPly();
        showPly(viewPly);
        if (game.status === 'finished') disconnect(); // no more events will come
        renderAll();
        renderList();
      },
      onMove(ev) {
        if (!current() || !game) return;
        queue(() => addMove(ev));
      },
      onEnd({ result }) {
        if (!current() || !game) return;
        disconnect(); // api.js has closed the stream already; this is for our state
        conn.state = 'open';
        // Through the queue, so the result comes after the last move is shown.
        queue(() => {
          game.status = 'finished';
          game.result = result;
          game.waitingFor = null;
          resetDraft();
          if (viewPly === newestPly()) board.hideMarkers(); // nobody moves any more
          renderAll();
          refreshList();
        });
      },
      onError() {
        if (!current()) return;
        if (game && game.status === 'finished') return;
        lost();
      },
    });
  }

  /**
   * Run `step` after the steps queued before it. In a human game each step
   * first waits until the board's ball animations have finished, so that the
   * bot's quick reply does not cut the human's move short. Steps queued for a
   * game we no longer watch are dropped.
   */
  function queue(step) {
    const token = watchToken;
    moveQueue = moveQueue.then(async () => {
      if (token !== watchToken || !game) return;
      const left = game.human ? board.animationTimeLeft() : 0;
      if (left > 0) await sleep(left * 1000 + REPLY_PAUSE_MS);
      if (token !== watchToken || !game) return;
      step();
    }).catch((e) => console.error(e));
  }

  /** A "move" event (from the stream, or the answer to our own POST). */
  function addMove(ev) {
    if (ev.ply <= game.moves.length) return; // already have it
    if (ev.ply !== game.moves.length + 1) {
      // We missed a move: reconnect, and the fresh snapshot resyncs us.
      connect();
      return;
    }
    game.moves.push(ev.move);
    game.position = ev.position;
    // The game waits for the human exactly when the human is to move (protocol).
    if (game.human) game.waitingFor = ev.position.toMove === game.human ? game.human : null;
    resetDraft();
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
  }

  // ---- human input ---------------------------------------------------------------

  /** Forget the move entered so far, and recompute the legal moves of the newest position. */
  function resetDraft() {
    draft = emptyDraft();
    legal = humansTurn() ? legalMoves(game.position) : [];
  }

  /** A tap or click on a square the board marked as clickable. */
  function pick(square) {
    if (!inputOn()) return;
    const next = click(game.position, legal, draft, square);
    if (!next) return; // not a legal choice: nothing happens (D18)
    const newAction = next.action && !draft.action;
    draft = next;
    moveError = '';
    if (newAction) {
      if (!needsTakeBack(legal, draft.action)) {
        submit(draftMove(legal, draft, false)); // no shape: the move is complete
        return;
      }
      // A shape is completed (R07): show the ball on its new square (animated)
      // while the take-backs are chosen.
      const action = draft.action.kind === 'raise' ? `${draft.action.from}-${draft.action.to}` : draft.action.to;
      board.show(nextEntry(history[newestPly()], action), true, { markers: false });
    }
    renderAll();
  }

  /** Confirm the take-back choice (0, 1 or 2 balls). */
  function confirmTakeBack() {
    if (!inputOn() || !draft.action) return;
    const move = draftMove(legal, draft, true);
    if (move) submit(move);
  }

  /** Drop the move entered so far (it has not been sent, so this is not an undo). */
  function cancelDraft() {
    if (!inputOn() || (!draft.action && !draft.selected)) return;
    const hadAction = Boolean(draft.action);
    draft = emptyDraft();
    if (hadAction) showPly(newestPly());
    renderAll();
  }

  /** Send the human's move. The server checks it again; a refusal is shown as is. */
  async function submit(move) {
    const token = watchToken;
    const text = moveText(move);
    posting = true;
    renderAll();
    try {
      const ev = await api.postMove(gameId, text);
      if (token !== watchToken) return;
      // Input stays off until the move is on the board: until then the
      // position (and so the legal moves) are still the old ones.
      queue(() => {
        posting = false;
        addMove(ev); // does nothing if the stream has brought the move already
        renderAll();
      });
      return;
    } catch (e) {
      if (token !== watchToken) return;
      posting = false;
      moveError = e instanceof ApiError ? `The server refused ${text}: ${e.message}` : `Could not send ${text}: ${e.message}`;
      resetDraft();
      showPly(newestPly());
    }
    renderAll();
  }

  /**
   * The play bar over the board in a human game: whose turn it is, what to do
   * next, the take-back buttons, "bot is thinking", the result, or an error.
   */
  function renderPlay() {
    const bar = $('play');
    bar.replaceChildren();
    bar.hidden = !(game && game.human);
    if (bar.hidden) return;
    const me = game.human;
    const bot = game[otherColour(me)];
    const button = (label, onclick, primary = false, id = undefined) =>
      el('button', { type: 'button', className: `pv-btn${primary ? ' pv-btn-primary' : ''}`, onclick, id }, label);
    const line = (cls, ...children) => el('p', { className: `pv-play-line ${cls}` }, ...children);
    let state;

    if (game.status === 'finished') {
      const text = game.result === 'capped' ? 'Draw (ply cap)' : game.result === me ? 'You won' : 'You lost';
      state = 'over';
      bar.append(el('div', { className: 'pv-play-title', id: 'play-result' }, text),
        line('', `${RESULT_TEXT[game.result] || game.result}. ${endReason(game).text}`));
    } else if (posting) {
      state = 'wait';
      bar.append(el('div', { className: 'pv-play-title' }, 'Sending your move…'));
    } else if (!humansTurn()) {
      state = 'bot';
      bar.append(el('div', { className: 'pv-play-title pv-thinking', id: 'bot-thinking' }, el('i', { ariaHidden: 'true' }), `${colourName(otherColour(me))} (${bot}) is thinking…`),
        line('pv-muted', 'The board takes no input until the bot has moved.'));
    } else if (viewPly !== newestPly()) {
      state = 'behind';
      bar.append(el('div', { className: 'pv-play-title' }, 'Your move'),
        line('', `You are looking at ply ${viewPly}. Moves are made on the newest position.`),
        el('div', { className: 'pv-play-actions' }, button('Back to the game', () => go(newestPly()), true, 'jump-live')));
    } else if (!draft.action) {
      state = 'turn';
      const { selectable } = choices(game.position, legal, draft);
      const title = draft.selected ? `Raise ${draft.selected}` : `Your move (${colourName(me)})`;
      const help = draft.selected
        ? `${TAP[0].toUpperCase() + TAP.slice(1)} a marked higher square to raise it there (R03), or ${TAP} the lifted ball again to choose another move.`
        : `${TAP[0].toUpperCase() + TAP.slice(1)} a marked square to place a ball${selectable.length ? `, or one of your ringed balls to raise it (R03)` : ''}.`;
      bar.append(el('div', { className: 'pv-play-title', id: 'play-title' }, title), line('', help));
      if (draft.selected) bar.append(el('div', { className: 'pv-play-actions' }, button('Cancel', cancelDraft)));
    } else {
      state = 'takeback';
      const n = draft.takeBack.length;
      const label = n === 0 ? 'Take back nothing' : `Take back ${draft.takeBack.join(' and ')}`;
      bar.append(el('div', { className: 'pv-play-title', id: 'play-title' }, 'Shape completed: take back 0, 1 or 2'),
        line('', n < 2
          ? `${TAP[0].toUpperCase() + TAP.slice(1)} your ringed balls one at a time to take them back to your reserve (R07); only balls free right now respond (R04). Then confirm.`
          : `Two balls chosen, the most a move can take back (R07). Confirm, or ${TAP} the last one to put it back.`),
        el('div', { className: 'pv-play-actions' }, button(label, confirmTakeBack, true, 'confirm'), button('Cancel move', cancelDraft)));
    }
    if (moveError && state !== 'over') bar.append(el('p', { className: 'pv-error', role: 'alert' }, moveError));
    bar.dataset.state = state;
  }

  /** Tell the board what may be clicked now (nothing unless it is the human's turn). */
  function renderInput() {
    if (!inputOn()) {
      board.setInput(null);
      return;
    }
    const { targets, selectable } = choices(game.position, legal, draft);
    board.setInput({ targets, selectable, selected: draft.selected, chosen: draft.takeBack });
  }

  // Keyboard: Escape drops the move entered so far, Enter confirms a take-back.
  document.addEventListener('keydown', (e) => {
    if (!inputOn() || e.target.closest('input, select, textarea')) return;
    if (e.key === 'Escape') cancelDraft();
    else if (e.key === 'Enter' && draft.action) confirmTakeBack();
  });

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
    if (ply !== viewPly) draft = emptyDraft(); // a half-entered move is dropped
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
    renderPlay();
    renderInput();
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
        el('div', { className: 'pv-banner-title', id: 'result' }, icon(capped ? 'pause' : 'flag'), RESULT_TEXT[game.result] || `Finished: ${game.result}`,
          game.human && !capped ? ` — you ${game.result === game.human ? 'won' : 'lost'}` : ''),
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
            game.human === colour ? el('span', { className: 'pv-you' }, 'you') : null,
            turn ? el('span', { className: 'pv-tag' }, 'To move') : null),
          el('code', { className: 'pv-player-bot', title: game[colour] }, game[colour]),
          pips),
        el('span', { className: 'pv-reserve pv-num' }, String(n), el('small', {}, '/15')));
    };
    box.append(row('white'), row('black'),
      el('p', { className: 'pv-meta pv-num', id: 'ply' }, game.human
        ? `Ply ${game.moves.length} · cap ${game.plyCap} · you vs bot`
        : `Ply ${game.moves.length} · cap ${game.plyCap} · delay ${game.delayMs} ms`));
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
      // (append() would print a null as the text "null", so leave it out instead.)
      ...(tags.length ? [el('div', { className: 'pv-tags' }, ...tags.map((t) => el('span', { className: 'pv-tag' }, t)))] : []),
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
    behind.hidden = !game || viewPly === max || (game.human && running);
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
    for (const side of ['white', 'black', 'opponent']) {
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
    if (!$('opponent').value) $('opponent').value = pick('random');
  }

  // The form has two kinds of game (the segmented control on top):
  //   "Bot vs bot" — two bot specs and a delay between moves, as before;
  //   "You vs bot" — your colour and one bot spec (D18). The delay is not
  //                  asked for: the server ignores it in a human game.
  let mode = 'bots';
  let myColour = 'white';
  function renderForm() {
    for (const b of document.querySelectorAll('[data-mode]')) b.setAttribute('aria-pressed', String(b.dataset.mode === mode));
    for (const b of document.querySelectorAll('[data-colour]')) b.setAttribute('aria-pressed', String(b.dataset.colour === myColour));
    $('bots-fields').hidden = mode !== 'bots';
    $('play-fields').hidden = mode !== 'play';
    $('delay-field').hidden = mode !== 'bots';
    $('start').textContent = mode === 'play' ? 'Play' : 'Start';
  }
  $('new-game').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-mode], button[data-colour]');
    if (!b) return;
    if (b.dataset.mode) mode = b.dataset.mode;
    if (b.dataset.colour) myColour = b.dataset.colour;
    renderForm();
  });
  if (params.get('play') === '1') mode = 'play'; // ?play=1 opens the form on "You vs bot"
  renderForm();

  $('new-game').addEventListener('submit', async (ev) => {
    ev.preventDefault();
    const button = $('start');
    button.disabled = true;
    $('form-error').textContent = '';
    try {
      const num = (id) => ($(id).value === '' ? undefined : Number($(id).value));
      const bot = $('opponent').value.trim();
      const players = mode === 'play'
        ? { white: myColour === 'white' ? 'human' : bot, black: myColour === 'black' ? 'human' : bot }
        : { white: $('white').value.trim(), black: $('black').value.trim() };
      const { id } = await api.createGame({
        ...players,
        delayMs: mode === 'play' ? undefined : num('delay'),
        plyCap: num('plycap'),
      });
      await refreshList();
      watch(id);
      // On a phone the form is below the board, which is first on the page
      // (after the top bar): scroll up so the top bar, board and play bar show.
      if (mode === 'play') window.scrollTo({ top: 0 });
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
