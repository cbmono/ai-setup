# ai-setup

Opinionated defaults for [Claude Code](https://claude.com/claude-code), tuned for Node.js and TypeScript projects. Agents, slash commands, and settings — ready to drop into `~/.claude` or cherry-pick per project.

Built for Opus 4.7 with stacked-PR workflows in mind.

---

## Getting started

The recommended setup is **user-wide**: run `install.sh` once, and every project picks up the agents, commands, skills, and defaults automatically.

```bash
git clone https://github.com/<your-fork>/ai-setup.git ~/path/to/ai-setup
cd ~/path/to/ai-setup
./install.sh
```

`install.sh` symlinks this repo's tracked defaults **into** your existing `~/.claude` one entry at a time (not a whole-directory symlink), so your plugins, sessions, and `settings.local.json` stay put and Claude Code's runtime state never leaks into the repo. It's idempotent and auto-discovers what to link from what git tracks — re-run it after a `git pull` that adds a new top-level entry. See [Install](#install) for what it does and the per-project alternative.

Then in any project: `claude`, then `/init` to bootstrap the project's `CLAUDE.md`. Project-state files (`/scan`, `/techdebt`, `/plan` outputs) land in the project's local `.claude/`, created lazily on first write.

Prefer per-project copy, or have an existing `.claude/` to overlay? See [Install](#install).

---

## What's inside

### Agents (`.claude/agents/`)

Generic Node/TS agents — they infer your toolchain from `package.json` instead of hardcoding paths.

| Agent               | Model  | Purpose                                                                            | Invoked by commands                  |
| ------------------- | ------ | ---------------------------------------------------------------------------------- | ------------------------------------ |
| **build-validator** | Sonnet | Typecheck / lint / test / build. `--deep` = clean-install + sequenced unit→int→e2e | `/verify`                            |
| **code-architect**  | Opus   | Staff-level review of staged + unstaged changes                                    | `/grill` (grill fallback, no Workflow), direct dispatch |
| **deep-bug-scan**   | Opus   | Deep scan for logic bugs, null risks, race conditions, SQL issues, weak tests      | `/scan`                              |
| **oncall-guide**    | Sonnet | Diagnoses test/CI failures and classifies the cause                                | `/verify` (on failure)               |
| **plan-architect**  | Opus   | Critiques an implementation plan before code is written                            | `/plan` (grill fallback, no Workflow) |
| **stack-navigator** | Sonnet | Reads `gh stack view` and proposes the next safe action in a stacked-PR flow       | `/stack` (no args)                   |

For cleaning up recently changed code, use the built-in `/simplify` skill (a Claude Code built-in, not a command this repo ships) — that's what it's for.

### Slash commands (`.claude/commands/`)

One `.md` per command; filename becomes `/<name>`. No frontmatter required; `$ARGUMENTS` expands to whatever the user typed after the command. See [`.claude/README.md`](./.claude/README.md) for the command-vs-skill distinction and editing guidelines.

| Command        | What it does                                                                                  | Dispatches agents             |
| -------------- | --------------------------------------------------------------------------------------------- | ----------------------------- |
| `/acp`         | Stage, commit with a generated message, and push (stack-aware)                                | —                             |
| `/dave`        | Critique current diff/plan via Dave AI (Alteos-internal — requires `dave` CLI)                | —                             |
| `/grill`       | Adversarial fan-out over your own diff — find what's wrong before a reviewer does             | diff-grill workflow; code-architect (fallback) |
| `/plan`        | Draft → adversarial workflow grill → save plan to `.claude/plans/<slug>.md` (rides with the stack) | plan-grill workflow; plan-architect (fallback) |
| `/rabbit`      | Run CodeRabbit review on the current branch against `main`                                    | —                             |
| `/scan [dir]`  | Deep bug scan of a folder; appends findings to `.claude/potential-bugs.md`                    | deep-bug-scan                 |
| `/stack`       | gh-stack wrapper (bare = smart recommendation, args = specific actions)                       | stack-navigator (no args)     |
| `/techdebt`    | Scan for duplication/dead code; defer/apply/reject per item. Backlog in `.claude/techdebt.md` | —                             |
| `/verify`      | Pre-PR gate: typecheck / lint / test / build. `--deep` = full install + e2e                   | build-validator, oncall-guide |

**Picking among the review commands:** `/plan` and `/grill` are the same adversarial fan-out aimed at opposite ends of the work — `/plan` attacks an _approach_ before code exists, `/grill` attacks the _diff_ after you've written it (often both on the same task: `/plan` to decide how, `/grill` once it's built). `/grill` reviews the current diff (diff-scoped, ephemeral, pre-PR). `/scan` hunts bugs in existing code (folder-scoped, durable backlog at `.claude/potential-bugs.md`). `/techdebt` finds structural cleanup opportunities across the **whole repo** (deferred backlog at `.claude/techdebt.md`); for the same kind of cleanup scoped to the current diff, use the built-in `/simplify` skill. See [`.claude/README.md`](./.claude/README.md) for the full workflow patterns.

### Skills (`.claude/skills/`)

Auto-invocable capabilities — Claude fires them on intent match (no `/<name>`). One subdirectory per skill with a `SKILL.md`.

| Skill             | Fires when                       | What it does                                                                                                                  |
| ----------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **test-locators** | Building or editing frontend UI  | Adds stable test locators (`data-testid`/`data-test`) and a11y handles with business-meaningful kebab-case names, so E2E tests don't go flaky |

The skill is the canonical definition of the convention — `/grill` and `/plan` also pull it in as a `locators` review lens on frontend changes (the lens carries a short, in-sync copy of the rules). `/dave` restates the rules inline in its prompt and CodeRabbit applies them from its **web** review-instruction settings — both run outside Claude Code and can't reach the skill.

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

### Plugins enabled by default

`settings.json` enables two plugins from the official marketplace (`claude-plugins-official`) for everyone who adopts these defaults — no `extraKnownMarketplaces` needed, since the official marketplace is registered automatically:

| Plugin           | Why it's a default                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------------------- |
| [`superpowers`](https://github.com/obra/superpowers) | Skills framework — brainstorming, subagent-driven development, systematic debugging, red/green TDD          |
| [`typescript-lsp`](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/typescript-lsp) | Adds the `LSP` tool (go-to-definition, find-references, hover, workspace-symbol) backed by a TS language server, for the Node/TS stack this repo targets |
| [`security-guidance`](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/security-guidance) | Surfaces secure-coding guidance during development; additive, no overlap with shipped commands              |

The set is intentionally small. Most other official plugins (`code-review`, `pr-review-toolkit`, `code-simplifier`, `commit-commands`, `feature-dev`) **duplicate commands this repo already ships** (`/grill` + `code-architect`, `/rabbit`, `/techdebt`, `/acp`, `/plan`) — enabling them would just create overlap.

> **Trust gate, not silent install.** On a fresh clone Claude Code first shows the "trust this folder?" prompt; only after you trust it do the plugins auto-enable. To disable one without forking, set it `false` in your own `settings.local.json` (e.g. `"superpowers@claude-plugins-official": false`).

**Opt-in, MCP-backed plugins** — `github`, `linear`, and `context7` match Alteos's connected services but are **not** in the baseline, following the same rule as MCP servers (kept out so consumers choose to wire them up). Copy the entries you want from [`.claude/settings.plugins.example.json`](./.claude/settings.plugins.example.json) into your own `settings.json`.

### Hooks shipped in the baseline

`settings.json` wires up one hook by default — anything narrower stays in opt-in `.example.json` files.

| Hook                 | Event                       | Behavior                                                                                                                                                                                                                  |
| -------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `format-on-write.sh` | `PostToolUse` (Write\|Edit) | Formats the file Claude just wrote, if the nearest `package.json` declares `@biomejs/biome` (preferred) or `prettier`. Uses `npx --no-install`, so a missing or uninstalled formatter is a silent no-op. Never blocks the tool. |

The script (`.claude/hooks/format-on-write.sh`) self-detects — projects without a declared formatter, files outside the project, and unsupported extensions all no-op cleanly. To disable, remove the `hooks` block from your `settings.json` or shadow it in `settings.local.json`.

---

## Install

### Option A — Adopt as user-wide defaults

Clone the repo and run `install.sh`:

```bash
git clone https://github.com/<your-fork>/ai-setup.git ~/path/to/ai-setup
cd ~/path/to/ai-setup
./install.sh
```

The script symlinks each tracked default (`agents/`, `commands/`, `skills/`, `hooks/`, `MEMORY.md`, `claude-defaults.md`) **into** your real `~/.claude`, rather than replacing `~/.claude` with one big symlink. Two reasons this matters:

- **Your `~/.claude` keeps owning its runtime state** — `plugins/`, `sessions/`, `projects/`, `history.jsonl`, `settings.local.json`. A whole-directory symlink would either nest inside an existing `~/.claude` (a silent no-op) or relocate all that state into the repo, where it'd clutter the working tree.
- **It auto-discovers what to link from `git ls-files`**, so a new top-level default added to the repo is picked up on the next run — there's no list to maintain. Re-running is idempotent; anything it would overwrite is backed up to `*.bak.<timestamp>`. Entries are linked whole, so if `~/.claude` already has a real `commands/`/`agents/`/`skills/` of your own, that directory is moved aside to `*.bak.<timestamp>` (recoverable) and replaced by the symlink — keep personal global commands per-project (`<project>/.claude/commands/`) instead, since `~/.claude/commands/` now points into this repo.

`settings.json` is handled deliberately: if you don't already have one it's linked (so the repo's permission + plugin baseline applies user-wide); if you do, it's left untouched and the script prints how to adopt the baseline while keeping machine-specific plugins in `settings.local.json`.

Pull updates anytime with `git pull` — because the links are live, content changes and new files inside linked dirs apply immediately, no re-sync. To back out, `./install.sh --uninstall` removes only the symlinks it created, leaving your runtime state, real files, and backups untouched.

### Option B — Per-project

Use this when you want stability per project (**frozen** defaults that *don't* track the repo), or for project-specific tweaks. This is a **copy**, not a link — so unlike Option A it won't pick up later repo changes; re-run it to refresh. (To keep `~/.claude` continuously in sync with the repo, use Option A's symlinks, not this.)

For a fresh project (no existing `.claude/`):

```bash
cp -r ~/path/to/ai-setup/.claude ~/path/to/your-project/.claude
```

For a project that already has a `.claude/`:

```bash
rsync -a --exclude='settings.local.json' ~/path/to/ai-setup/.claude/ ~/path/to/your-project/.claude/
```

That single exclusion is enough — this repo's `.claude/` no longer carries `potential-bugs.md`, `techdebt.md`, or `plans/`. Those project-state artifacts are auto-created in the target by their respective commands (`/scan`, `/techdebt`, `/plan`) on first run, and stay gitignored. `CLAUDE.md` at the project root is also never touched. If you've customised `.claude/MEMORY.md`, back it up before syncing — it will be overwritten.

### Bootstrap a CLAUDE.md

Run `/init` in your project — it analyzes the codebase and generates an accurate CLAUDE.md (commands, architecture, structure). Then append the three sections below, which `/init` won't produce because they're workflow conventions rather than codebase facts.

> **Before you paste:**
>
> 1. **Confirm the links.** The imports below use `@~/.claude/...`, which assumes you ran `install.sh` (recommended in [Getting started](#getting-started)). Verify with `readlink ~/.claude/claude-defaults.md` — it should point at this repo's `.claude/claude-defaults.md`. (`install.sh` links files *into* a real `~/.claude`, so `~/.claude` itself is a directory, not a symlink.) If you're on a per-project install instead, swap both `@~/.claude/...` paths for `@.claude/...` and make sure those files exist in this project's `.claude/`.
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
> - **Per-project alternative:** if you don't want a user-wide install, swap the imports for `@.claude/claude-defaults.md` and `@.claude/MEMORY.md` and use [Option B](#option-b--per-project)'s `cp`/`rsync` to keep the project-local copies updated.

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
- `.claude/settings.plugins.example.json` — reference only, opt-in MCP-backed plugins (github, linear, context7)
- `.claude/potential-bugs.md`, `.claude/techdebt.md`, `.claude/plans/` — gitignored, auto-created by `/scan`, `/techdebt`, `/plan` on first run; never seeded in this repo
- `CLAUDE.md` (this repo's root) — guidance for Claude when editing **this config repo itself**, not a template

---

## License

MIT. See [LICENSE](./LICENSE).
