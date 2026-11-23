# Screen anatomy: Pylos viewer

Repository override of the portable template. These patterns come from the
proposed viewer design in `.ai/prototypes/viewer-3d/` (Acceptance: pending).
No production UI exists yet, so treat everything here as a proposal until
the owner accepts it.

- Shell: one top bar (brand, Library / Live, current file, server status). No sidebar.
- Viewer: the 3D board on the left with floating controls (camera presets
  top left, visible levels top right, transport bottom). A 21 rem side column
  holds, in order: the status card (result, replay error, connection), players
  and reserves, the current move, and the move list.
- Status that ends or blocks the game goes in the side column, never over the
  board. Only the slim "Jump to live" bar floats over the board, above the transport.
- Narrow frames (≤ 56 rem): the board is on top and the panels sit below in two
  columns. Phones (≤ 36 rem): controls move out of the canvas, above and below it.
- Notation (D09) is always monospace. Labels are uppercase Chakra Petch.
  Body text is Barlow.
- Corners are 2 px. Panels have a chamfered top-left corner. There is one
  accent colour (ice blue) for the current selection and the last move.
- Dark theme only.
