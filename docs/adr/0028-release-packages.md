# 0028. Release packages and the release workflow

## Status

Accepted for the scope (D23–D25, the owner's choices on 2026-11-26: Ubuntu 24.04 amd64, only `pylos-web`, a workflow on a version tag; adding this CI was approved with D25). The details below were chosen by the agent and are reviewed by the owner in the PR.

## Context

Until now Pylos could only be built from source: ghcup, GHC 9.10.1, system libraries and a build of a few minutes (P05). The owner wants an install without compiling, published as GitHub Release `v0.1.0` (D23). Only the game server is packaged and there is no service (D24). Since #44, `pylos-web` without WEB_DIR finds `web/` next to itself or in `/usr/share/pylos/web` (D26), so a package only has to put the files there.

## Decision

- **Two files per release**, built by `packaging/build-packages.sh` (a plain bash script you can run locally):
  - `pylos_<version>_amd64.deb` installs `/usr/bin/pylos-web`, `/usr/share/pylos/web/` and `/usr/share/doc/pylos/README.md`. The package name is `pylos`, so it is removed with `sudo apt remove pylos`.
  - `pylos-web-<version>-linux-amd64.tar.gz` holds `pylos-web-<version>/` with `pylos-web`, `web/` and `README.md`, side by side.
- **The `.deb` is built with `dpkg-deb` from a staged folder**, not with the Debian source-package tools (`debhelper`, `debian/rules`). Those are made for distribution maintainers and add a dozen files to learn. A staged folder plus one `control` file is the whole idea of a binary package, visible in about 40 lines.
- **Depends is computed, not written by hand.** `dpkg-shlibdeps` reads the binary's shared libraries and names the Ubuntu packages and minimum versions that provide them. GHC links its Haskell code statically, but the C library, libgmp, libffi and zlib dynamically, and which of these the binary needs is a property of the build (A07). A hand-written list would drift.
- **The binary is stripped** (debugging symbols removed): a smaller download, the same program.
- **Built on `ubuntu-24.04`, pinned.** A binary needs the C library version it was built against, or newer. `ubuntu-latest` will move to a newer Ubuntu one day, and the package would then stop installing on 24.04 (D23).
- **`.github/workflows/release.yml`, separate from `ci.yml`.** It runs on a pushed `v*` tag. Its jobs:
  1. `build`: checks that the tag matches `pylos.cabal`'s version, runs the full validation gate, and builds the two files.
  2. `smoke-test`: in a clean `ubuntu:24.04` container, installs the `.deb` with `apt` (which pulls in the Depends from the Ubuntu archive) and starts `pylos-web` from an empty folder. It then fetches the page and two scripts, and plays a random-vs-random game through the API to the end. It does the same from the unpacked `.tar.gz`, with the `.deb`'s web folder hidden. The script speaks HTTP through bash's `/dev/tcp`, so no extra package (curl and its libraries) can hide a missing dependency.
  3. `publish`: only for a tag, only after both checks pass. It creates the GitHub Release with the two files, using the workflow's own token. Only this job has write permission.
- **The same workflow runs on pull requests that touch the packaging** (the scripts, the workflow, `pylos.cabal`, the cabal project and freeze files), without the publish job. So a broken package is caught in review, not after a tag is pushed.
- **The version lives in `pylos.cabal`** and is now `0.1.0` (Q09). The tag is `v` plus that version. A mismatch stops the workflow before anything is built.
- **No new Haskell dependencies.** The workflow uses GitHub's own actions and the tools on the runner (`dpkg-dev`, `strip`, `docker`, `gh`).

Rejected:
- A static binary (musl or `-optl-static`): it would run on any Linux, but GHC's static linking against glibc is fragile and musl needs a different toolchain. D23 asks for Ubuntu 24.04 only.
- Building on 22.04 for wider reach: the owner chose 24.04 (D23).
- A container image: Later (D23).
- A systemd service in the package: the owner chose none (D24). The server never runs unattended, so the `--lan` exposure of D20 is unchanged.
- A release action from the marketplace: `gh release create` on the runner does the same with one command and no third-party code holding a write token.

## Consequences

- Cutting a release: set `version:` in `pylos.cabal`, merge to `main`, push the tag `v<version>` on that commit. The workflow does the rest, or publishes nothing.
- If a tagged run fails, no Release exists. Fix it on `main`, then move the tag only with the owner's approval (E07-S04).
- The file names and install paths above become something users rely on (`BACKWARD_COMPATIBILITY.md`).
- The `Maintainer` field is a placeholder address (`pylos@invalid`, a reserved domain that never delivers). Debian requires the field. The project has no public contact address, and the owner's own address stays private.

## Brief ids

D20, D23, D24, D25, D26, A07, P05, Q09
