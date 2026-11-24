# 0025. Human play on the server

## Status

Proposed. D18 (one human against one bot, legal moves only, no undo) and D16 (commands up over HTTP, updates down over SSE) are the owner's decisions. Everything below is an implementation choice made by the agent for E05-S02 (#32). The owner reviews it in the PR.

## Context

S5 lets the owner play a bot in the browser (D18). ADR 0023 left room for this: one more command, `POST /api/games/:id/move`, and a `human` player kind, on the same event stream. Four things needed a choice:

1. How the server says that a game waits for the human, so a browser that reconnects knows it is its turn.
2. Whether `delayMs` slows the bot's reply.
3. How to keep a posted move and the game thread from both changing a game at once.
4. Whether an abandoned human game should hold one of the 8 running-game places.

## Decision

**The human is a player value.** `white` or `black` in `POST /api/games` may be `"human"` instead of a bot spec. At most one side may be human (D18); two humans are a `400`. The snapshot, the summary and so the game's record show `"human"` as that side's player, just as they show a bot spec.

**Two new snapshot and summary fields**, both additive:

- `human`: the colour the human plays, or `null` in a bot-vs-bot game. It never changes during a game.
- `waitingFor`: the human's colour while the game waits for the human's move, otherwise `null` (the bot is thinking, the game has finished, or there is no human). The browser enables input exactly when this is its colour.

Rejected: a single `"turn": "human" | "bot"` field. Two plain fields say the same thing without a new vocabulary, and `waitingFor` is `null` in every game that needs no input.

**The move route.** `POST /api/games/:id/move` with `{"move": "<D09 move>"}`, written exactly as in the snapshot's `moves` list. The server reads it with the reference parser and looks it up among the bitboard engine's legal moves, comparing whole moves, so take-backs may come in any order. A legal move on the human's turn answers `200` with the data of its `move` event, which is also broadcast. The bot's reply comes only on the event stream. The POST does not wait for it, because a deep bot can think for seconds and the browser already listens there (D16). Everything else is `400 {"error": "..."}`: a body that is not `{"move": string}`, text that is not a move, an illegal move, a move while the bot is to move, a move after the game has ended, a move in a bot-vs-bot game. The game is unchanged in every one of these cases. An unknown game is `404`.

**`delayMs` only paces bot-vs-bot games.** In a human game every bot move is either the opening move or the reply to the human, and waiting makes the human wait for nothing. The bot moves as soon as it has chosen. The field is still accepted and shown. Animating the reply is the browser's job.

**One writer at a time, decided inside STM.** A game's state is one `TVar`. The side to move is the only one allowed to change it:

- `submitMove` checks the turn, the game status and the legality, then applies the move and writes the `move` event, all in one STM transaction. If two moves are posted at the same moment, STM runs the two transactions one after the other. The second sees that the bot is now to move and is refused (`NotYourTurn`). A refused move writes nothing.
- The game thread waits with STM `retry` while the human is to move. `retry` blocks the thread until the state `TVar` changes. Then it wakes at once, at no processor cost while it waits. It thinks outside any transaction and writes its move in one transaction. It can write the state it read before thinking, because during the bot's turn `submitMove` refuses every move, so nobody else can have changed it.
- The rules of acceptance are a pure function (`checkHumanMove`), tested without threads.

Rejected: an `MVar` or channel mailbox that sends posted moves to the game thread, which then answers. It also works, but it needs a reply channel per request and a timeout in case the thread has died. The STM version keeps the existing rule ("state changes and events are written together, atomically") and has no extra moving parts.

**The running limit counts games that use the processor.** The limit of 8 (ADR 0023) exists so the server stays responsive. A game waiting for the human uses no processor time, so it does not count. Otherwise, after eight abandoned games (a closed tab, a reload), no new game could start until a restart.

**At most 8 bots think at once.** Because waiting human games are not counted, many human games can be open, and each human move starts a bot search. Admission alone would therefore not bound the work. So every bot thinks inside one of 8 server-wide places (`maxThinking`, a counter in STM). A bot whose turn comes while all places are busy waits, blocked in STM without using the processor, and replies when a place is free. Waiting was chosen over refusing the move with an error, because the human's move is legal and has already been applied. `bracket_` gives a place back even if a bot throws, so a failed game cannot hold a place for ever.

## Consequences

- The browser (E05-S03) needs only `postMove` and the existing event stream. On reconnect, the snapshot's `waitingFor` says whether to enable input.
- Abandoned human games stay in memory until the server restarts (N03, as for every game). They cost a sleeping thread and a few kilobytes each. If that ever matters, a time-out that ends idle human games is a small follow-up.
- A bot that is thinking cannot be interrupted. No undo (D18) means nothing needs to.
- `delayMs` means less than it did: in a human game it is ignored. `docs/web-protocol.md` says so.

## Brief ids

D18, D16, D12, R03–R08, N03
