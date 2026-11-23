// api.js — a thin client for the server's JSON API and SSE stream
// (docs/web-protocol.md). Nothing else in the browser builds URLs.
//
// The two browser primitives it uses, `fetch` and `EventSource`, are passed
// in. Normally they are the real ones; in mock mode (?mock=1) they are the
// fakes from mock.js, so the very same code paths run against a fake server.

export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

export function createApi({ fetch = window.fetch.bind(window), EventSource = window.EventSource } = {}) {
  /** Fetch JSON; on a non-2xx status throw ApiError with the server's "error" text. */
  async function request(method, path, body) {
    const init = { method, headers: {} };
    if (body !== undefined) {
      init.headers['Content-Type'] = 'application/json';
      init.body = JSON.stringify(body);
    }
    const res = await fetch(path, init);
    let data = null;
    try {
      data = await res.json();
    } catch {
      // A body that is not JSON (e.g. a proxy error page): report the status.
    }
    if (!res.ok) {
      const msg = (data && data.error) || `${method} ${path} failed: HTTP ${res.status}`;
      throw new ApiError(res.status, msg);
    }
    return data;
  }

  return {
    /** [{ kind, example, help }] — one entry per bot kind. */
    listBots: () => request('GET', '/api/bots'),
    /** [GameSummary], newest first. */
    listGames: () => request('GET', '/api/games'),
    /** Start a bot-vs-bot game; resolves to { id }, or throws ApiError (400) naming the bad spec. */
    createGame: ({ white, black, delayMs, plyCap }) =>
      request('POST', '/api/games', { white, black, delayMs, plyCap }),
    /** GameSnapshot. */
    getGame: (id) => request('GET', `/api/games/${encodeURIComponent(id)}`),

    /**
     * Subscribe to a game's events. `handlers` has onSnapshot, onMove, onEnd
     * (each receives the parsed JSON data) and optionally onError.
     * Returns a function that closes the stream.
     */
    watchGame(id, handlers) {
      const es = new EventSource(`/api/games/${encodeURIComponent(id)}/events`);
      const on = (name, fn) =>
        es.addEventListener(name, (ev) => {
          if (fn) fn(JSON.parse(ev.data));
        });
      on('snapshot', handlers.onSnapshot);
      on('move', handlers.onMove);
      on('end', (data) => {
        // The server keeps the stream open after "end" (protocol), so we close it.
        es.close();
        if (handlers.onEnd) handlers.onEnd(data);
      });
      // EventSource reconnects by itself after a network error; the server
      // then sends a fresh snapshot, which replaces our state.
      es.onerror = () => {
        if (handlers.onError) handlers.onError();
      };
      return () => es.close();
    },
  };
}
