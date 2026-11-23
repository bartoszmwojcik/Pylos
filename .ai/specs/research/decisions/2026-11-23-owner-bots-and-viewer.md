# Bots and viewer settled by the project owner, 2026-11-23

- Date, owner: 2026-11-23, project owner (answers given in the E01–E03 task session)
- Context and the options weighed: Q03 (which bots, and how they are judged) and Q02 (the form of the web demo and its technology) blocked S3 and S4. The agent proposed several parameters per bot, and a web stack (scotty + warp, Server-Sent Events, plain JavaScript with Three.js).
- Owner's answers, as given:
  - Q03: "greedy, alpha-beta, mcts - can they have different parameters each?" After the agent listed the possible parameters: "Yes, fewer knobs".
  - Q02: "live games, 3D, framework please propose". On the proposal: "there will be soon more epics to develop: interface for user to play against bot. otherwise the proposal is ok for me."
- Decision and why:
  - D15: random, greedy, alpha-beta and MCTS bots, with one knob each (greedy weights, alpha-beta depth, MCTS iterations).
  - D16: scotty + warp, SSE for updates, HTTP for commands, plain JS + vendored Three.js. Human play (S5) adds one POST endpoint and reuses the event stream, which answers the owner's note about the coming human-vs-bot epic.
  - D17: the viewer shows live games in 3D. Replay is not requested.
- Consequences, and what would make us revisit it:
  - How bots are judged is not settled. The match runner reports wins, losses and draws (a capped game is a draw, D12).
  - S5 (human vs bot) is the next epic and is designed for, but not built.
- Status: active
