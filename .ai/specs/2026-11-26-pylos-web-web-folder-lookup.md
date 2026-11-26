# pylos-web finds its web folder (E07-S01)

- Issue: #44 (epic #43, S6)
- Design authority: `.ai/specs/product-brief.md`, D26 (owner, 2026-11-26)
- Status: implemented together with this spec (one branch; see the PR)

## TLDR

`pylos-web [--lan] [PORT] [WEB_DIR]` without WEB_DIR serves the first folder that exists of `./web`, `<folder of the executable>/web` and `/usr/share/pylos/web`. An explicit WEB_DIR is used as given. When none exists, the server stops with exit code 2 and names every folder it tried. This lets the packaged command (E07-S02) start from any folder, while a source checkout behaves as before.

## Decisions in play

- D26 — the lookup order above; explicit WEB_DIR unchanged (active, owner)
- D20, N05 — binding is unchanged: 127.0.0.1 unless `--lan`

## Edge cases

- A source checkout started in the project folder: `./web` wins, as before.
- Started elsewhere from a checkout's build output (`$(cabal list-bin pylos-web)` in another folder): the executable lives under `dist-newstyle/`, so neither `./web` nor the next-to-executable folder exists; unless `/usr/share/pylos/web` exists, the server stops with the list. Before this change it started and answered 404. Pass WEB_DIR in that case.
- A stray `web` folder in the current folder that is not Pylos's: it wins (folder check only). Accepted by D26's order.
- An explicit WEB_DIR that does not exist: used as given, as before (the server answers 404).

## Implementation Plan

1. `app/web/WebArgs.hs`: `optWebDir :: Maybe FilePath`; add `webDirCandidates` and `resolveWebDir`, the folder check passed in.
2. `app/web/Main.hs`: resolve with `getExecutablePath` and `doesDirectoryExist`; print the folder; exit 2 with the error.
3. `pylos.cabal`: `directory` and `filepath` in the `pylos-web` stanza (both already in the build plan).
4. `test/WebArgsTests.hs`: the order, explicit WEB_DIR, and the error naming every folder.
5. `docs/technical.md`, ADR 0023: the lookup order and why.
