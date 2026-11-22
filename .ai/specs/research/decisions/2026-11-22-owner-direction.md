# D01–D07 — Direction confirmed by the project owner, 2026-11-22

- Date, owner: 2026-11-22, project owner (stated in their own messages; see `../interviews/2026-11-22-owner-account.md`)
- Context and the options weighed: the owner wrote these choices in their opening request and follow-up. The agent did not recommend them.
- Decision and why:
  - D01 — The backend is Haskell. The web frontend is served directly by the backend.
  - D02 — Playing bots come first. Bot-vs-bot games must be observable as a demo.
  - D03 — The demo runs in a web browser, because development happens on a headless server.
  - D04 — Work starts with a readable, pure Haskell reference engine whose correctness is checked by QuickCheck properties.
  - D05 — An optimised Haskell bitboard engine follows. It is checked against the reference by perft counts.
  - D06 — The code and the reasons for its decisions must be understandable to the owner. That is a goal in its own right.
  - D07 — Product discovery (`om-discover`) and a backlog (`om-backlog`) come before any spec or code.
- Consequences, and what would make us revisit it: every later slice builds on the reference engine as its oracle. The owner can revisit any of these at will.
- Status: active
