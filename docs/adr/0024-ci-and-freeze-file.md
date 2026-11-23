# 0024. CI and the dependency freeze file

## Status

Accepted: the owner approved adding CI and a freeze file (2026-11-23). The details below were chosen by the agent and stay Proposed until the owner reviews them in the PR.

## Context

The validation gate (`cabal build all`, `cabal test all`) only ran on the machine of whoever opened a PR. Nothing checked `main` after a merge. `pylos.cabal` has version bounds, but inside those bounds `cabal update` can pick newer versions, so two machines can build different dependency sets.

## Decision

- **GitHub Actions**, one workflow, `.github/workflows/ci.yml`. The repository is on GitHub, so this needs no other service.
- It runs on PRs to `main` and pushes to `main`, on `ubuntu-latest`, one job. The steps are the validation gate, in the same order.
- GHC 9.10.1 is installed with `haskell-actions/setup`, the maintained Haskell setup action. It matches `with-compiler` in `cabal.project` (D10).
- The build uses `-Werror`. The code builds warning-free today, and this keeps it so. Locally, `cabal build all` stays without `-Werror`, so a warning does not block work in progress.
- The cabal store and `dist-newstyle` are cached, keyed on the OS, the GHC version and the hash of `pylos.cabal`, `cabal.project` and `cabal.project.freeze`. Without the cache every run rebuilds all dependencies (about 30 on `main`, more with the server), which takes minutes.
- A newer push to the same branch cancels the older run.
- **`cabal.project.freeze`** pins every dependency version, its flags and the Hackage `index-state`. It was made with `cabal freeze` on the branch that adds the bots and the server, so it already covers their packages (`scotty`, `warp` and others). Pins for packages a branch does not use are ignored. The local `pylos` package is not pinned.

Rejected: a build matrix over several GHC versions. D10 pins one compiler. Rejected: Stack or Nix. D10 chose cabal.

## Consequences

- Every PR shows a green or red check. `main` is checked after every merge.
- Local builds and CI resolve the same versions.
- Upgrading a dependency is now a deliberate step: delete or edit `cabal.project.freeze`, run `cabal update` and `cabal freeze`, and review the diff in a PR.
- A PR that adds a new dependency should run `cabal freeze` again. A package missing from the freeze file is not pinned, so its version can drift.

## Brief ids

D10
