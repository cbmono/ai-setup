# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Public, opinionated Claude Code defaults for Node.js / TypeScript projects. It ships subagents, user-invocable slash commands (including a Boris Cherny tips command), a permissions baseline, and a CLAUDE.md template that users drop into consumer projects. No application code, no build, no test suite. Work here is editing markdown and JSON under `.claude/` plus the top-level `README.md`.

## Layout

- `.claude/claude-defaults.md` — behavioural defaults (planning, thinking, subagents, verification) that consumer projects pull into their own `CLAUDE.md` via `@.claude/claude-defaults.md`. Edit this to change the per-session rules everywhere at once.
- `.claude/agents/` — subagent definitions (frontmatter: `name`, `description`, optional `model`, `isolation`).
- `.claude/commands/` — slash commands triggered by `/<name>`. Filename = command name. No frontmatter. Use `$ARGUMENTS` for user-supplied args. **Never put a `README.md` in here** — Claude Code would register it as `/README`.
- `.claude/commands/boris.md` — the `/boris` command: Boris Cherny's Claude Code tips. The first line in the body carries the version — bump it when content changes materially.
- `.claude/settings.json` — checked-in, team-shared permissions baseline.
- `.claude/settings.local.json` — per-machine overrides, gitignored.
- `.claude/settings.mempalace.example.json` — opt-in mempalace MCP + hooks, for users to copy from.
- `.claude/potential-bugs.md` — append-only output sink for `deep-bug-scan`.
- `.claude/techdebt.md` — rolling backlog for `/techdebt` (deferred items only, not a log). Created on first run.
- `.claude/README.md` — human inventory + commands-vs-skills note. Must stay in sync with the top-level `README.md` when agents/commands change.
- `README.md` (root) — public-facing setup guide.

## Conventions when editing

- **Agents must stay generic.** No references to specific projects, codebases, or internal helpers. Agents should infer the toolchain from `package.json` scripts and whatever `CLAUDE.md` the consumer project ships.
- **Commands must stay generic too.** Same rule — no project-specific paths, no internal tooling. Commands ship to consumers.
- **Inventory tables in two places.** When you add/remove/rename an agent or command, update both `.claude/README.md` and the top-level `README.md`.
- **`boris.md` is external content.** Treat edits surgically — bump the version line at the top when you change it. The source is howborisusesclaudecode.com.
- **Opus 4.7 is the target.** Guidance in agents and the CLAUDE.md template assumes 4.7 behavior (adaptive thinking, explicit subagent spawning, xhigh default). Don't rewrite for 4.6.
- **`settings.json` is checked in.** Only add permission entries that are safe for everyone on a team. Per-machine additions go in `.claude/settings.local.json` (gitignored).
- **Don't invent tool invocations.** If a command references `gh stack`, `mempalace`, `coderabbit`, etc., check the actual command surface before committing — users run these verbatim.
- **After adding/moving commands or agents, restart Claude Code and verify registration** — `/exit`, then `claude`. New files aren't picked up mid-session.

## Out of scope

- Don't add CI, GitHub Actions, or a build step — this is a config-only repo.
- Don't add a `package.json` unless you have a reason tied to tooling for editing markdown.
