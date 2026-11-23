// Viewer prototype wiring: builds each screen's viewer from data-viewer config.
// Backend behaviour (record files, live stream, replay validation) is SIMULATED
// in this file with local timers and fixture records from games.js.
import { Board3D } from './board3d.js?v=3';
import { replay, describeMove, endReason, colourName, squareOf } from './pylos.js';

const GAMES = window.PYLOS_GAMES;
// A hand-edited record whose 9th move is illegal (a24 is already occupied).
const BROKEN = {
  file: 'games/2026-11-20-hand-edited.json', saved: '2026-11-20 18:31',
  record: { ...GAMES[2].record, moves: [...GAMES[2].record.moves.slice(0, 8), 'a24', ...GAMES[2].record.moves.slice(9)] },
  error: { ply: 9, text: '“a24” is not a legal move here: a24 is already occupied.' },
};

const ic = (name) => `<svg class="pv-ic" aria-hidden="true"><use href="#pv-${name}"/></svg>`;
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

function resultLabel(rec) {
  return rec.result === 'capped' ? 'Capped' : `${rec.result === 'white' ? 'White' : 'Black'} wins`;
}

// ── Library ───────────────────────────────────────────────────────────────
function renderLibrary(el) {
  const empty = el.dataset.library === 'empty';
  const rows = GAMES.map((g, i) => {
    const snaps = replay(g.record);
    const end = endReason(g.record, snaps);
    return `<tr>
      <td><button class="pv-link" data-open-game="${i}" data-goto="s2">${esc(g.file.replace('games/', ''))}</button></td>
      <td>${esc(g.record.white)}</td><td>${esc(g.record.black)}</td>
      <td><span class="pv-result pv-result-${g.record.result}">${resultLabel(g.record)}</span></td>
      <td class="pv-num">${g.record.plies}</td>
      <td class="pv-muted">${esc(end.code === 'apex' ? 'Apex placed' : end.code === 'reserve' ? 'Empty reserve' : 'Ply cap')}</td>
      <td class="pv-muted pv-num">${esc(g.saved)}</td>
    </tr>`;
  }).join('') + `<tr>
      <td><button class="pv-link" data-goto="s6">${esc(BROKEN.file.replace('games/', ''))}</button></td>
      <td>random</td><td>random</td><td><span class="pv-result pv-result-error">Cannot replay</span></td>
      <td class="pv-num">—</td><td class="pv-muted">Illegal move 9</td><td class="pv-muted pv-num">${BROKEN.saved}</td></tr>`;

  el.innerHTML = `
  <div class="pv-library">
    <section class="pv-panel pv-live-card">
      <div class="pv-live-head">${empty ? '<span class="pv-pill">Idle</span><h2 class="pv-h2">No live match</h2>' : '<span class="pv-pill pv-pill-live"><i></i>Live</span><h2 class="pv-h2">Match in progress</h2>'}</div>
      ${empty ? `<p class="pv-muted">No match is running. Start one on the server with <code class="pv-code">pylos-match</code>; it appears here automatically.</p>`
      : `<p class="pv-live-line"><b>random</b> <span class="pv-muted">(White)</span> vs <b>random</b> <span class="pv-muted">(Black)</span></p>
      <p class="pv-muted pv-num">Ply 12 of cap 300 · started 14:31</p>
      <button class="pv-btn pv-btn-primary" data-goto="s4">${ic('eye')}Watch live</button>`}
    </section>
    <section class="pv-panel pv-records">
      <div class="pv-records-head">
        <h2 class="pv-h2">Game records</h2>
        <span class="pv-muted pv-num">${empty ? 0 : GAMES.length + 1} files in <code class="pv-code">games/</code></span>
      </div>
      ${empty ? `<div class="pv-empty">
          <div class="pv-empty-glyph" aria-hidden="true"><i></i><i></i><i></i></div>
          <h3 class="pv-h3">No game records yet</h3>
          <p class="pv-muted">Records are the JSON files the match runner writes to <code class="pv-code">games/</code>. Generate one with <code class="pv-code">pylos-ref playout 42 &gt; games/seed-42.json</code>.</p>
        </div>`
      : `<div class="pv-table-wrap"><table class="pv-table">
        <thead><tr><th>File</th><th>White</th><th>Black</th><th>Result</th><th class="pv-num">Plies</th><th>Ended by</th><th>Saved</th></tr></thead>
        <tbody>${rows}</tbody></table></div>`}
    </section>
  </div>`;
}

// ── Viewer ────────────────────────────────────────────────────────────────
const viewers = {};

function viewerMarkup(cfg) {
  const cams = [['perspective', 'Perspective'], ['top', 'Top'], ['side', 'Side'], ['corner', 'Corner']];
  const lv = [[0, 'A'], [1, 'A–B'], [2, 'A–C'], [3, 'All']];
  return `
  <div class="pv-body">
    <section class="pv-stage" aria-label="Board">
      <div class="pv-canvas" tabindex="0" aria-label="3D board. Drag to orbit, scroll to zoom, arrow keys step through moves."></div>
      <div class="pv-hud pv-hud-tl">
        <div class="pv-seg" role="group" aria-label="Camera">${cams.map(([k, l]) => `<button type="button" data-cam="${k}" aria-pressed="${k === 'perspective'}">${l}</button>`).join('')}</div>
      </div>
      <div class="pv-hud pv-hud-tr">
        <span class="pv-hud-label">Levels</span>
        <div class="pv-seg" role="group" aria-label="Visible levels">${lv.map(([k, l]) => `<button type="button" data-lv="${k}" aria-pressed="${k === 3}">${l}</button>`).join('')}</div>
      </div>
      <div class="pv-tip" role="status" hidden></div>
      <div class="pv-banner" hidden></div>
      <div class="pv-transport">
        <div class="pv-transport-btns">
          <button type="button" class="pv-icbtn" data-act="first" aria-label="First position">${ic('first')}</button>
          <button type="button" class="pv-icbtn" data-act="prev" aria-label="Previous move">${ic('prev')}</button>
          <button type="button" class="pv-icbtn pv-icbtn-main" data-act="play" aria-label="Play">${ic('play')}</button>
          <button type="button" class="pv-icbtn" data-act="next" aria-label="Next move">${ic('next')}</button>
          <button type="button" class="pv-icbtn" data-act="last" aria-label="Last position">${ic('last')}</button>
        </div>
        <input class="pv-range" type="range" min="0" value="0" aria-label="Ply">
        <span class="pv-ply pv-num"></span>
        ${cfg.mode === 'live' || cfg.mode === 'lost'
          ? `<button type="button" class="pv-pill pv-pill-live pv-follow" data-act="follow"><i></i><span>Live</span></button>`
          : `<label class="pv-speed"><span class="pv-sr">Speed</span><select aria-label="Playback speed"><option value="0.5">0.5×</option><option value="1" selected>1×</option><option value="2">2×</option><option value="4">4×</option></select></label>`}
      </div>
    </section>
    <aside class="pv-side">
      <section class="pv-status" hidden></section>
      <section class="pv-panel pv-players" aria-label="Players"></section>
      <section class="pv-panel pv-current" aria-live="polite"></section>
      <section class="pv-panel pv-moves">
        <div class="pv-moves-head"><h3 class="pv-h3">Moves</h3><span class="pv-muted pv-small">D09 notation</span></div>
        <ol class="pv-movelist"></ol>
      </section>
    </aside>
  </div>`;
}

function mountViewer(el) {
  const cfg = JSON.parse(el.dataset.viewer);
  const src = cfg.broken ? BROKEN : GAMES[cfg.game];
  el.innerHTML = viewerMarkup(cfg);
  const $ = (s) => el.querySelector(s);
  const state = {
    cfg, src, snaps: null, ply: 0, playing: false, timer: null, speed: 1,
    live: cfg.mode === 'live' || cfg.mode === 'lost', following: true, livePly: cfg.ply,
  };
  const tip = $('.pv-tip');
  const board = new Board3D($('.pv-canvas'), {
    onHover: (h) => {
      if (!h) { tip.hidden = true; return; }
      tip.hidden = false;
      tip.textContent = `${h.id} · ${colourName(h.colour)} · level ${h.id[0]}`;
      tip.style.left = `${h.x + 14}px`; tip.style.top = `${h.y + 10}px`;
    },
  });

  function load(source) {
    state.src = source;
    const moves = source.error ? source.record.moves.slice(0, source.error.ply - 1) : source.record.moves;
    state.snaps = replay({ ...source.record, moves });
    // the move list shows every recorded move, the illegal one marked
    state.allMoves = source.record.moves;
    const max = state.live ? state.livePly : state.snaps.length - 1;
    const range = $('.pv-range');
    range.max = max;
    renderMoveList();
    go(Math.min(cfg.ply ?? max, max), false);
  }

  function lastAvailable() { return state.live ? state.livePly : state.snaps.length - 1; }

  function renderMoveList() {
    const list = $('.pv-movelist');
    const limit = state.live ? state.livePly : state.allMoves.length;
    let html = `<li class="pv-mv-start"><button type="button" data-ply="0">Start</button></li>`;
    for (let i = 0; i < limit; i += 2) {
      const cell = (k) => {
        if (k >= limit) return '<span></span>';
        const bad = state.src.error && k + 1 === state.src.error.ply;
        const beyond = state.src.error && k + 1 > state.src.error.ply;
        return `<button type="button" data-ply="${k + 1}" class="${bad ? 'is-bad' : ''}" ${beyond ? 'disabled' : ''}>${esc(state.allMoves[k])}</button>`;
      };
      html += `<li><span class="pv-mv-no">${i / 2 + 1}</span>${cell(i)}${cell(i + 1)}</li>`;
    }
    list.innerHTML = html;
  }

  function renderPlayers(snap) {
    const rec = state.src.record;
    const over = !state.live && snap.ply === state.snaps.length - 1 && !state.src.error;
    const row = (c) => {
      const n = snap.reserve[c];
      const pips = Array.from({ length: 15 }, (_, i) => `<i class="${i < n ? 'on' : ''}"></i>`).join('');
      const turn = !over && snap.toMove === c;
      return `<div class="pv-player ${turn ? 'is-turn' : ''}">
        <span class="pv-ball pv-ball-${c}" aria-hidden="true"></span>
        <div class="pv-player-main">
          <div class="pv-player-name"><b>${colourName(c)}</b><span class="pv-muted">${esc(c === 'W' ? rec.white : rec.black)}</span>${turn ? '<span class="pv-tag">To move</span>' : ''}</div>
          <div class="pv-pips" role="img" aria-label="${n} of 15 balls in reserve">${pips}</div>
        </div>
        <span class="pv-reserve pv-num">${n}<small>/15</small></span>
      </div>`;
    };
    $('.pv-players').innerHTML = row('W') + row('B');
  }

  function renderCurrent(snap) {
    const m = snap.move;
    const total = state.live ? state.livePly : state.snaps.length - 1;
    const tags = [];
    if (m) {
      tags.push(m.kind === 'raise' ? 'Raise' : 'Place');
      m.shapes.forEach((s) => tags.push(s.type === 'square' ? 'Square' : s.type === 'row' ? 'Row of 4' : 'Column of 4'));
      if (m.takeBacks.length) tags.push(`Take-back ×${m.takeBacks.length}`);
    }
    $('.pv-current').innerHTML = `
      <div class="pv-current-head pv-num">Ply ${snap.ply} / ${total}${m ? ` · ${colourName(m.colour)}` : ''}</div>
      <div class="pv-notation">${m ? esc(m.text) : '—'}</div>
      <p class="pv-desc">${esc(describeMove(m))}</p>
      ${tags.length ? `<div class="pv-tags">${tags.map((t) => `<span class="pv-tag">${t}</span>`).join('')}</div>` : ''}`;
  }

  function renderBanner(snap) {
    const b = $('.pv-status');
    $('.pv-banner').hidden = true;
    const rec = state.src.record;
    if (state.src.error) {
      b.hidden = false; b.className = 'pv-status pv-banner-error'; b.setAttribute('role', 'alert');
      b.innerHTML = `<div class="pv-banner-title">${ic('warn')}Replay stopped at move ${state.src.error.ply}</div>
        <p>${esc(state.src.error.text)} The board shows the position after move ${state.src.error.ply - 1}. The file was not changed.</p>
        <div class="pv-banner-actions"><button type="button" class="pv-btn" data-goto="s1">Back to library</button><button type="button" class="pv-btn pv-btn-ghost" data-act="copy">${ic('copy')}Copy file path</button></div>`;
      return;
    }
    if (cfg.mode === 'lost') {
      b.hidden = false; b.className = 'pv-status pv-banner-warn'; b.setAttribute('role', 'status');
      b.innerHTML = `<div class="pv-banner-title">${ic('plug')}Connection to the server lost</div>
        <p>The board stays at ply ${state.livePly}. Reconnecting in <b class="pv-count">5</b> s; missed moves are fetched on reconnect.</p>
        <div class="pv-banner-actions"><button type="button" class="pv-btn" data-act="retry">${ic('refresh')}Retry now</button></div>`;
      return;
    }
    const over = !state.live && snap.ply === state.snaps.length - 1;
    if (over) {
      const end = endReason(rec, state.snaps);
      b.hidden = false; b.className = `pv-status ${rec.result === 'capped' ? 'pv-banner-neutral' : 'pv-banner-result'}`; b.setAttribute('role', 'status');
      b.innerHTML = `<div class="pv-banner-title">${ic(rec.result === 'capped' ? 'pause' : 'flag')}${resultLabel(rec)}</div>
        <p>${esc(end.text)} <span class="pv-ref">${end.rule}</span></p>`;
      return;
    }
    b.hidden = true;
    if (state.live && !state.following) {
      const f = $('.pv-banner');
      f.hidden = false; f.className = 'pv-banner pv-banner-neutral pv-banner-slim';
      f.innerHTML = `<p>Viewing ply ${snap.ply}. The match is at ply ${state.livePly}.</p><button type="button" class="pv-btn pv-btn-primary" data-act="follow">${ic('next')}Jump to live</button>`;
    }
  }

  function go(ply, animate = true) {
    ply = Math.max(0, Math.min(ply, lastAvailable()));
    const forwardOne = ply === state.ply + 1;
    state.ply = ply;
    const snap = state.snaps[ply];
    board.show(snap, animate && forwardOne);
    $('.pv-range').max = lastAvailable();
    $('.pv-range').value = ply;
    $('.pv-ply').textContent = `${ply} / ${lastAvailable()}`;
    if (state.live) state.following = ply === state.livePly;
    renderPlayers(snap); renderCurrent(snap); renderBanner(snap);
    el.querySelectorAll('.pv-movelist button').forEach((btn) => btn.classList.toggle('is-current', +btn.dataset.ply === ply));
    const cur = el.querySelector('.pv-movelist .is-current');
    const list = $('.pv-movelist');
    if (cur) {
      const top = cur.offsetTop - list.offsetTop;
      if (top < list.scrollTop || top > list.scrollTop + list.clientHeight - 28) list.scrollTop = top - list.clientHeight / 2;
    }
    const followBtn = $('.pv-follow');
    if (followBtn) followBtn.classList.toggle('is-behind', !state.following);
    $('[data-act="play"]').disabled = state.live;
    if (ply >= lastAvailable() && state.playing) setPlaying(false);
  }

  function setPlaying(on) {
    state.playing = on;
    clearInterval(state.timer);
    const btn = $('[data-act="play"]');
    btn.innerHTML = ic(on ? 'pause' : 'play');
    btn.setAttribute('aria-label', on ? 'Pause' : 'Play');
    if (on) {
      if (state.ply >= lastAvailable()) go(0, false);
      state.timer = setInterval(() => go(state.ply + 1), 900 / state.speed);
    }
  }

  // live stream simulation: a new ply every 2.4 s until the record ends
  if (state.live && cfg.mode === 'live') {
    setInterval(() => {
      if (!state.visible) return;
      if (state.livePly >= state.src.record.moves.length) return;
      state.livePly += 1;
      renderMoveList();
      if (state.following) go(state.livePly); else go(state.ply, false);
    }, 2400);
  }
  if (cfg.mode === 'lost') {
    let n = 5;
    setInterval(() => { n = n <= 1 ? 5 : n - 1; const c = el.querySelector('.pv-count'); if (c) c.textContent = n; }, 1000);
  }
  new IntersectionObserver(([e]) => { state.visible = e.isIntersecting; }).observe(el.closest('.pv-app'));

  el.addEventListener('click', (e) => {
    const t = e.target.closest('button');
    if (!t || !el.contains(t)) return;
    if (t.dataset.cam) {
      board.setCamera(t.dataset.cam);
      el.querySelectorAll('[data-cam]').forEach((b) => b.setAttribute('aria-pressed', String(b === t)));
    } else if (t.dataset.lv) {
      board.setMaxLevel(+t.dataset.lv);
      el.querySelectorAll('[data-lv]').forEach((b) => b.setAttribute('aria-pressed', String(b === t)));
    } else if (t.dataset.ply) {
      setPlaying(false); go(+t.dataset.ply);
    } else if (t.dataset.act) {
      const a = t.dataset.act;
      if (a === 'first') { setPlaying(false); go(0); }
      if (a === 'prev') { setPlaying(false); go(state.ply - 1); }
      if (a === 'next') { setPlaying(false); go(state.ply + 1); }
      if (a === 'last') { setPlaying(false); go(lastAvailable()); }
      if (a === 'play') setPlaying(!state.playing);
      if (a === 'follow') go(state.livePly);
      if (a === 'copy') { navigator.clipboard?.writeText(state.src.file); t.lastChild.textContent = 'Copied'; }
      if (a === 'retry') { const c = el.querySelector('.pv-count'); if (c) c.textContent = '…'; }
    }
  });
  $('.pv-range').addEventListener('input', (e) => { setPlaying(false); go(+e.target.value, false); });
  const speed = el.querySelector('.pv-speed select');
  if (speed) speed.addEventListener('change', (e) => { state.speed = +e.target.value; if (state.playing) setPlaying(true); });
  $('.pv-canvas').addEventListener('keydown', (e) => {
    const k = { ArrowLeft: -1, ArrowRight: 1 }[e.key];
    if (k) { e.preventDefault(); setPlaying(false); go(state.ply + k); }
    if (e.key === 'Home') { e.preventDefault(); go(0); }
    if (e.key === 'End') { e.preventDefault(); go(lastAvailable()); }
    if (e.key === ' ' && !state.live) { e.preventDefault(); setPlaying(!state.playing); }
  });

  load(src);
  viewers[el.closest('.screen').id] = { load: (i) => { cfg.ply = 0; load(GAMES[i]); setFile(el, GAMES[i]); } };
  if (!state.live) setFile(el, src);
}

function setFile(el, src) {
  const top = el.closest('.pv-app')?.querySelector('[data-file]');
  if (top) top.textContent = src.file;
}

document.querySelectorAll('[data-library]').forEach(renderLibrary);
document.querySelectorAll('[data-viewer]').forEach(mountViewer);

// Library rows choose which record the replay screen shows, then navigate.
document.addEventListener('click', (e) => {
  const b = e.target.closest('[data-open-game]');
  if (b && viewers.s2) viewers.s2.load(+b.dataset.openGame);
}, true);

window.__pylosReady = true;
