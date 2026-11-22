# Interview — project owner (sole developer and sole intended user), 2026-11-22

Source: the owner's own messages in the om-brainstorm / om-discover session of 2026-11-22. These are not answers to interview questions. The owner wrote them unprompted.

- Recent situation or task the person described: the owner wants to build a web application that implements the board game Pylos. Development happens on a server without a display.
- What they did, step by step: nothing has been built yet. The repository holds only installed agent skills. The owner proposed a starting order: a pure reference engine first, then an optimised bitboard engine checked against it.
- What worked, what did not, and any consequences they described: nothing was described. Because there is no display, a local GUI demo is not an option for them.
- Other approaches they tried and how those worked: none were described.
- The outcome they were trying to achieve and what happened: playing bots, checking how they play, and being able to watch a demo of such a game. The owner also wants to understand the code and the reasons for its design.
- Verbatim quotes worth keeping (mark each as quote):
  - quote: "backend in haskell, frontend web, can be served directly from backed."
  - quote: "I want to start with development of playing bots, chceck them playing, but being possible observing demo of such game."
  - quote: "Since development is on server without display, i thing demo should go via web."
  - quote: "I want to understand the ocde, decisions why it is like that"
  - quote: "1. A readable pure Haskell reference with QuickCheck properties. 2. The optimised Haskell bitboard engine, checked against the reference by perft counts."
  - quote: "I'd prefer going thru om-discover and om-backlog first."
- What they explicitly did not care about: nothing was stated.
- Interviewer's own remarks (kept separate from what was said):
  - This account supports only the owner's own situation and goals.
  - It says nothing about any other users. None are in scope.
  - The owner then told the agent to continue autonomously on reasonable assumptions. That means agent-chosen rule details and design choices remain proposals.
