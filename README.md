# ai-setup

Opinionated defaults for [Claude Code](https://claude.com/claude-code), tuned for Node.js and TypeScript projects. Agents, slash commands, and settings — ready to drop into `~/.claude` or cherry-pick per project.

Built for Opus 4.7 with stacked-PR workflows in mind.

---

## Getting started

The recommended setup is **user-wide**: symlink this repo's `.claude/` into `~/.claude/` once, and every project picks up the agents, commands, skills, and defaults automatically.

```bash
git clone https://github.com/<your-fork>/ai-setup.git ~/ai-setup
mv ~/.claude ~/.claude.bak.$(date +%s) 2>/dev/null || true
ln -s ~/ai-setup/.claude ~/.claude
```

Then in any project: `claude`, then `/init` to bootstrap the project's `CLAUDE.md`. Project-state files (`/scan`, `/techdebt`, `/plan` outputs) land in the project's local `.claude/`, created lazily on first write.

Prefer per-project copy, or have an existing `.claude/` to overlay? See [Install](#install).

---

## What's inside

### Agents (`.claude/agents/`)

Generic Node/TS agents — they infer your toolchain from `package.json` instead of hardcoding paths.

| Agent               | Model  | Purpose                                                                            | Invoked by commands                  |
| ------------------- | ------ | ---------------------------------------------------------------------------------- | ------------------------------------ |
| **build-validator** | Sonnet | Typecheck / lint / test / build. `--deep` = clean-install + sequenced unit→int→e2e | `/verify`                            |
| **code-architect**  | Opus   | Staff-level review of staged + unstaged changes                                    | `/grill` (parallel), direct dispatch |
| **deep-bug-scan**   | Opus   | Deep scan for logic bugs, null risks, race conditions, SQL issues, weak tests      | `/scan`                              |
| **oncall-guide**    | Sonnet | Diagnoses test/CI failures and classifies the cause                                | `/verify` (on failure)               |
| **plan-architect**  | Opus   | Critiques an implementation plan before code is written                            | `/plan`                              |
| **stack-navigator** | Sonnet | Reads `gh stack view` and proposes the next safe action in a stacked-PR flow       | `/stack` (no args)                   |

For cleaning up recently changed code, use the built-in `/simplify` skill (a Claude Code built-in, not a command this repo ships) — that's what it's for.

### Slash commands (`.claude/commands/`)

One `.md` per command; filename becomes `/<name>`. No frontmatter required; `$ARGUMENTS` expands to whatever the user typed after the command. See [`.claude/README.md`](./.claude/README.md) for the command-vs-skill distinction and editing guidelines.

| Command        | What it does                                                                                  | Dispatches agents             |
| -------------- | --------------------------------------------------------------------------------------------- | ----------------------------- |
| `/acp`         | Stage, commit with a generated message, and push (stack-aware)                                | —                             |
| `/dave`        | Critique current diff/plan via Dave AI (Alteos-internal — requires `dave` CLI)                | —                             |
| `/grill`       | Devil's advocate on your own diff — find what's wrong before a reviewer does                  | —                             |
| `/plan`        | Draft → review → save plan to `.claude/plans/<slug>.md` (rides with the stack)                | plan-architect                |
| `/rabbit`      | Run CodeRabbit review on the current branch against `main`                                    | —                             |
| `/scan [dir]`  | Deep bug scan of a folder; appends findings to `.claude/potential-bugs.md`                    | deep-bug-scan                 |
| `/stack`       | gh-stack wrapper (bare = smart recommendation, args = specific actions)                       | stack-navigator (no args)     |
| `/techdebt`    | Scan for duplication/dead code; defer/apply/reject per item. Backlog in `.claude/techdebt.md` | —                             |
| `/verify`      | Pre-PR gate: typecheck / lint / test / build. `--deep` = full install + e2e                   | build-validator, oncall-guide |

**Picking among the review commands:** `/grill` reviews the current diff (diff-scoped, ephemeral, pre-PR). `/scan` hunts bugs in existing code (folder-scoped, durable backlog at `.claude/potential-bugs.md`). `/techdebt` finds structural cleanup opportunities across the **whole repo** (deferred backlog at `.claude/techdebt.md`); for the same kind of cleanup scoped to the current diff, use the built-in `/simplify` skill. See [`.claude/README.md`](./.claude/README.md) for the full workflow patterns.

### Settings (`.claude/settings.json`)

Pre-allows common safe operations so you see fewer permission prompts:

- Read-only git and `gh` commands
- `gh stack` navigation (view, up, down, top, bottom, checkout)
- Package-manager `run` / `install` / `test` for npm, pnpm, yarn, bun (scoped — `yarn`, `bunx`, `pnpm dlx` are **not** wildcarded)
- `npx tsc`, `eslint`, `prettier`, `vitest`, `jest` (and `bunx` / `yarn` equivalents)
- `Read` / `Edit` / `Write` scoped to the current repo (`./**`) — not the whole filesystem

And denies dangerous defaults: `git push --force …` and `git push -f …` (flag-first only), `git reset --hard …`, `git clean -f …`, `rm -rf /` / `~` / `$HOME`, `.env` reads **and** writes, SSH private keys (read/edit/write), AWS credentials (read/edit/write), `sudo`.

> **Note on deny patterns.** Mid-pattern wildcards (e.g. `git push * --force`) are documented but fragile — Anthropic's own docs warn that argument-constraint rules don't survive flag re-ordering, redirects, env-var substitution, or extra whitespace. So the deny rules above only catch flag-first force-push orderings (`git push --force origin main`, not `git push origin main --force`). If you need stronger coverage, add a `PreToolUse` hook in `settings.local.json` that inspects the full command line.

Per-machine overrides go in `.claude/settings.local.json` (gitignored).

---

## Install

### Option A — Adopt as user-wide defaults

Back up any existing `~/.claude`, then symlink or copy this repo into it:

```bash
# Back up first
mv ~/.claude ~/.claude.bak.$(date +%s) 2>/dev/null || true

# Symlink (lets you pull updates with `git pull`)
git clone https://github.com/<your-fork>/ai-setup.git ~/ai-setup
ln -s ~/ai-setup/.claude ~/.claude
```

Agents and commands apply to every project. `settings.json` becomes your user-wide allow/deny list.

### Option B — Per-project

Use this when you want stability per project (frozen defaults), or for project-specific tweaks.

For a fresh project (no existing `.claude/`):

```bash
cp -r ~/path/to/ai-setup/.claude ./.claude
```

For a project that already has a `.claude/`:

```bash
rsync -a --exclude='settings.local.json' ~/path/to/ai-setup/.claude/ ./.claude/
```

That single exclusion is enough — this repo's `.claude/` no longer carries `potential-bugs.md`, `techdebt.md`, or `plans/`. Those project-state artifacts are auto-created in the target by their respective commands (`/scan`, `/techdebt`, `/plan`) on first run, and stay gitignored. `CLAUDE.md` at the project root is also never touched. If you've customised `.claude/MEMORY.md`, back it up before syncing — it will be overwritten.

### Bootstrap a CLAUDE.md

Run `/init` in your project — it analyzes the codebase and generates an accurate CLAUDE.md (commands, architecture, structure). Then append the three sections below, which `/init` won't produce because they're workflow conventions rather than codebase facts.

> **Before you paste:**
>
> 1. **Confirm the symlink.** The imports below use `@~/.claude/...`, which assumes you set up the user-wide symlink (recommended in [Getting started](#getting-started)). Verify with `readlink ~/.claude` — it should point at this repo's `.claude/`. If you're on a per-project install instead, swap both `@~/.claude/...` paths for `@.claude/...` and make sure those files exist in this project's `.claude/`.
> 2. **Put `CLAUDE.md` at the repo root.** Bare-path imports (`@.claude/...`) resolve relative to the `CLAUDE.md` file's location; if you move it, adjust the paths.
> 3. **Approve the import on first run.** The first time Claude Code encounters a new `@` import in a project, it shows a one-time approval dialog. **Click approve** — if you decline, imports stay disabled for that project and the defaults silently won't load.

```markdown
## Working with Claude here

@~/.claude/claude-defaults.md
@~/.claude/MEMORY.md

<!-- Loads behavioural defaults (claude-defaults.md) and the slash-command
trigger table (MEMORY.md) from the user-wide ~/.claude/ symlink every
session. For per-project installs (no symlink), swap to `@.claude/...`
and ensure both files exist in this project's .claude/. -->

## Things Claude has learned here

<!-- Add one-liners as you correct Claude — anytime Claude does something incorrectly, capture the rule here so it doesn't recur. Example:

- Never import from `lodash` — we use `remeda` everywhere.
- API handlers must call `logger.withContext(req)` before any awaits.
- Don't auto-add JSDoc — the repo style is type-first, comment-last.
-->

## Out of scope / do not touch

<!-- Files, dirs, or behaviors Claude should leave alone:
- `generated/` — regenerated from schema, edits will be lost
- `migrations/` — never edit past migrations, always add new
-->
```

> **How the `@` import works (and what to watch):**
>
> - Claude Code resolves `@<path>` lines inside `CLAUDE.md` and inlines the referenced file into every session's context. Tilde paths (`@~/.claude/...`) resolve against your home directory; bare paths (`@.claude/...`) resolve relative to the `CLAUDE.md` file. Supports up to 5 levels of recursion.
> - Keep your `CLAUDE.md` + all imports around **200 lines total**. Every line is re-sent on every turn; bloat shows up directly in token costs and in Claude's attention budget. Our `claude-defaults.md` is intentionally ~20 lines — resist the urge to expand it with guidance that already lives in Claude Code's built-in system prompt (e.g. "don't add defensive error handling," "don't create unrequested docs" — those are already defaults).
> - **Why imports instead of inlining the bullets?** You edit the rules once in `~/.claude/claude-defaults.md` (the file in this repo, surfaced via the symlink) and every project picks up the change automatically — no per-project copy-paste drift.
> - **Per-project alternative:** if you don't want a user-wide symlink, swap the imports for `@.claude/claude-defaults.md` and `@.claude/MEMORY.md` and use [`bin/sync-to-project.sh`](#option-b--per-project) to keep the project-local copies updated.

---

## Stacked pull requests (gh-stack)

This repo is built around [github/gh-stack](https://github.com/github/gh-stack), GitHub's official stacked-PR extension.

**Install:**

```bash
gh extension install github/gh-stack
```

(Requires `gh` v2.0+ and the feature enabled on your account.)

**Typical flow with Claude:**

```
> /stack view                        # where am I?
> /stack add feat/api-endpoints      # next branch on top
> (edit + commit)
> /stack submit                      # push and open/update PRs
> /stack sync                        # after a PR below merges
> /stack merge                       # land the bottom PR
```

Use the `stack-navigator` agent when you want a summary plus the recommended next action:

```
> use stack-navigator to tell me what to do next
```

**Pre-allowed in settings.json:** read-only `gh stack` commands (`view`, `up`, `down`, `top`, `bottom`, `checkout`). Mutating commands (`submit`, `sync`, `unstack`, `rebase`) still prompt — because they push to GitHub.

**Plans ride with the work.** `/plan` saves the refined plan to `.claude/plans/<slug>.md` (slug = Jira key when detected, else a kebab-case verb-prefixed summary like `feat-…` / `fix-…` / `chore-…`). The file is checked in alongside the related PR(s) and updated in-place (checkboxes) as steps land. Once the work merges to main (the last PR in the stack, if stacked), delete it.

---

## Memory (mempalace, optional)

If you want local-first session memory, [mempalace](https://github.com/mempalace/mempalace) indexes Claude Code transcripts for semantic + keyword search (offline, no API calls). `.claude/settings.mempalace.example.json` ships the MCP + hooks shape — copy the blocks into your own `settings.json` after `pip install mempalace && mempalace init .`. Check [mempalaceofficial.com](https://mempalaceofficial.com) for the current install + hook syntax; the example file may drift.

---

## Opus 4.7

This config targets Opus 4.7 for planning and review, Sonnet 4.6 for implementation.

Key behaviour differences vs 4.6 (worth internalizing):

- **Default effort is `xhigh`.** Use `/model` to adjust — `high` for concurrent sessions, `max` for gnarly problems only.
- **Adaptive thinking.** Fixed thinking budgets aren't supported; nudge with "think carefully and step-by-step" or "respond directly."
- **Less delegation by default.** Tell it explicitly: "Spawn subagents in parallel for each..."
- **Fewer tool calls.** Tell it explicitly: "Grep thoroughly before answering."
- **Front-load the spec.** Every turn adds reasoning overhead — state constraints, acceptance criteria, and file locations in turn one.

---

## Customizing

- **Add a command:** drop an `.md` file in `.claude/commands/` — the filename (minus `.md`) becomes the `/command`. Use `$ARGUMENTS` for user-supplied args. No frontmatter needed. **Don't put a `README.md` in `.claude/commands/`** — Claude Code scans every `.md` there as a command, so a README becomes `/README`. See [`.claude/README.md`](./.claude/README.md) for the command-vs-skill distinction.
- **Add an agent:** drop an `.md` file in `.claude/agents/` with YAML frontmatter (`name`, `description`, optional `model`, `isolation: worktree`).
- **Adjust permissions:** edit `.claude/settings.json` for team-shared rules, `.claude/settings.local.json` for this machine only.
- **Compounding engineering:** when Claude does something wrong, add the rule to your project's `CLAUDE.md` so it doesn't recur.

> **Restart after adding commands or agents.** Claude Code scans `.claude/commands/` and `.claude/agents/` at session start. New files aren't picked up until you `/exit` and relaunch `claude`. If `/<your-new-command>` returns "Unknown command", that's why.
>
> **Commands vs skills:** this repo uses `.claude/commands/` for explicit `/name` invocations. If you want Claude to auto-invoke a capability based on user intent, use `.claude/skills/<name>/SKILL.md` with YAML frontmatter instead — see the Claude Code docs on skills.

---

## Conventions in this repo

- `.claude/settings.json` — checked in, team-shared permissions baseline
- `.claude/settings.local.json` — gitignored, per-machine overrides
- `.claude/settings.mempalace.example.json` — reference only, copy blocks out to opt in
- `.claude/potential-bugs.md`, `.claude/techdebt.md`, `.claude/plans/` — gitignored, auto-created by `/scan`, `/techdebt`, `/plan` on first run; never seeded in this repo
- `CLAUDE.md` (this repo's root) — guidance for Claude when editing **this config repo itself**, not a template

---

## License

MIT. See [LICENSE](./LICENSE).
