# AGENTS.md — Pylos

## Project overview

Pylos is a personal learning project: an implementation of the Pylos board game.

- **Backend:** Haskell. It also serves a web frontend.
- **Build order:**
  1. A readable, pure reference rules engine, checked by QuickCheck properties.
  2. An optimised bitboard engine, checked against the reference by perft counts.
  3. Bots, plus a browser viewer for watching bot-vs-bot games. Development happens on a headless server.
- **The owner must be able to understand the code and the reasons behind it.** Explaining decisions is part of every task, not an extra.

Product context lives in `.ai/specs/product-brief.md`. Read it before any feature work. Its Business rules (R01–R08), Non-goals (N01–N05) and Decisions (D01–D22) are the protected contract. The active rules are R03–R08. R01, R02, N01 and N02 are superseded, but their rows are kept for history. Every row the current scope relies on is active and confirmed by the owner. The rules come from the owner's memory of the game. Whether they match the official rulebook is the untested assumption A01. No open question blocks the current scope (S5, human-vs-bot play). The backlog is in `.ai/specs/backlog.md` (issues #1–#12, #15, #18–#21 and #30–#36).

The toolchain (E01), the reference engine (E02), the bitboard engine (E03) and the bots with the live viewer (E04) exist; human-vs-bot play (E05) is next. Layout: `reference/` is the reference engine (cabal main library), `bitboard/` is the bitboard engine and the engine comparison (internal library `bitboard`), `bots/` the bots and match runner, `server/` the live game server, `web/` the browser viewer, `packaging/` the release package scripts, `app/` holds the `pylos-ref`, `pylos-bit`, `pylos-match` and `pylos-web` executables, `test/` the test suite, `golden/` the frozen perft and playout values, and `docs/adr/` the decision records. `README.md` has the install steps and how to play; `docs/technical.md` has the developer details (tools, tests, layout); `docs/rules.md` has the rules for players. GHC 9.10.1 and cabal come from ghcup (`source ~/.ghcup/env`). The system packages from the README (including `libgmp-dev`) are installed on this server.

## Task routing

| When the task involves… | Read first | Key rules |
|---|---|---|
| Product idea, scope, "should we build this" | `SDLC.md` (Discovery, Intake) | Start with `om-brainstorm` / `om-discover`; no code before a routed decision. |
| Game rules, moves, perft (reference engine) | `.ai/specs/product-brief.md` (R03–R08, D08, D09, D11, D12, D14) | Pure, readable code (D04, N04). Every rule function's Haddock comment cites the rule id it implements (D13). No performance tricks here. |
| Bitboard engine | Product brief D05 and D11; the reference engine modules once they exist | Must match the reference golden perft and playout files. Reference modules never import bitboard modules. |
| Bots, match runner | Product brief D15, D12; `bots/`; `docs/adr/0022-bots.md` | Pure `chooseMove` on the bitboard engine; one knob per bot (D15); a capped game is a draw (D12). |
| Web server and viewer | Product brief D16, D17; `docs/web-protocol.md`; `server/`, `web/`; `docs/adr/0023-web-server.md` | scotty + SSE, plain JS + vendored Three.js, no build step. Bind to 127.0.0.1 by default, to the home network only by an explicit option (`--lan`, D20, N05). Change the protocol doc together with server and client. |
| Decisions and explanations | `docs/adr/` (once created, D13) | Every non-obvious choice gets a decision record. A brief `proposal` is never recorded as accepted. |
| A feature design | `SDLC.md`, `.ai/specs/` | Specs live in `.ai/specs/` as `{YYYY-MM-DD}-{kebab-case-title}.md`; briefs in `.ai/specs/briefs/`. |
| Tests | `test/` (one tasty suite, grouped by story); `test/Gen.hs` for reachable positions | Engine behaviour ships with a QuickCheck property or HUnit rule test over reachable positions (`CODE_REVIEW.md`). |
| CI | `.github/workflows/ci.yml`, `cabal.project.freeze`, `docs/adr/0024-ci-and-freeze-file.md` | CI mirrors `validation.commands` (build with `-Werror`, then test, then the `web-rules` Node job); change both together. Regenerate the freeze file only on purpose, with `cabal freeze`. |
| Releases, packages | `.github/workflows/release.yml`, `packaging/`, `docs/adr/0028-release-packages.md` | A `v*` tag matching `pylos.cabal`'s version builds a `.deb` and a `.tar.gz` of `pylos-web` on `ubuntu-24.04`, smoke-tests them in a clean container and publishes the GitHub Release (D23–D25). Push a tag only with the owner's go-ahead. |
| Agent pipeline / process | `.ai/agentic.config.json`, `SDLC.md`, `.ai/trackers/github.md`, `.ai/browsers/agent-browser.md` | Change config and `SDLC.md` together; re-run `om-setup-agent-pipeline` when toolchain or labels change. |
<!-- discovery:routing-start -->
| Product discovery, a product brief, or a backlog | `.ai/specs/product-brief.md`, `.ai/specs/research/`, `.ai/specs/backlog.md`, `SDLC.md` → Definition of Ready and Product decisions as a protected contract | Non-goals, business rules and decisions in the brief are a protected contract — change them only with a superseding entry approved by their owner; synthetic personas are hypotheses, not evidence. |
<!-- discovery:routing-end -->
| Installed skills | `.claude/skills/`, `skills-lock.json` | Do not edit installed skills; put repo-specific deviations in `.ai/skills/<skill-name>/SKILL.md`. |

## Always / Ask first / Never

- **Always:** follow `SDLC.md`; run the validation gate before opening a PR; target `main`.
- **Ask first:** choosing or changing the stack, adding dependencies, adding CI.
- **Never:** commit secrets (`.env`, credentials, `.claude/settings.local.json`); push to `main` directly.

## Validation commands

Configured in `.ai/agentic.config.json` and `SDLC.md` → Validation gate, in this order:

- `cabal build all`
- `cabal test all` (about 30 s; it recomputes the golden perft values with the reference engine)
- `node test/web-rules-perft.mjs` (about 1 s; checks the browser's rules copy `web/rules.js` against the golden perft values)

## Pointers

- `SDLC.md`: ticket flow, label state machine, QA gate, claim protocol.
- `CODE_REVIEW.md`: review rules, auto-applied by `om-code-review`.
- `BACKWARD_COMPATIBILITY.md`: planned protected surfaces.
- `.ai/agentic.config.json`: pipeline configuration every skill reads.
