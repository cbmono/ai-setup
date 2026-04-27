# `.claude/` — Claude Code config

Defaults shipped by this repo. See the [top-level README](../README.md) for install and usage.

## Layout

```
.claude/
  README.md                           # this file (inventory + conventions)
  claude-defaults.md                  # @-imported from CLAUDE.md → loaded every session
  potential-bugs.md                   # append-only sink for deep-bug-scan
  techdebt.md                         # rolling backlog for /techdebt (deferred items only)
  settings.json                       # team-shared permissions (checked in)
  settings.local.json                 # per-machine overrides (gitignored)
  settings.mempalace.example.json     # opt-in mempalace MCP + hooks
  agents/                             # subagents (one .md per agent, YAML frontmatter)
  commands/                           # slash commands (one .md per command, no frontmatter)
```

> Don't put a `README.md` inside `commands/` — Claude Code registers every `.md` there as a slash command, so a README becomes `/README`.

## Agents

| Agent             | Model  | Purpose                                                                                              | Invoked by commands                           |
| ----------------- | ------ | ---------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `build-validator` | Sonnet | Typecheck / lint / test / build. `--deep` = clean-install + sequenced unit→integration→e2e           | `/verify`                                     |
| `code-architect`  | Opus   | Staff-level review of staged + unstaged changes                                                      | `/grill` (parallel dispatch), direct dispatch |
| `deep-bug-scan`   | Opus   | Scans a folder for logic, null, async, SQL, API-misuse, assertion, mutation, and security-smell bugs | `/scan`                                       |
| `oncall-guide`    | Sonnet | Diagnoses test or CI failures and classifies the cause                                               | `/verify` (on failure)                        |
| `plan-architect`  | Opus   | Critiques an implementation plan before code is written                                              | `/plan-review`                                |
| `stack-navigator` | Sonnet | Reads `gh stack view` and proposes the next safe action                                              | `/stack` (no args)                            |

Recently-changed-code cleanup uses the **built-in** `/simplify` skill (a Claude Code built-in, not a command this repo ships) — no custom agent needed.

## Commands

One `.md` per command in `.claude/commands/`. Filename (minus `.md`) is the command name: `grill.md` → `/grill`. No frontmatter. Use `$ARGUMENTS` inside the file to reference text typed after the command.

| Command        | What it does                                                                                                                                                            | Dispatches agents             |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| `/acp`         | Stage, commit with a generated message, push (stack-aware)                                                                                                              | —                             |
| `/boris`       | Boris Cherny's workflow tips & best practices                                                                                                                           | —                             |
| `/dave`        | Critique current diff/plan via Dave AI (Alteos-internal — requires `dave` CLI)                                                                                          | —                             |
| `/grill`       | Grill your own diff — correctness, concurrency, edge cases                                                                                                              | —                             |
| `/plan-review` | Write a plan, then spin up a reviewer before implementation                                                                                                             | plan-architect                |
| `/rabbit`      | CodeRabbit review on the current branch against `main`                                                                                                                  | —                             |
| `/scan [dir]`  | Deep bug scan; appends findings to `potential-bugs.md`                                                                                                                  | deep-bug-scan                 |
| `/stack`       | gh-stack wrapper. Bare call = smart recommendation                                                                                                                      | stack-navigator (no args)     |
| `/techdebt`    | Scan for duplication, dead code, low-value abstractions; defer/apply/reject per item. Deferred items go to `techdebt.md` (rolling backlog, dedupes against prior runs). | —                             |
| `/verify`      | Pre-PR gate. `--deep` = full install + sequenced unit→int→e2e                                                                                                           | build-validator, oncall-guide |

## Workflow patterns

How the tools fit together — useful for picking the right one and combining them.

- **Pre-PR verification:** `/verify` → fix anything red → `/grill` (which dispatches `code-architect` in parallel) → `/acp`.
- **Two complementary review lenses, run together:** `/grill` covers correctness, edge cases, concurrency, observability — questions about _the diff_. `code-architect` covers architecture, layering, naming, dependency choices — questions about _the design_. `/grill` fans out both in parallel and merges results.
- **Plan-first work:** `/plan-review` writes a plan and dispatches `plan-architect` for critique before any code is written. For changes already in progress, `code-architect` reviews staged + unstaged diffs.
- **Bugs vs. tech debt:** `/scan` (via `deep-bug-scan`) finds real bugs — wrong logic, null risks, race conditions, SQL issues, weak assertions. Output is `.claude/potential-bugs.md`, kept current (fixed entries are pruned). `/techdebt` finds _structural_ issues — duplication, dead code, low-value abstractions. Output is `.claude/techdebt.md`, a deferred-only backlog. There's a small overlap (dead code, near-duplicates) — run `/scan` when you suspect correctness problems, `/techdebt` when you want cleanup.
- **CI failure triage:** `/verify` fails → it dispatches `oncall-guide` for diagnosis. You can also dispatch `oncall-guide` directly with a failing test name or CI job URL.

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
