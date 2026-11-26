# 0023. The live game server

## Status

Accepted for the stack (D16, the owner's choice on 2026-11-23). The structure below is an implementation choice made by the agent. The owner reviews it in the PR.

## Context

The owner watches games from a laptop, through an SSH tunnel to the headless server (P01). Human-vs-bot play (S5) is the next epic. There is one user, and nothing is public (N02, superseded by N05: the home network is allowed only when the owner turns it on, D20).

## Decision

- `pylos-web` (`server/`, `app/web/`) is scotty on warp, bound to `127.0.0.1` by default. The protocol is in `docs/web-protocol.md`.
- Each game runs in its own thread: it thinks, waits `delayMs`, then publishes the move. State lives in STM variables. A watcher takes the snapshot and subscribes to the game's broadcast channel in one atomic step, so it never misses or repeats a move.
- The JSON API uses scotty routes. The event stream and the static files are two small WAI middlewares in front of scotty. The stream uses wai-extra's `eventSourceAppIO`. Static paths with `..` or hidden names are refused.
- Without an event, the stream sends a comment every 15 seconds, so the SSH tunnel does not drop an idle connection.
- At most 8 games run at once.
- Home-network listening (E05-S01, D20, N05): the option `--lan` makes the server bind `0.0.0.0` instead of `127.0.0.1`. Without it nothing changes, so a fresh start is never reachable from the network by accident. The option is a flag rather than an environment variable or a port-like argument, so it shows in the command line and in `ps`. The flag may stand anywhere among the positional `[PORT] [WEB_DIR]`, which keep working. An unknown `--flag` is refused; before this change extra arguments were ignored. The parser is pure (`app/web/WebArgs.hs`) and tested.
- With `--lan` the server prints the address to open and a warning that anyone on the network can play (no authentication, accepted by the owner in D20). The address is found by connecting a UDP socket to a documentation address (192.0.2.1) and reading the socket's own address; no packet is sent. This finds only the primary IPv4 address, which is what a phone on the home Wi-Fi needs; other interfaces are not listed. This uses the `network` package, which warp already depends on (it is in `cabal.project.freeze`), so no new package is built; it is now also named in the `pylos-web` stanza. Binding `0.0.0.0` is IPv4 only; IPv6 is not served.
- The web folder (E07-S01, D26): an explicit WEB_DIR is used as given. Without it, the server takes the first folder that exists of `./web` (a source checkout, as before), `web` next to the executable (`getExecutablePath`; the unpacked `.tar.gz`) and `/usr/share/pylos/web` (the `.deb`). So an installed `pylos-web` starts from any folder, and a checkout behaves as before. When none exists, it stops with an error naming all three, instead of starting a server that answers every page with 404. The check is a folder check only; a stray `web` folder in the current folder wins, which is the price of keeping the checkout's behaviour first. The choice is a pure function with the folder check passed in (`resolveWebDir`), so the order is tested without the disk. Rejected: a wrapper script in the package (owner's choice, D26), which would force a PORT whenever WEB_DIR is given and would not help the `.tar.gz`; an environment variable, which is invisible in `ps` and one more thing to document.
- Human play (S5) adds `POST /api/games/:id/move` and a `human` player on the same event stream; see `0025-human-play-protocol.md`.

Rejected: WebSockets (not needed until S5, and not even then, since a POST is enough). Rejected: servant (a heavier type-level API for five routes). Rejected: wai-app-static (a dependency for what is ten lines).

## Consequences

- The page and every file under `/static/` are sent with `Cache-Control: no-cache`, so the browser re-checks each file with the server (a cheap `304` when unchanged). Without it, after an upgrade a browser could keep running an old `app.js`, and new features (such as "You vs bot") would seem missing.
- Games are kept in memory only (N03). A restart forgets them.
- New dependencies: scotty, wai, warp, wai-extra and http-types, plus stm, which ships with GHC (D16).

## Brief ids

D16, D17, D20, D26, N02, N03, N05, P01
