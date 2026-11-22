# AGENTS.md — Pylos

## Project overview

Pylos is a new, greenfield repository. It currently contains only the installed
Open Mercato agent skills (`.claude/skills/`, `.agents/skills/`, `skills-lock.json`)
and the agent-pipeline configuration under `.ai/`. There is no application code,
stack choice, or CI yet.

TODO: replace this paragraph with a one-paragraph description of what Pylos is,
who it is for, and the chosen stack, once that is decided. Then re-run
`om-create-agents-md` (or edit this file) to refresh the routing table below.

## Task routing

| When the task involves… | Read first | Key rules |
|---|---|---|
| Product idea, scope, "should we build this" | `SDLC.md` (Discovery, Intake) | Start with `om-brainstorm` / `om-discover`; no code before a routed decision. |
| A feature design | `SDLC.md`, `.ai/specs/` | Specs live in `.ai/specs/` as `{YYYY-MM-DD}-{kebab-case-title}.md`; briefs in `.ai/specs/briefs/`. |
| Application code | TODO — no source tree yet | TODO — record stack conventions here once code exists. |
| Tests | TODO — no test suite yet | Every fix ships with a regression test once a runner exists. |
| CI | TODO — no `.github/workflows/` yet | Mirror `validation.commands` in CI when it is added. |
| Agent pipeline / process | `.ai/agentic.config.json`, `SDLC.md`, `.ai/trackers/github.md`, `.ai/browsers/agent-browser.md` | Change config and `SDLC.md` together; re-run `om-setup-agent-pipeline` when toolchain or labels change. |
| Installed skills | `.claude/skills/`, `skills-lock.json` | Do not edit installed skills; put repo-specific deviations in `.ai/skills/<skill-name>/SKILL.md`. |

## Always / Ask first / Never

- **Always:** follow `SDLC.md`; run the validation gate before opening a PR; target `main`.
- **Ask first:** choosing or changing the stack, adding dependencies, adding CI.
- **Never:** commit secrets (`.env`, credentials, `.claude/settings.local.json`); push to `main` directly.

## Validation commands

None configured yet (`validation.commands` is empty in `.ai/agentic.config.json`).
Add them there — and in `SDLC.md` → Validation gate — once the stack exists.

## Pointers

- `SDLC.md` — ticket flow, label state machine, QA gate, claim protocol.
- `.ai/agentic.config.json` — pipeline configuration every skill reads.
- `CODE_REVIEW.md`, `BACKWARD_COMPATIBILITY.md` — not generated yet (no code to derive them from); generate with `om-setup-agent-pipeline` once there is code.
