# AGENTS.md — Pylos

## Project overview

Pylos is a personal learning project: an implementation of the Pylos board game.

- **Backend:** Haskell. It also serves a web frontend.
- **Build order:**
  1. A readable, pure reference rules engine, checked by QuickCheck properties.
  2. An optimised bitboard engine, checked against the reference by perft counts.
  3. Bots, plus a browser viewer for watching bot-vs-bot games. Development happens on a headless server.
- **The owner must be able to understand the code and the reasons behind it.** Explaining decisions is part of every task, not an extra.

Product context lives in `.ai/specs/product-brief.md`. Read it before any feature work. Its Business rules (R01–R06), Non-goals (N01–N04) and Decisions (D01–D13) are the protected contract. Rows marked `proposal` are not yet confirmed by the owner. The open points to settle are OP1–OP9, listed in `.ai/specs/briefs/2026-11-22-pylos-reference-engine.md`. The backlog is in `.ai/specs/backlog.md` (issues #1–#12).

The repository is greenfield. Today it holds only the installed agent skills (`.claude/skills/`, `.agents/skills/`, `skills-lock.json`) and the pipeline configuration under `.ai/`. No Haskell code exists yet, and the Haskell toolchain is not installed on the server yet. Backlog item E01-S01 (#5) covers both.

## Task routing

| When the task involves… | Read first | Key rules |
|---|---|---|
| Product idea, scope, "should we build this" | `SDLC.md` (Discovery, Intake) | Start with `om-brainstorm` / `om-discover`; no code before a routed decision. |
| Game rules, moves, perft (reference engine) | `.ai/specs/product-brief.md` (R01–R06, D08, D09, D11, D12) | Pure, readable code (D04, N04). Every rule function's Haddock comment cites the rule id it implements (D13). No performance tricks here. |
| Bitboard engine | Product brief D05 and D11; the reference engine modules once they exist | Must match the reference golden perft and playout files. Reference modules never import bitboard modules. |
| Bots, match runner | Product brief Scope (Later), Q03 | TODO: not yet specified |
| Web server and viewer | Product brief D01, D03, Q02 | The backend serves the frontend. TODO: framework not yet chosen (OP7) |
| Decisions and explanations | `docs/adr/` (once created, D13) | Every non-obvious choice gets a decision record. A brief `proposal` is never recorded as accepted. |
| A feature design | `SDLC.md`, `.ai/specs/` | Specs live in `.ai/specs/` as `{YYYY-MM-DD}-{kebab-case-title}.md`; briefs in `.ai/specs/briefs/`. |
| Tests | TODO: no test suite yet (E01-S01) | Engine behaviour ships with a QuickCheck property or HUnit rule test over reachable positions (`CODE_REVIEW.md`). |
| CI | TODO: no `.github/workflows/` yet | Mirror `validation.commands` in CI when it is added. |
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

None are configured yet: `validation.commands` is empty in `.ai/agentic.config.json`, because no toolchain exists. When E01-S01 (#5) lands, add these in order, both in the config and in `SDLC.md` → Validation gate:

- `cabal build all`
- `cabal test all`

## Pointers

- `SDLC.md`: ticket flow, label state machine, QA gate, claim protocol.
- `CODE_REVIEW.md`: review rules, auto-applied by `om-code-review`.
- `BACKWARD_COMPATIBILITY.md`: planned protected surfaces.
- `.ai/agentic.config.json`: pipeline configuration every skill reads.
