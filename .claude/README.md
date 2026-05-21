# `.claude/` — Claude Code config

Defaults shipped by this repo. See the [top-level README](../README.md) for install and usage.

## Layout

```
.claude/
  README.md                           # this file (inventory + conventions)
  claude-defaults.md                  # @-imported from CLAUDE.md → loaded every session
  MEMORY.md                           # project conventions (slash-command triggers); optional @-import
  settings.json                       # team-shared permissions + universally-safe hooks (checked in)
  settings.local.json                 # per-machine overrides (gitignored, auto-created by Claude Code)
  settings.mempalace.example.json     # opt-in mempalace MCP + hooks
  hooks/                              # executable hook scripts referenced from settings.json
    format-on-write.sh                # PostToolUse Write|Edit: prettier/biome if declared in package.json
  agents/                             # subagents (one .md per agent, YAML frontmatter)
  commands/                           # slash commands (one .md per command, no frontmatter)
  skills/                             # auto-invocable capabilities; see skills/README.md

# Auto-created on first run by their respective commands (gitignored, never committed):
  potential-bugs.md                   # /scan output (append-only sink)
  techdebt.md                         # /techdebt output (rolling deferred backlog)
  plans/                              # /plan output; rides with the related PR(s), deleted once work merges
```

> Don't put a `README.md` inside `commands/` — Claude Code registers every `.md` there as a slash command, so a README becomes `/README`.

## Agents

| Agent             | Model  | Purpose                                                                                              | Invoked by commands                           |
| ----------------- | ------ | ---------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `build-validator` | Sonnet | Typecheck / lint / test / build. `--deep` = clean-install + sequenced unit→integration→e2e           | `/verify`                                     |
| `code-architect`  | Opus   | Staff-level review of staged + unstaged changes                                                      | `/grill` (parallel dispatch), direct dispatch |
| `deep-bug-scan`   | Opus   | Scans a folder for logic, null, async, SQL, API-misuse, assertion, mutation, and security-smell bugs | `/scan`                                       |
| `oncall-guide`    | Sonnet | Diagnoses test or CI failures and classifies the cause                                               | `/verify` (on failure)                        |
| `plan-architect`  | Opus   | Critiques an implementation plan before code is written                                              | `/plan`                                       |
| `stack-navigator` | Sonnet | Reads `gh stack view` and proposes the next safe action                                              | `/stack` (no args)                            |

Recently-changed-code cleanup uses the **built-in** `/simplify` skill (a Claude Code built-in, not a command this repo ships) — no custom agent needed.

## Commands

One `.md` per command in `.claude/commands/`. Filename (minus `.md`) is the command name: `grill.md` → `/grill`. No frontmatter. Use `$ARGUMENTS` inside the file to reference text typed after the command.

| Command        | What it does                                                                                                                                                            | Dispatches agents             |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| `/acp`         | Stage, commit with a generated message, push (stack-aware)                                                                                                              | —                             |
| `/dave`        | Critique current diff/plan via Dave AI (Alteos-internal — requires `dave` CLI)                                                                                          | —                             |
| `/grill`       | Grill your own diff — correctness, concurrency, edge cases                                                                                                              | —                             |
| `/plan`        | Draft → review → save plan to `.claude/plans/<slug>.md` (rides with the stack)                                                                                          | plan-architect                |
| `/rabbit`      | CodeRabbit review on the current branch against `main`                                                                                                                  | —                             |
| `/scan [dir]`  | Deep bug scan; appends findings to `potential-bugs.md`                                                                                                                  | deep-bug-scan                 |
| `/stack`       | gh-stack wrapper. Bare call = smart recommendation                                                                                                                      | stack-navigator (no args)     |
| `/techdebt`    | Scan for duplication, dead code, low-value abstractions; defer/apply/reject per item. Deferred items go to `techdebt.md` (rolling backlog, dedupes against prior runs). | —                             |
| `/verify`      | Pre-PR gate. `--deep` = full install + sequenced unit→int→e2e                                                                                                           | build-validator, oncall-guide |

## Workflow patterns

How the tools fit together — useful for picking the right one and combining them.

- **Pre-PR verification:** `/verify` → fix anything red → `/grill` (which dispatches `code-architect` in parallel) → `/acp`.
- **Two complementary review lenses, run together:** `/grill` covers correctness, edge cases, concurrency, observability — questions about _the diff_. `code-architect` covers architecture, layering, naming, dependency choices — questions about _the design_. `/grill` fans out both in parallel and merges results.
- **Plan-first work:** `/plan` drafts a plan, dispatches `plan-architect` for critique, then saves the refined plan to `.claude/plans/<slug>.md` (auto-created on first run) — slug is the Jira key when detected on branch / recent commits, else a kebab-case verb-prefixed summary (`feat-…`, `fix-…`, `chore-…`). The file is checked in, rides along with the related PR(s) as a checkbox progress tracker, and is deleted by the user once the work merges to main (`/stack merge` will prompt for cleanup when the stack drains). **Caveat for stacked PRs:** every PR that ticks a checkbox modifies the same file, so frequent updates create rebase friction during `gh stack sync` — update at PR boundaries, not after every commit. For changes already in progress, `code-architect` reviews staged + unstaged diffs.
- **Review lenses by scope and durability:** three commands, picked by what you're judging and whether you want a backlog.
  - `/grill` — **diff-scoped, ephemeral.** Devil's-advocate critique of the current diff pre-PR (correctness, edge cases, concurrency) plus a parallel `code-architect` pass on design. Output is in-conversation only — act on it now or lose it.
  - `/scan [dir]` — **folder-scoped, durable.** `deep-bug-scan` hunts _existing_ code for real bugs (wrong logic, null risks, race conditions, SQL issues, weak assertions). Findings append to `.claude/potential-bugs.md` (auto-created on first run), kept current (fixed entries pruned).
  - `/techdebt` — **repo-scoped, durable.** Finds _structural_ issues (duplication, dead code, low-value abstractions). Deferred items go to `.claude/techdebt.md` (auto-created on first run), a deferred-only backlog (fixed/rejected items pruned).
  - Small overlap on dead code / near-duplicates between `/scan` and `/techdebt` — run `/scan` for correctness problems, `/techdebt` for cleanup.
  - The built-in `/simplify` skill covers the same _kind_ of cleanup as `/techdebt` but scoped to the current diff — reach for `/simplify` after a feature lands, `/techdebt` for periodic repo-wide sweeps.
- **CI failure triage:** `/verify` fails → it dispatches `oncall-guide` for diagnosis. You can also dispatch `oncall-guide` directly with a failing test name or CI job URL.

## Hooks

Ship hooks here only when they're **universally safe** — must no-op cleanly on projects that don't match. Scripts live in `.claude/hooks/`, referenced from `settings.json`. Anything narrower than that goes in an opt-in `settings.<name>.example.json` consumers copy from.

| Hook                  | Event                  | What it does                                                                                                                                                            |
| --------------------- | ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `format-on-write.sh`  | `PostToolUse` (Write\|Edit) | After Claude writes/edits a file, format it if the nearest `package.json` declares `@biomejs/biome` (preferred) or `prettier`. Uses `npx --no-install` so a missing or uninstalled formatter is a silent no-op. Skips unsupported extensions. |

## Commands vs skills

Claude Code has two distinct mechanisms. This repo uses **commands**.

- **Commands** (`.claude/commands/foo.md`) — invoked only when the user types `/foo`. No frontmatter. Best for explicit checkpoints.
- **Skills** (`.claude/skills/foo/SKILL.md` with `name` + `description` frontmatter) — Claude can auto-invoke via the `Skill` tool when the description matches user intent. Use only if you want proactive invocation.

Everything here is an explicit user action (commit, verify, grill, scan) — don't promote to skills unless auto-triggering is genuinely desired.

## Conventions when editing files here

- **Agents** use YAML frontmatter (`name`, `description`, optional `model`, `isolation`). `description` is what Claude Code matches on — write it as a triggerable purpose, not a title.
- **Commands** don't use frontmatter. Filename is the command name.
- When you add or remove an agent/command, update both inventories: this file and the top-level `README.md`.
- Keep files short. Front-loaded, declarative instructions beat verbose prose.
- `deep-bug-scan` appends findings to `potential-bugs.md` and must dedupe against existing entries.
- `/techdebt` writes only **deferred** findings to `techdebt.md` — it's a rolling backlog, not a log. Items fixed or rejected in a session must be removed from the file.
- After adding/moving/renaming commands or agents, restart Claude Code (`/exit`, then `claude`) and verify they register without a `skills:` prefix.
