# Backward compatibility

The surfaces below come from `.ai/specs/product-brief.md`. Each becomes protected as soon as it lands on `main`. The first four are implemented by E02/E03 (`reference/Pylos/Reference/Notation.hs`, `Record.hs`, `golden/`, `app/ref`, `app/bit`). Update this file when a surface is first implemented.

| Surface | Planned in | What counts as breaking | Required path |
|---|---|---|---|
| Move notation (`a23`, `a11-b22`, ` x a23 a24`) | D09 | Any change that makes previously valid text parse differently or fail to parse | A superseding decision in the brief, a migration note, and old records still readable or converted by a provided tool |
| JSON game-record format (`version` 1, docs/adr/0017) | D09 | Removing or renaming fields, or changing the meaning of `moves` or `result` | The same as for notation, plus a version field bump |
| Golden perft and playout files | D11 | Any change to a stored value | Only through an explained regeneration tied to an owner-approved rule or decision change |
| `pylos-ref` and `pylos-bit` CLI commands and arguments | S1, S2 | Removing or renaming a command or flag, or changing its output format used by scripts | A deprecation note in the README for one release before removal |
| HTTP routes and SSE events of the viewer | S4 (not yet specified) | TODO: define when S4 is specified | TODO |
