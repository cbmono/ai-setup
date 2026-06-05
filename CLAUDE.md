# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@.claude/claude-defaults.md
@.claude/MEMORY.md

<!-- Eat our own dog food: load the same defaults + memory artifacts we ship to consumers when working on this repo itself. -->

## What this repo is

Public, opinionated Claude Code defaults for Node.js / TypeScript projects. It ships subagents, user-invocable slash commands, a permissions baseline, and a CLAUDE.md template that users drop into consumer projects. No application code, no build, no test suite. Work here is editing markdown and JSON under `.claude/` plus the top-level `README.md`.

## Layout

- `.claude/claude-defaults.md` — behavioural defaults (planning, thinking, subagents, verification) that consumer projects pull into their own `CLAUDE.md` via `@.claude/claude-defaults.md`. Edit this to change the per-session rules everywhere at once. Keep it under ~20 lines — it's re-sent every turn in every consumer project. Don't restate guidance that already lives in Claude Code's built-in system prompt.
- `.claude/MEMORY.md` — project conventions Claude should know about, currently a slash-command natural-language trigger table. Optional `@.claude/MEMORY.md` import from a consumer's `CLAUDE.md`; not auto-loaded otherwise.
- `.claude/agents/` — subagent definitions (frontmatter: `name`, `description`, optional `model`, `isolation`).
- `.claude/commands/` — slash commands triggered by `/<name>`. Filename = command name. No frontmatter. Use `$ARGUMENTS` for user-supplied args. **Never put a `README.md` in here** — Claude Code would register it as `/README`.
- `.claude/skills/` — auto-invocable capabilities (one subdirectory per skill, each with a `SKILL.md` carrying YAML frontmatter). Ships `test-locators` (proactive frontend test-attribute guidance); see `.claude/skills/README.md` for the convention.
- `.claude/settings.json` — checked-in, team-shared permissions baseline, the small set of universally-safe hooks that no-op when not applicable (currently: format-on-write), and the default `enabledPlugins` (currently: `superpowers`, `typescript-lsp`, `security-guidance` from `claude-plugins-official`).
- `.claude/settings.local.json` — per-machine overrides, gitignored.
- `.claude/settings.mempalace.example.json` — opt-in mempalace MCP + hooks, for users to copy from.
- `.claude/settings.plugins.example.json` — opt-in MCP-backed plugins (github, linear, context7), for users to copy from.
- `.claude/hooks/` — executable hook scripts referenced from `settings.json`. Must be self-detecting (no project-specific paths, no toolchain assumptions) and exit 0 on every non-applicable input so they can ship to every consumer.
- `.claude/potential-bugs.md`, `.claude/techdebt.md`, `.claude/plans/` — runtime output of `/scan`, `/techdebt`, `/plan`. Auto-created in target projects on first run, gitignored, never seeded in this repo. The `/plan` slug is the Jira key when detected on branch / recent commits, else a kebab-case verb-prefixed summary (`feat-…`, `fix-…`, `chore-…`); plan files ride with the related PR(s) and are deleted once the work merges to main.
- `.claude/README.md` — human inventory + commands-vs-skills note. Must stay in sync with the top-level `README.md` when agents/commands change.
- `README.md` (root) — public-facing setup guide.
- `install.sh` (root) — user-wide installer. Per-entry symlinks the tracked `.claude/` defaults **into** the real `~/.claude` (never a whole-dir symlink, so runtime state stays out of the repo and an existing `~/.claude` isn't clobbered). Auto-discovers what to link via `git ls-files .claude`, minus a small `EXCLUDE` denylist (repo docs, templates, `settings.json`). Idempotent; backs up anything it would overwrite. `--uninstall` removes only the symlinks it created (leaves runtime state, real files, and backups). When you add a tracked default that should NOT land in `~/.claude`, add it to `EXCLUDE`.
- `entities.json`, `mempalace.yaml` (root) — gitignored local mempalace state. Not source, don't edit or commit.

## Commands vs skills

This repo ships mostly **commands** (`.claude/commands/<name>.md`, invoked only when the user types `/<name>`). Skills (`.claude/skills/<name>/SKILL.md`) auto-invoke via intent matching. When asked to add a capability, default to a command unless proactive invocation is explicitly wanted — `test-locators` is the one skill so far, because adding test attributes should happen automatically while building frontend, not on a typed command. See `.claude/README.md` for the full distinction.

## Conventions when editing

- **Agents must stay generic.** No references to specific projects, codebases, or internal helpers. Agents should infer the toolchain from `package.json` scripts and whatever `CLAUDE.md` the consumer project ships.
- **Commands must stay generic too.** Same rule — no project-specific paths, no internal tooling. Commands ship to consumers.
- **Inventory lives in three places, with different jobs.** Agent `description:` frontmatter is the dispatch trigger Claude Code matches on — keep it terse and action-shaped. The "Purpose" columns in `.claude/README.md` and the top-level `README.md` are human-readable and may be more verbose. They need not be word-for-word identical, but none of the three may drift from what the agent actually does. When you add, remove, rename, or materially change an agent, command, or skill, walk all three. If `claude-defaults.md` mentions the agent by name, update it there too.
- **The fenced CLAUDE.md template in `README.md` (the "Bootstrap a CLAUDE.md" section) is consumer-facing.** Edit it as boilerplate users paste into their own projects, not as guidance for this repo. Don't expand the example bullets — they're intentionally placeholders.
- **`settings.json` is the checked-in, team-shared baseline.** Permissions live here; MCP servers and env vars do not (those stay in opt-in example files like `settings.mempalace.example.json` so consumers choose to wire them up). Hooks may ship here, but only if they are **universally safe** — must no-op cleanly when the project doesn't match (e.g. format-on-write checks for a declared formatter in `package.json` and exits 0 otherwise). Anything narrower goes in an opt-in `.example.json`. Per-machine additions go in `.claude/settings.local.json` (gitignored).
- **Default plugins (`enabledPlugins`) live in `settings.json`; MCP-backed plugins do not.** Only enable a plugin by default if it's broadly safe, stack-aligned, and doesn't duplicate a command/agent this repo already ships (so not `code-review`/`pr-review-toolkit`/`code-simplifier`/`commit-commands`/`feature-dev`). Plugins from `claude-plugins-official` need no `extraKnownMarketplaces`. Plugins that wire up external services via MCP (github, linear, context7) follow the MCP rule above — opt-in in `settings.plugins.example.json`, not the baseline. When you change the default set, update the Plugins tables in both `README.md` and `.claude/README.md`.
- **Permission patterns: prefer the simple shapes.** `Bash(cmd:*)` (trailing wildcard, equivalent to `Bash(cmd *)`) and exact-string matches are reliable. Mid-pattern wildcards (`Bash(git push * --force)`) are documented and supported, but per Anthropic's own docs they're fragile against flag re-ordering, redirects, env-var substitution, and extra whitespace — i.e. anyone trying to evade is likely to. Don't ship them as deny rules. If you need argument-level filtering, use a `PreToolUse` hook in `settings.local.json` that inspects the full command line.
- **Don't ship deny rules that block harmless files.** `.env.example` / `.env.template` / `.env.sample` are templates meant to be read; only block real env files (`.env`, `.env.local`, `.env.*.local`). Same logic for SSH: block `id_rsa` / `id_ed25519` / `id_ecdsa`, not `*.pub` (public keys are meant to be shareable).
- **Opus 4.7 is the target.** Guidance in agents and the CLAUDE.md template assumes 4.7 behavior (adaptive thinking, explicit subagent spawning, xhigh default). Don't rewrite for 4.6.
- **Don't invent tool invocations.** If a command references `gh stack`, `mempalace`, `coderabbit`, etc., check the actual command surface before committing — users run these verbatim.
- **After adding/moving commands or agents, restart Claude Code and verify registration** — `/exit`, then `claude`. New files aren't picked up mid-session.
- **Don't rename or move `.claude/claude-defaults.md`.** Consumer projects pin it as `@.claude/claude-defaults.md` in their own CLAUDE.md; renaming or relocating it silently breaks every downstream setup that pulled from this repo.

## Verifying a change

No build, lint, or test suite — markdown + JSON only. The verification loop is:

1. `/exit` and relaunch `claude` so the session re-scans `.claude/agents/` and `.claude/commands/`.
2. Invoke the changed command (`/<name>`) or ask Claude to use the changed agent; confirm it registers without a `skills:` prefix and behaves as intended.
3. For `settings.json` edits, trigger an affected tool call and confirm the expected allow/deny/prompt outcome.

## Out of scope

- Don't add CI, GitHub Actions, or a build step — this is a config-only repo.
- Don't add a `package.json` unless you have a reason tied to tooling for editing markdown.
