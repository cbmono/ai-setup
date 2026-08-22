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
  settings.plugins.example.json       # opt-in MCP-backed plugins (github, linear, context7)
  settings.codex.example.json         # opt-in Codex failover (openai/codex-plugin-cc)
  hooks/                              # executable scripts referenced from settings.json
    format-on-write.sh                # PostToolUse Write|Edit: prettier/biome if declared in package.json
    statusline.sh                     # statusLine: model · context% · session cost · lines · 5h limit
  scripts/                            # executable scripts the USER runs directly (not hooks, not commands)
    deepseek-session.sh               # opt-in: launch a session against DeepSeek instead of Anthropic
  agents/                             # subagents (one .md per agent, YAML frontmatter)
  commands/                           # slash commands (one .md per command, no frontmatter)
  output-styles/                      # opt-in reply formats (one .md per style, YAML frontmatter)
    brief.md                          # "Brief": outcome first, then Needs-you as numbered steps with URLs
  skills/                             # auto-invocable capabilities; see skills/README.md
  rules/                              # path-scoped instructions (`paths:` glob) — load only on a matching read
    ai-bridge.md                      # paths: ai-bridge/**            — layout + its 8 load-bearing invariants
    hooks-and-scripts.md              # paths: .claude/{hooks,scripts}/** — status line, hook paths, DeepSeek
    output-styles.md                  # paths: .claude/output-styles/** — Brief vs the built-in Concise
    repo-config.md                    # paths: .coderabbit.yaml, install.sh
    settings-and-permissions.md       # paths: .claude/settings*.json   — baseline, plugins, permission shapes

# Auto-created on first run by their respective commands (gitignored, never committed):
  potential-bugs.md                   # /scan output (append-only sink)
  techdebt.md                         # /techdebt output (rolling deferred backlog)
  plans/                              # /plan output; rides with the related PR(s), deleted once work merges
```

> Don't put a `README.md` inside `commands/` — Claude Code registers every `.md` there as a slash command, so a README becomes `/README`.

> The `../ai-bridge/` control-panel template is a **separate subtree** — its role agents (`project-manager`, `software-engineer`, `devops-engineer`, `qa-reviewer`, `cataloguer`, `auditor`, `oncall-guide`) and its commands (`/pm-loop`, `/new-project`, `/close-project`, `/answer`, `/audit`, `/pr-review-request`, `/fanout`) install into per-group *instances*, **not** into `~/.claude`, so they're intentionally absent from the inventories below. See [`../ai-bridge/README.md`](../ai-bridge/README.md).

## Agents

| Agent             | Model  | Purpose                                                                                              | Invoked by commands                           |
| ----------------- | ------ | ---------------------------------------------------------------------------------------------------- | --------------------------------------------- |
| `build-validator` | Sonnet | Typecheck / lint / test / build. `--deep` = clean-install + sequenced unit→integration→e2e           | `/verify`                                     |
| `code-architect`  | Opus   | Staff-level review of staged + unstaged changes                                                      | `/grill` (grill fallback, no Workflow), direct dispatch |
| `deep-bug-scan`   | Opus   | Scans a folder for logic, null, async, SQL, API-misuse, assertion, mutation, and security-smell bugs | `/scan`                                       |
| `oncall-guide`    | Sonnet | Diagnoses test or CI failures and classifies the cause                                               | `/verify` (on failure)                        |
| `plan-architect`  | Opus   | Critiques an implementation plan before code is written                                              | `/plan` (grill fallback, no Workflow)         |
| `stack-navigator` | Sonnet | Reads `gh stack view` and proposes the next safe action                                              | `/stack` (no args)                            |

Recently-changed-code cleanup uses the **built-in** `/simplify` skill (a Claude Code built-in, not a command this repo ships) — no custom agent needed.

## Commands

One `.md` per command in `.claude/commands/`. Filename (minus `.md`) is the command name: `grill.md` → `/grill`. No frontmatter. Use `$ARGUMENTS` inside the file to reference text typed after the command.

| Command        | What it does                                                                                                                                                            | Dispatches agents             |
| -------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------- |
| `/acp`         | Stage, commit with a generated message, push (stack-aware)                                                                                                              | —                             |
| `/dave`        | Critique current diff/plan via Dave AI (Alteos-internal — requires `dave` CLI)                                                                                          | —                             |
| `/grill`       | Adversarial fan-out over your own diff — correctness, failure modes, tests, architecture, +more                                                                        | diff-grill workflow; code-architect (fallback) |
| `/plan`        | Draft → adversarial workflow grill → save plan to `.claude/plans/<slug>.md` (rides with the stack)                                                                      | plan-grill workflow; plan-architect (fallback) |
| `/rabbit`      | CodeRabbit review on the current branch against the default branch                                                                                                      | —                             |
| `/codex-handoff` | Claude→Codex session handoff (resolves the transcript the plugin can't auto-detect); `back` has Codex summarise itself, then reconciles that against `git diff`        | needs the opt-in `codex` plugin |
| `/scan [dir]`  | Deep bug scan; appends findings to `potential-bugs.md`                                                                                                                  | deep-bug-scan                 |
| `/stack`       | gh-stack wrapper. Bare call = smart recommendation                                                                                                                      | stack-navigator (no args)     |
| `/techdebt`    | Scan for duplication, dead code, low-value abstractions; defer/apply/reject per item. Deferred items go to `techdebt.md` (rolling backlog, dedupes against prior runs). | —                             |
| `/verify`      | Pre-PR gate. `--deep` = full install + sequenced unit→int→e2e                                                                                                           | build-validator, oncall-guide |

## Skills

Auto-invocable — Claude fires them on intent match, no `/<name>` needed. See [`skills/README.md`](./skills/README.md) for the convention.

| Skill           | Fires when                                                                        | What it does                                                                                                                                  |
| --------------- | --------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| `test-locators` | Building or editing frontend UI (components, pages, forms, interactive elements)  | Adds stable test locators (`data-testid`/`data-test`) + a11y handles, named `<feature>-<element>-<purpose>` by business meaning, so E2E tests don't go flaky |

The skill is the **canonical definition** of the locator convention. `/grill` and `/plan` invoke it and add a `locators` lens when the diff/plan touches frontend, so the same rules apply whether you're building UI or reviewing it (the lens prompt carries a short copy of the rules, since fan-out reviewer subagents can't load the skill — keep it in sync with `SKILL.md`). External reviewers can't reach the skill either, so they restate the rules: `/dave` (Dave AI) inline in its prompt, `/rabbit` (CodeRabbit) via CodeRabbit's **web** review-instruction settings (a one-time manual paste, not a repo file).

## Workflow patterns

How the tools fit together — useful for picking the right one and combining them.

- **Pre-PR verification:** `/verify` → fix anything red → `/grill` (fans out independent reviewers, one per lens) → `/acp`.
- **Plan vs. grill — same adversarial fan-out, opposite ends of the work:** `/plan` grills an _approach_ **before** any code exists (attacks the reasoning — wrong assumptions, missing edge cases, a simpler path it skipped). `/grill` grills a _diff_ **after** you've written it (attacks the change — what input breaks it, what fails silently, what the test actually asserts). Both fan out independent reviewer subagents (one lens each, sized to the work, with a refutation pass to filter false positives) and fall back to a single independent reviewer — `plan-architect` for `/plan`, `code-architect` for `/grill` — when the Workflow tool isn't available. You'll often use both on the same piece of work: `/plan` to decide _how_, `/grill` once it's built.
- **Plan-first work:** `/plan` drafts a plan, then grills it with an adversarial Workflow — independent reviewer subagents, one lens each, sized to the plan (core 4 lenses on Sonnet for small changes, all 8 on Opus for large ones) with a refutation pass to filter false positives; if the Workflow tool is unavailable it falls back to a single independent `plan-architect` critique. It then saves the refined plan to `.claude/plans/<slug>.md` (auto-created on first run) — slug is the Jira key when detected on branch / recent commits, else a kebab-case verb-prefixed summary (`feat-…`, `fix-…`, `chore-…`). The file is checked in, rides along with the related PR(s) as a checkbox progress tracker, and is deleted by the user once the work merges to main (`/stack merge` will prompt for cleanup when the stack drains). **Caveat for stacked PRs:** every PR that ticks a checkbox modifies the same file, so frequent updates create rebase friction during `gh stack sync` — update at PR boundaries, not after every commit. For changes already in progress, `code-architect` reviews staged + unstaged diffs.
- **Review lenses by scope and durability:** three commands, picked by what you're judging and whether you want a backlog.
  - `/grill` — **diff-scoped, ephemeral.** Adversarial fan-out over the current diff pre-PR — independent reviewers across correctness, failure modes, tests, architecture, concurrency, observability, scope, and security (`code-architect` is the no-Workflow fallback for the architecture lens). Output is in-conversation only — act on it now or lose it.
  - `/scan [dir]` — **folder-scoped, durable.** `deep-bug-scan` hunts _existing_ code for real bugs (wrong logic, null risks, race conditions, SQL issues, weak assertions). Findings append to `.claude/potential-bugs.md` (auto-created on first run), kept current (fixed entries pruned).
  - `/techdebt` — **repo-scoped, durable.** Finds _structural_ issues (duplication, dead code, low-value abstractions). Deferred items go to `.claude/techdebt.md` (auto-created on first run), a deferred-only backlog (fixed/rejected items pruned).
  - Small overlap on dead code / near-duplicates between `/scan` and `/techdebt` — run `/scan` for correctness problems, `/techdebt` for cleanup.
  - The built-in `/simplify` skill covers the same _kind_ of cleanup as `/techdebt` but scoped to the current diff — reach for `/simplify` after a feature lands, `/techdebt` for periodic repo-wide sweeps.
- **CI failure triage:** `/verify` fails → it dispatches `oncall-guide` for diagnosis. You can also dispatch `oncall-guide` directly with a failing test name or CI job URL.

## Hooks

Ship hooks here only when they're **universally safe** — must no-op cleanly on projects that don't match. Scripts live in `.claude/hooks/`, referenced from `settings.json` by an absolute, shell-expanded path (`"${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/<name>.sh` — the configured Claude config dir, default `~/.claude`) — a bare relative path resolves against the session cwd and 127s in every project that doesn't itself ship the script. Anything narrower than that goes in an opt-in `settings.<name>.example.json` consumers copy from.

| Hook                  | Event                  | What it does                                                                                                                                                            |
| --------------------- | ---------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `format-on-write.sh`  | `PostToolUse` (Write\|Edit) | After Claude writes/edits a file, format it if the nearest `package.json` declares `@biomejs/biome` (preferred) or `prettier`. Uses `npx --no-install` so a missing or uninstalled formatter is a silent no-op. Skips unsupported extensions. |
| `statusline.sh`       | `statusLine`           | One line: model · context used · session cost · lines changed · 5-hour rate-limit burn. Drops any field the harness didn't send (cost is 0 early; `rate_limits` is Pro/Max-only; `used_percentage` is null before the first call and after `/compact`), so it degrades to just the model name rather than printing `null`. Exits 0 on malformed JSON and empty stdin. Needs `jq`; when it is missing the line renders a one-line reminder in place of the stats, so the cause is visible rather than the status line just going blank. |

`statusLine` isn't a hook event, but the script lives in `hooks/` because that dir is defined by *"referenced from `settings.json`"*, which is exactly what it is — and it inherits the same absolute-path convention.

## Output styles

Output styles change how Claude *talks*, not how it codes (`keep-coding-instructions: true` — note the field defaults to `false`, which would drop Claude Code's built-in engineering instructions, so never omit it here). They apply to the **main conversation only** — subagents run their own prompt, which is why chat formatting never leaks into a PR body a role agent writes. A fork is the exception; it inherits the parent's full system prompt.

| Style   | File              | What it does |
| ------- | ----------------- | ------------ |
| `Brief` | `output-styles/brief.md` | Outcome in line one. A `Needs you:` section — only when something actually blocks — as numbered, imperative steps with the URL or path inline. Enforces answer-vs-deliverable, "never invent state", and one structural emoji per line (✅ approve · ❓ answer · 🔀 merge · ⛔ unblock · 🏁 close). Delegates cost/token reporting to the status line, since a reply can only guess at it. |

**On by default** via `"outputStyle": "Brief"` in `settings.json`. To get the stock voice back, set the built-in `Default` style in `settings.local.json` (`{"outputStyle": "Default"}`) or pick it in `/config` → *Output style* — no fork of the baseline needed. `install.sh` merges this key into an existing real `settings.json` (adding it only when absent, so your own choice always wins).

**Kept over the built-in `Concise`** (v2.1.237), which covers result-first, no-preamble and short-by-default but not the `Needs you:` queue, the numbering rule, the never-state-cost-in-prose rule, or the marker discipline `show-awaiting.sh` greps for. That comparison was made against `Concise`'s **documented** behaviour — a built-in style's body isn't readable from here, so nobody has A/B'd them in use. The comparison did improve `Brief`: `Concise`'s guarantee that error reports, security warnings and destructive-action confirmations are never shortened is now in `brief.md` too.

Prior art: [attention-span](https://github.com/alexgreensh/attention-span) (AGPL-3.0). `Brief` is independently written for this MIT repo — no files vendored — but its *answer vs deliverable* split and its "emoji marks structure, never decorates" rule come from there and deserve the credit.

## Plugins

`settings.json` enables a small, deliberate set from the official marketplace (`claude-plugins-official`) via `enabledPlugins`. Official-marketplace plugins need no `extraKnownMarketplaces` — that key is only for third-party marketplaces.

| Plugin           | Marketplace               | Why it's in the baseline                                                                        |
| ---------------- | ------------------------- | ----------------------------------------------------------------------------------------------- |
| [`superpowers`](https://github.com/obra/superpowers) | `claude-plugins-official` | Skills framework: brainstorming, subagent-driven dev, systematic debugging, red/green TDD  |
| [`typescript-lsp`](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/typescript-lsp) | `claude-plugins-official` | Adds the `LSP` tool (go-to-def, find-refs, hover, workspace-symbol) for the Node/TS stack; no overlap with shipped commands |
| [`security-guidance`](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/security-guidance) | `claude-plugins-official` | Secure-coding guidance during development; additive, no overlap with shipped commands      |

**Kept out of the baseline on purpose:** plugins that duplicate this repo's command surface (`code-review`/`pr-review-toolkit` ≈ `/grill` + `code-architect`, `code-simplifier` ≈ `/techdebt`, `commit-commands` ≈ `/acp`, `feature-dev` ≈ `/plan`), and MCP-backed plugins (`github`, `linear`, `context7`) which follow the same opt-in rule as MCP servers — see `settings.plugins.example.json`.

Plugins enable behind the folder-trust gate on first launch, not silently. Consumers disable any default in their own `settings.local.json` (`"superpowers@claude-plugins-official": false`). When changing the default set, keep this table and the top-level `README.md` Plugins section in sync.

## Codex failover (opt-in)

`settings.codex.example.json` wires up OpenAI's [`codex-plugin-cc`](https://github.com/openai/codex-plugin-cc) so Codex can be driven from inside Claude Code. Its purpose is **token failover**, not review: `/codex:rescue` delegates write-capable work to Codex when Claude tokens run low, and `/codex:transfer` converts a live Claude session into a resumable Codex thread (`codex resume <id>`) for when they run out. `rescue` needs a working Claude session to orchestrate, so `transfer` is the only real escape hatch once you're empty — say so whenever documenting this.

**Kept out of the baseline for three separate reasons**, each of which is independently sufficient under this repo's rules: it needs external credentials (the MCP rule), it's a **third-party** marketplace so it needs `extraKnownMarketplaces` (the official-marketplace defaults don't), and `/codex:review` + `/codex:adversarial-review` duplicate `/grill` / `/rabbit` / `code-architect`. Also note that enabling it enables its hooks — `SessionStart`, `SessionEnd`, and a Stop-time review gate (900s timeout). Verified against a live `/codex:setup`: that gate reports `reviewGateEnabled: false` by default and is turned on explicitly with `/codex:setup --enable-review-gate`, so it's a hazard you opt into rather than inherit — but it must stay called out for anyone running `/pm-loop`.

**What `/codex:transfer` actually requires** — both preconditions, because it fails unhelpfully when either is missing: a Codex build with **external-agent session import**, and a readable Claude transcript at `~/.claude/projects/<slugified-cwd>/<session-id>.jsonl` **unless** `--source <path>` is passed. In practice auto-detection fails (`Could not identify the current Claude transcript`), which is why `/codex-handoff` resolves the newest transcript for the cwd and always passes `--source`. Note transcripts live outside the repo, so a session started in a different directory has a different project folder.

**`/codex:rescue --background` writes to the live checkout.** It is write-capable by default and runs while Claude keeps working in the same directory, so concurrent edits to the same files can be lost or interleaved. Pause edits in that scope or hand Codex an isolated worktree, and `git diff` before trusting the result — the same reason `/codex-handoff back` reconciles Codex's summary against the diff rather than believing it.

**Keep this integration modular.** All Codex content lives in that one example file plus clearly-bounded doc sections (here and in the root `README.md`). Don't thread Codex branches through unrelated machinery: the point is that mirroring it elsewhere later is a one-file copy, and that it can be dropped without unpicking anything. Marketplace sources accept `ref` (branch/tag) but **not** `sha`.

## DeepSeek backend (opt-in)

`scripts/deepseek-session.sh` runs one Claude Code session against DeepSeek instead of Anthropic. **Not a default, and not the same shape as the Codex integration above** — Codex is *delegation* (Claude drives, hands tasks to a separate process), this is *substitution* (the model behind Claude Code is replaced, so the whole session — prompts, file contents, tool results — is served by DeepSeek).

**Why it's a script and not a `settings.*.example.json`.** It works by setting `ANTHROPIC_BASE_URL` / `ANTHROPIC_AUTH_TOKEN` / the model-tier vars, which must exist **before** the `claude` process starts. There is no settings key that achieves this, so don't "harmonise" it into an example-settings file — that would be inventing config that doesn't work. This is also why `scripts/` exists as a category distinct from `hooks/`: hooks are invoked *by Claude Code*, these are invoked *by the user*.

**Two things to preserve if you edit it.**

1. It **parses** `.env` with `grep`/`sed` rather than `set -a; . .env`. Sourcing a secrets file executes arbitrary shell from it; a stray `$(...)` in someone's `.env` would run silently. There's a regression test for this (a command substitution in `.env` must not fire).
2. It `unset`s `ANTHROPIC_API_KEY`. That's the `x-api-key` header while `ANTHROPIC_AUTH_TOKEN` is `Authorization` — leaving both set would forward an **Anthropic** credential to a third-party endpoint.

**Verified live 2026-08-04** (don't re-derive these from docs, they were checked against the API): base URL `https://api.deepseek.com/anthropic`, `Authorization: Bearer` auth works, `deepseek-v4-pro` and `deepseek-v4-flash` both real, and a one-shot `claude -p` session through the launcher returned correctly. **DeepSeek's docs are wrong about the fallback** — an unrecognised model name resolved to `deepseek-v4-pro` (expensive tier), not flash as documented. Consequence worth keeping in the docs: a stale model ID inflates cost and never errors, so the IDs stay overridable via `DEEPSEEK_MODEL_PRO` / `DEEPSEEK_MODEL_FLASH`. The installed CLI also reads a **FABLE** tier that DeepSeek's setup docs omit — it's mapped to the pro tier explicitly, since leaving it unset would hit that same silent unknown-model mapping (which lands on pro anyway, so being explicit costs nothing). Subagents have their own knob, `DEEPSEEK_SUBAGENT_MODEL` (default flash), so a setup where subagents do the real work — an ai-bridge instance's role agents — can be raised without moving the haiku tier.

**Known limitation, verified not theoretical:** the session prints `claude.ai connectors are disabled because ANTHROPIC_API_KEY or another auth source is set…` and org MCP connectors (Asana, Atlassian, Slack, Supabase, …) are unavailable, because a non-OAuth auth source outranks the claude.ai login. This is inherent to substitution, not a bug in the script — `unset`ting the token would just disable DeepSeek. Agents, commands, skills, and locally-configured MCP servers are unaffected.

**`.claude/scripts/` needs an explicit `.gitignore` allow.** The root `.gitignore` denies `.claude/*` and re-includes tracked defaults one by one, so a new directory here is invisible to git until `!.claude/scripts/` is added. `install.sh` then links it automatically (it auto-discovers from `git ls-files`), which is exactly why the gitignore entry is load-bearing rather than cosmetic. `FALLBACK_DEFAULTS` in `install.sh` lists it too, for non-git tarball installs.

**🚫 Treat this as a capability a deployment can simply not have.** Substitution routes the entire session to a third party, which many organisations' data-governance rules forbid for client or customer-adjacent code. It's kept to one script plus bounded doc sections precisely so a setup under those constraints can leave the files out entirely rather than configure the risk away.

**Data governance is the consumer's call, and the docs must keep saying so.** The root `README.md` carries the scope warning and the setup walkthrough. The unsuppressible stderr banner naming the active backend is a safety feature, not noise — don't add a `--quiet`.

**Deliberately not vendoring [`aattaran/deepclaude`](https://github.com/aattaran/deepclaude).** It has more features (proxy on `:3200`, live backend switching, cost tracking) but publishes no tags or releases, so there is nothing to pin — and this repo pins third-party executable content by rule. Keeping our own ~40 lines means no unpinned third-party code sits in the path holding the API key.

## Browser control (Claude for Chrome)

**Nothing to ship here — this one is deliberately docs-only.** Claude for Chrome's `mcp__claude-in-chrome__*` tools are **injected by the extension** into a live paired session; they appear in no config file (`claude mcp list` doesn't list the server, and there's no stanza in `settings.json` or any `.mcp.json`). So there is no `settings.claudeforchrome.example.json` and there shouldn't be — inventing a `command`/`args` block would violate "don't invent tool invocations". Setup is: install the extension → grant **per-site** permissions in it → the tools appear. See the top-level `README.md` → "Browser control" for the consumer-facing version.

Two verified behaviors that shape guidance elsewhere: background subagents **do** inherit the browser connection (it isn't foreground-only), but each gets its **own tab group** rather than the human's open tabs — so agents must navigate from an explicit URL. `settings.json` **allows `mcp__claude-in-chrome__*`** — the one MCP-tool permission in the baseline, and a deliberate exception to "consumers wire up their own integrations". Rationale: permissions belong in `settings.json` per this repo's rules, and leaving these tools prompting defeats the feature's main use case, since a *background* agent stalls on a prompt nobody sees (it reads as a hang, not a block). It's safe as a default because it is **inert until the consumer installs and pairs the extension** — no extension, no tools, nothing matches — which also means the extension's per-site permissions are the real gate. `ai-bridge/symlink/.claude/settings.json` carries the same rule, because instance sessions read that file rather than this one. Two caveats to keep stated. It's server-level and cannot separate read-only navigation from **writes** (form submits, setting changes), as the tool names are extension-injected and not enumerable from config — and it applies to ordinary sessions, not only ai-bridge projects with delegated autonomy. To restore prompts without forking the baseline, shadow it in `.claude/settings.local.json` (or `~/.claude/settings.local.json` for a whole machine):

```json
{ "permissions": { "ask": ["mcp__claude-in-chrome__*"] } }
```

And it only arrives by `git pull` where `~/.claude/settings.json` is a **symlink** to this repo; `install.sh` leaves a real one untouched by design, so those users add the one allow rule themselves. Instances are fine either way — they read `ai-bridge/symlink/.claude/settings.json`.

The `ai-bridge/` subtree consumes this: a project opts in with `browser: claude-for-chrome`, and `ai-bridge/symlink/SCHEMA.md` → "Browser access" holds the agent-facing rules (browser-first, degrade when absent, writes ask-first unless the project's autonomy delegates them).

## Commands vs skills vs rules

Claude Code has three distinct mechanisms. This repo uses mostly **commands**, plus one **skill** (`test-locators`) and a set of **rules**.

- **Commands** (`.claude/commands/foo.md`) — invoked only when the user types `/foo`. No frontmatter. Best for explicit checkpoints.
- **Skills** (`.claude/skills/foo/SKILL.md` with `name` + `description` frontmatter) — Claude can auto-invoke via the `Skill` tool when the description matches user intent. Use only if you want proactive invocation.
- **Rules** (`.claude/rules/foo.md` with a `paths:` glob list) — instructions, not workflows. They load **only when Claude reads a file the glob matches**, so they carry no cost when unmatched (unlike a skill, whose name and description stay in context every turn). This is where per-area conventions live instead of bloating the root `CLAUDE.md`. Three things to know before writing one: a glob is matched **relative to the project directory** and never matches a file outside it; a rule fires on a **read**, so it cannot govern a file being created from scratch; and a rule with no `paths:` — including one whose frontmatter fails to parse — loads unconditionally at session start. These rules are **not** installed into `~/.claude` (`install.sh` excludes them): they describe this repo's own files, and as user-level rules the globs would match a consumer's unrelated `install.sh` or `.coderabbit.yaml`.

Most things here are explicit user actions (commit, verify, grill, scan) and stay commands; reach for a skill only when proactive, no-typing invocation is genuinely wanted — `test-locators` is the one case so far (it fires while building frontend, not on a typed command).

## Conventions when editing files here

- **Agents** use YAML frontmatter (`name`, `description`, optional `model`, `isolation`). `description` is what Claude Code matches on — write it as a triggerable purpose, not a title.
- **Commands** don't use frontmatter. Filename is the command name.
- When you add or remove an agent, command, or skill, update both inventories: this file and the top-level `README.md`.
- Keep files short. Front-loaded, declarative instructions beat verbose prose.
- `deep-bug-scan` appends findings to `potential-bugs.md` and must dedupe against existing entries.
- `/techdebt` writes only **deferred** findings to `techdebt.md` — it's a rolling backlog, not a log. Items fixed or rejected in a session must be removed from the file.
- After adding/moving/renaming commands, agents, or skills, restart Claude Code (`/exit`, then `claude`) and verify they register without a `skills:` prefix.
