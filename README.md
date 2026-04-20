# ai-setup

Opinionated defaults for [Claude Code](https://claude.com/claude-code), tuned for Node.js and TypeScript projects. Agents, slash commands, settings, and a curated workflow-tips command — ready to drop into `~/.claude` or cherry-pick per project.

Built for Opus 4.7 with stacked-PR workflows in mind.

---

## Getting started

1. Copy the `.claude/` folder into your project.
2. Start Claude Code in your terminal: `claude`.
3. Run `/init`.
4. Done.
5. Check the list of agents and commands in `.claude/` — or see [What's inside](#whats-inside) below.

For user-wide install or finer-grained setup, see [Install](#install).

---

## What's inside

### Agents (`.claude/agents/`)

Generic Node/TS agents — they infer your toolchain from `package.json` instead of hardcoding paths.

| Agent               | Model  | Purpose                                                                             | Invoked by commands            |
| ------------------- | ------ | ----------------------------------------------------------------------------------- | ------------------------------ |
| **build-validator** | Sonnet | Typecheck / lint / test / build. `--deep` = clean-install + sequenced unit→int→e2e | `/verify`                      |
| **code-architect**  | Opus   | Staff-level review of staged + unstaged changes                                     | `/plan-review`, `/grill`       |
| **deep-bug-scan**   | Opus   | Deep scan for logic bugs, null risks, race conditions, SQL issues, weak tests       | `/scan`                        |
| **oncall-guide**    | Sonnet | Diagnoses test/CI failures and classifies the cause                                 | `/verify` (on failure)         |
| **stack-navigator** | Sonnet | Reads `gh stack view` and proposes the next safe action in a stacked-PR flow        | `/stack` (no args)             |

For cleaning up recently changed code, use the built-in `/simplify` skill — that's what it's for.

### Slash commands (`.claude/commands/`)

One `.md` per command; filename becomes `/<name>`. No frontmatter required; `$ARGUMENTS` expands to whatever the user typed after the command. See [`.claude/README.md`](./.claude/README.md) for the command-vs-skill distinction and editing guidelines.

| Command        | What it does                                                                   | Dispatches agents             |
| -------------- | ------------------------------------------------------------------------------ | ----------------------------- |
| `/acp`         | Stage, commit with a generated message, and push (stack-aware)                 | —                             |
| `/verify`      | Pre-PR gate: typecheck / lint / test / build. `--deep` = full install + e2e    | build-validator, oncall-guide |
| `/scan [dir]`  | Deep bug scan of a folder; appends findings to `.claude/potential-bugs.md`     | deep-bug-scan                 |
| `/grill`       | Devil's advocate on your own diff — find what's wrong before a reviewer does   | —                             |
| `/plan-review` | Write a plan, then spin up a reviewer before implementation                    | code-architect                |
| `/stack`       | gh-stack wrapper (bare = smart recommendation, args = specific actions)        | stack-navigator               |
| `/techdebt`    | Scan for duplication/dead code; defer/apply/reject per item. Backlog in `.claude/techdebt.md` | —                             |
| `/rabbit`      | Run CodeRabbit review on the current branch against `main`                     | —                             |
| `/save`        | Persist durable context to memory (+ mempalace if installed), then compact     | —                             |
| `/boris`       | Boris Cherny's Claude Code workflow tips (parallel sessions, hooks, plan mode) | —                             |

### Settings (`.claude/settings.json`)

Pre-allows common safe operations so you see fewer permission prompts:

- Read-only git and `gh` commands
- `gh stack` navigation (view, up, down, top, bottom, checkout)
- Package-manager `run` / `install` / `test` for npm, pnpm, yarn, bun (scoped — `yarn`, `bunx`, `pnpm dlx` are **not** wildcarded)
- `npx tsc`, `eslint`, `prettier`, `vitest`, `jest` (and `bunx` / `yarn` equivalents)
- `Read` / `Edit` / `Write` scoped to the current repo (`./**`) — not the whole filesystem

And denies dangerous defaults: `git push --force` (common orderings), `git reset --hard`, `rm -rf /`, `.env` reads **and** writes, SSH keys (read/edit/write), AWS credentials (read/edit/write), `sudo`.

> **Note on deny patterns.** Claude Code matches Bash deny rules positionally, not semantically. We cover the two most common force-push orderings (`git push --force …` and `git push … --force`), but a pathological ordering could still slip through. If that matters to your team, add a `PreToolUse` hook in `settings.local.json`.

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

Copy just what you want into the project's `.claude/`:

```bash
# In the target project
mkdir -p .claude/agents .claude/commands
cp -r ~/path/to/ai-setup/.claude/agents/* .claude/agents/
cp -r ~/path/to/ai-setup/.claude/commands/* .claude/commands/
cp ~/path/to/ai-setup/.claude/settings.json .claude/settings.json
```

### Bootstrap a CLAUDE.md

Run `/init` in your project — it analyzes the codebase and generates an accurate CLAUDE.md (commands, architecture, structure). Then append the three sections below, which `/init` won't produce because they're workflow conventions rather than codebase facts.

> **Before you paste:**
>
> 1. **Put `CLAUDE.md` at the repo root**, alongside the `.claude/` directory. The `@` import below uses a path relative to the CLAUDE.md file — if you move CLAUDE.md elsewhere, adjust the path or it will silently fail to load.
> 2. **Approve the import on first run.** The first time Claude Code encounters a new `@` import, it shows a one-time approval dialog. **Click approve** — if you decline, imports stay disabled for that project and `.claude/claude-defaults.md` won't load (silent failure: Claude will just ignore the defaults without error).

````markdown
## Working with Claude here

@.claude/claude-defaults.md

<!-- Imports `.claude/claude-defaults.md` into every session: planning, adaptive thinking, subagent spawning, compounding engineering. Edit that file to change the defaults project-wide. Full Boris Cherny tips: `/boris`. -->

## Things Claude has learned here

<!-- Add one-liners as you correct Claude. "Anytime we see Claude do something incorrectly we add it to the CLAUDE.md." — Boris Cherny. Example:

- Never import from `lodash` — we use `remeda` everywhere.
- API handlers must call `logger.withContext(req)` before any awaits.
- Don't auto-add JSDoc — the repo style is type-first, comment-last.
-->

## Out of scope / do not touch

<!-- Files, dirs, or behaviors Claude should leave alone:
- `generated/` — regenerated from schema, edits will be lost
- `migrations/` — never edit past migrations, always add new
-->
````

> **How the `@` import works (and what to watch):**
>
> - Claude Code resolves `@<path>` lines inside `CLAUDE.md` and inlines the referenced file into every session's context. Paths are relative to the CLAUDE.md file's location, not your working directory. Supports tilde (`@~/.claude/shared.md`) and up to 5 levels of recursion.
> - Keep your CLAUDE.md + all imports around **200 lines total**. Every line is re-sent on every turn; bloat shows up directly in token costs and in Claude's attention budget. Our `.claude/claude-defaults.md` is intentionally ~20 lines — resist the urge to expand it with guidance that already lives in Claude Code's built-in system prompt (e.g. "don't add defensive error handling," "don't create unrequested docs" — those are already defaults).
> - **Why imports instead of inlining the bullets?** You edit the rules once in `.claude/claude-defaults.md` and every project using this setup picks up the change — no per-project copy-paste drift. If you adopt this repo user-wide (Option A above), the same defaults apply everywhere.
> - **User-wide variant:** put `@~/.claude/claude-defaults.md` in `~/.claude/CLAUDE.md` to get the defaults in every project, not just ones that copy this template.

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
> /stack status                      # where am I?
> /stack add feat/api-endpoints      # next branch on top
> (edit + commit)
> /stack submit                      # push and open/update PRs
> /stack sync                        # after a PR below merges
```

Use the `stack-navigator` agent when you want a summary plus the recommended next action:

```
> use stack-navigator to tell me what to do next
```

**Pre-allowed in settings.json:** read-only `gh stack` commands (`view`, `up`, `down`, `top`, `bottom`, `checkout`). Mutating commands (`submit`, `sync`, `unstack`, `rebase`) still prompt — because they push to GitHub.

---

## Memory (mempalace, optional)

[mempalace](https://github.com/mempalace/mempalace) is a local-first memory system that stores conversation history verbatim and indexes it for semantic + keyword search. Works offline, 96–98% retrieval recall, no API calls.

**Install:**

```bash
pip install mempalace
cd /path/to/your-project
mempalace init .
```

**Wire into Claude Code:** copy the MCP + hooks block from `.claude/settings.mempalace.example.json` into your `.claude/settings.json` (or `~/.claude/settings.json` for user-wide). The example uses `PreCompact` and `Stop` hooks to mine the session before context compaction and at turn end.

The `/save` skill auto-detects mempalace and runs `mempalace mine` if the CLI is on your `PATH`.

See [mempalaceofficial.com/guide/hooks](https://mempalaceofficial.com/guide/hooks) for the canonical hook commands — the example file uses reasonable defaults but check upstream for the current syntax.

---

## Opus 4.7

This config targets Opus 4.7 for planning and review, Sonnet 4.6 for implementation.

Key behaviour differences vs 4.6 (worth internalizing):

- **Default effort is `xhigh`.** Use `/model` to adjust — `high` for concurrent sessions, `max` for gnarly problems only.
- **Adaptive thinking.** Fixed thinking budgets aren't supported; nudge with "think carefully and step-by-step" or "respond directly."
- **Less delegation by default.** Tell it explicitly: "Spawn subagents in parallel for each..."
- **Fewer tool calls.** Tell it explicitly: "Grep thoroughly before answering."
- **Front-load the spec.** Every turn adds reasoning overhead — state constraints, acceptance criteria, and file locations in turn one.

Fire `/boris` for the full tips list (parallel worktrees, plan mode, hooks, permissions, MCP integrations, auto-memory).

---

## Customizing

- **Add a command:** drop an `.md` file in `.claude/commands/` — the filename (minus `.md`) becomes the `/command`. Use `$ARGUMENTS` for user-supplied args. No frontmatter needed. **Don't put a `README.md` in `.claude/commands/`** — Claude Code scans every `.md` there as a command, so a README becomes `/README`. See [`.claude/README.md`](./.claude/README.md) for the command-vs-skill distinction.
- **Add an agent:** drop an `.md` file in `.claude/agents/` with YAML frontmatter (`name`, `description`, optional `model`, `isolation: worktree`).
- **Adjust permissions:** edit `.claude/settings.json` for team-shared rules, `.claude/settings.local.json` for this machine only.
- **Compounding engineering:** when Claude does something wrong, add the rule to your project's `CLAUDE.md`. "Anytime we see Claude do something incorrectly we add it to the CLAUDE.md." (Boris)

> **Restart after adding commands or agents.** Claude Code scans `.claude/commands/` and `.claude/agents/` at session start. New files aren't picked up until you `/exit` and relaunch `claude`. If `/<your-new-command>` returns "Unknown command", that's why.
>
> **Commands vs skills:** this repo uses `.claude/commands/` for explicit `/name` invocations. If you want Claude to auto-invoke a capability based on user intent, use `.claude/skills/<name>/SKILL.md` with YAML frontmatter instead — see the Claude Code docs on skills.

---

## Conventions in this repo

- `.claude/settings.json` — checked in, team-shared
- `.claude/settings.local.json` — gitignored, per-machine
- `.claude/settings.mempalace.example.json` — reference only, copy blocks out to opt in
- `.claude/potential-bugs.md` — append-only output sink for `deep-bug-scan`
- `.claude/techdebt.md` — rolling backlog for `/techdebt` (deferred items only, created on first run)
- `CLAUDE.md` (this repo's root) — guidance for Claude when editing **this config repo itself**, not a template

---

## License

MIT. See [LICENSE](./LICENSE).
