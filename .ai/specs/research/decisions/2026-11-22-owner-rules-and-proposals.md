# Rules and proposals settled by the project owner, 2026-11-22

- Date, owner: 2026-11-22, project owner (answers given in the `om-discover --refresh` session)
- Context and the options weighed: the agent asked about the open rule points R02, R03 and R05 and the move definition D08, and asked the owner to confirm or change the other agent proposals (D09–D13, N01–N04). For each rule question the agent gave the current proposal, its known alternative, and a "not checked yet" option. For D08 the agent recommended the compound move.
- Owner's answers, as given:
  - Take-back: "may take back 0,1,2. the same rule if a player completes row of 4 vertical or horizontal. but not diagonal"
  - Empty reserve: "That player loses"
  - Raise onto a square the ball supports: "No"
  - Move definition: "Compound move (Recommended)", which accepts the agent's recommendation
  - Other proposals: "Confirm all as written"
- Decision and why:
  - Take-back is optional, 0–2 balls. This supersedes proposal R02, which made it mandatory (1–2).
  - Completing a horizontal or vertical row of 4 of one's own colour triggers the same take-back. A diagonal row does not. This supersedes R01's "without the lines variant" and N01.
  - R05 is confirmed: the player to move with an empty reserve loses.
  - R03 is confirmed: a raised ball may not land on a square it supports.
  - D08 is confirmed: one move is a compound value. It began as the agent's recommendation.
  - D09, D10, D11, D12, D13, N02, N03 and N04 are confirmed as written. N01 conflicts with the row rule above (see Consequences).
- Consequences, and what would make us revisit it:
  - These answers record the owner's choice of rules for this project. The record does not show where the answers came from (the printed rulebook, the publisher's rules, or the owner's preference), so A01 "matches the official rules" is not settled by it.
  - A batch confirmation of N01 ("lines variant not built") contradicts the row-of-4 answer. The row answer is the specific one, so the batch confirmation does not cover N01. That conflict goes back to the owner.
  - Still open: whether rows on level b (3 long) count, and how many balls may be taken back when one move completes two formations.
- Status: active

## Follow-up answers, same session (second round)

- Owner's answers, as given (picked from the agent's listed options):
  - Rows on level b: "No, only rows of 4 on a"
  - One ball completing two shapes at once: "0–2 in total"
  - Source of the rule answers: "Memory of the rules"
  - Replacing N01 and R01's "without lines": "Yes, replace them"
- Decision and why:
  - The row rule applies only to complete horizontal or vertical rows of 4 on level a. Level b rows of 3 and all diagonals do not count.
  - A move may take back 0–2 balls in total, however many shapes it completes. D08's limit of 0–2 take-backs per move stands.
  - The owner approves superseding N01 and R01's exclusion of the lines rule.
- Consequences, and what would make us revisit it:
  - The rule answers come from the owner's memory, not from a rulebook that was read. They are the owner's chosen rules for this project. Whether they match the official Gigamic rules is still untested (A01).
  - Revisit if the owner reads the rulebook and finds a difference, and wants the engine to follow it.

## Third round, same session

- Owner's answers, as given (picked from the agent's listed options):
  - R04, "Is a ball free exactly when no ball rests on it, and are take-backs done one at a time, so that removing the first ball can free a second?": "Yes, as written"
  - R08 geometry, "4×4, 3×3, 2×2 and 1 … all 4 squares under it filled … 15 balls per player": "Yes"
  - R07 inherited clauses, "a shape counts whether completed by placing or by raising; 2×2 squares count on levels a, b and c": "Yes, both"
  - R06 and the remaining R03 clauses: the owner asked for more information. The agent explained both and asked again.
    - R06: the agent gave two options and recommended the first. Option one: endless games are stopped by the match runner's ply cap, with no draw rule in the engine. Option two: the engine has a draw rule. The agent's reasons were that the first keeps positions history-free, keeps perft and the golden files well defined (D04, D11), and gives the bitboard engine less to match. The tradeoff it named is that a draw comes from an arbitrary cap, not a game rule. The agent said it does not know whether the official rules have a draw rule. Owner: "Runner's cap (Recommended)".
    - R03: the agent explained three details: a raise goes only upward; support is checked after the ball leaves its square; a raise replaces placing a new ball. Owner: "Confirm all three".
- Decision and why: R04, R06, the R08 geometry, R03 in full and R07 in full are confirmed as the owner's rules. All began as agent proposals. R06 is an agent recommendation the owner accepted. The owner answers from memory (A01).
