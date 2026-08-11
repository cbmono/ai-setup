# ai-setup

**A control panel for running a small team of AI agents on your codebases — plus the [Claude Code](https://claude.com/claude-code) setup they run on.**

You describe the work. A "project manager" agent breaks it into tasks. You approve. Engineer agents go off and build it **in the background**, open pull requests, and get reviewed. You merge. That's the whole idea — you act like an engineering manager, not a pair programmer.

---

## What's in here

Two layers, and you can use either one on its own:

| Layer | What it is | Use it if… |
| --- | --- | --- |
| **[`ai-bridge/`](#layer-1-ai-bridge--the-control-panel) — the control panel** | A folder that acts as mission control for a group of repos: projects, tasks, a background project-manager loop, role agents, a knowledge base. **This is the point of the repo.** | You want work happening while you're not watching |
| **[`.claude/`](#layer-2-the-claude-code-defaults) — the defaults** | Agents, slash commands, permissions, and hooks for everyday Claude Code use (`/plan`, `/grill`, `/verify`, `/scan`, …) | You just want a better-configured Claude Code |

Built for Opus 4.8, Node.js/TypeScript projects, and stacked pull requests.

**In a hurry?** [Set up the defaults](#getting-started) (2 minutes), then [set up a control panel](#setting-up-a-control-panel) (10 minutes).

---

# Layer 1: `ai-bridge` — the control panel

An **instance** of the control panel is a small git repo that sits beside your product repos. It holds no application code — only the state of the work: what you're trying to achieve, what's in flight, what's blocked, and what the agents have learned. Agents read from it and write back to it; you steer from it.

One instance per *group* of repos (work, a side project, a client), so those worlds stay separate.

> Under the hood it's an [Open Knowledge Format (OKF)](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md) **Knowledge Bundle** — a plain-markdown, schema'd way of storing projects, tasks, and findings. You never have to think about that; the commands write the files for you.

## The core loop

This is the part to memorise. Four steps, two of them yours:

```
  /new-project  →  the PM refines it  →  ①  YOU approve  →  agents build in the
     (you)          into draft tasks       (draft → ready)    background, open PRs
                                                                      │
                       project closed  ←  ②  YOU merge  ←─────────────┘
```

| Step | Command | What happens |
| --- | --- | --- |
| **1. Describe the work** | `/new-project <description>` | Scaffolds a project folder with seed tasks, all marked `draft`. It asks a few questions (which repo? how autonomous? does it need a browser?) and nothing is dispatchable yet. |
| **2. Let the PM sharpen it** | `/pm-loop` | The project-manager agent fills in acceptance criteria, and where it genuinely can't decide, writes down numbered **open questions** for you. |
| **① Your first gate** | *`/answer`, then edit the task* | Answer its questions, then promote the task by changing `status: draft` to `status: ready` in the task file. **Only a human can do this.** Nothing gets built without it. |
| **3. Let it run** | `/pm-loop 10m` | Each tick: dispatches `ready` tasks to role agents (which work in their own git worktrees, in the background), watches their PRs, reflects merges back, and refreshes the awaiting-you queue. |
| **② Your second gate** | *(merge on GitHub)* | You merge the PR — or, for a research project, approve the deliverable. **Only a human does this too** by default — unless you've explicitly delegated that gate for a project. |
| **4. Wrap up** | `/close-project <slug>` | Consolidates what was learned into the knowledge base, logs the closeout, and deletes the project folder. Git history + the knowledge base are the record. |

**The mindset: steer, don't watch.** You should mostly see *results and questions*, not every intermediate step. If you find yourself reading agent output line by line, you're using it wrong — check `AWAITING.md` and get on with something else.

## The commands you'll actually use

All of these run from inside a control-panel instance (`cd` there, then `claude`).

| Command | What it does |
| --- | --- |
| **`/pm-loop`** | One safe, idempotent tick of the loop — refine drafts, dispatch `ready` tasks, reflect merges. Add a gap (`/pm-loop 10m`) to keep looping. Say "DRY RUN" to see what it *would* do without spawning anything. |
| **`/new-project <description>`** | Start work. Add `kind=research` for doc/deck/asset projects that produce deliverables instead of code. |
| **`/answer`** | Answers all the PM's pending questions interactively in one batch, instead of editing each task file by hand. |
| **`/close-project <slug>`** | Close a finished project (the PM flags candidates; you pull the trigger). |
| **`/audit`** | The slow counter-metric. Weekly-ish: checks whether all this throughput is actually moving your stated goals. See [Are the agents actually helping?](#are-the-agents-actually-helping) |
| **`/todo <text>`** | Quick personal reminders in `todos.md`, separate from formal project work. `/todo` lists, `/todo done <text>` closes. |
| **`/fanout`** | Send a batch of independent one-off asks to parallel background agents. (Just giving the session ≥2 independent asks does this automatically.) |
| **`/pr-review-request <filter>`** | Find related open, green PRs and draft a grouped review-request message. |

Two `SessionStart` hooks mean that when you open Claude in an instance, it greets you with what's awaiting you and any open todos — you don't have to remember to ask.

There is deliberately **no status command**. The one status artifact is `AWAITING.md`: a queue of just the items a human decision unblocks (✅ approve · ❓ answer · 🔀 merge · ⛔ unblock · 🏁 close), rewritten by each `/pm-loop` tick and injected at session start. In-flight and upcoming work is left out — it needs no decision from you, and a board you scroll past is a board you stop reading. It's **on by default and off by deletion**: `ai-bridge/install.sh` creates the file when it first stamps out an instance, and after that the loop refreshes it only if it exists and never recreates it. So `rm AWAITING.md` turns the queue off for good — even across installer re-runs — and `touch AWAITING.md` turns it back on.

## Answering the PM's questions

When a task is blocked on a decision only you can make, the PM writes numbered questions into the task document:

```
Q1: which region should we default to?
```

Answer it by appending ` --- ` and your answer, right there in the file:

```
Q1: which region should we default to? --- eu-central-1
```

The next tick folds it in and clears the question. Once the list is empty, the task is promotable. `/answer` does this for you conversationally, and answering in chat during a session works too.

## How much do you have to babysit it?

Each project has an **autonomy** setting, chosen when you create it:

| Mode | What you do | What the loop does |
| --- | --- | --- |
| **`gated`** (default) | Approve every task, merge every PR | Refines, dispatches, reports. Never promotes, never merges. |
| **`yolo`** (`/new-project … /yolo`) | Answer questions, watch for drift with `/audit` | Also promotes fully-refined drafts with no open questions, and merges a PR once its independent review is clean and CI is fully green (merging the exact verified commit). Build tasks only — research stays human-driven. |

`yolo` is genuinely all-out. Pair it with `/audit` — that's the check that catches a loop quietly gaming itself.

## Who's on the team

Role agents load **only** when you launch Claude inside an instance — they never pollute your global `~/.claude`.

| Agent | Role |
| --- | --- |
| **`project-manager`** | Runs the loop: refines drafts, asks you questions, dispatches work, tracks PRs, reflects merges, proposes closures. Never promotes and never merges. |
| **`software-engineer`** | Implements tasks in the product repos, on a branch/worktree, and opens a PR. Never merges. |
| **`devops-engineer`** | Same, for CI, infrastructure, and deployment work. |
| **`qa-reviewer`** | The independent review gate when the repo has no external reviewer configured. Judges the PR against the task's acceptance criteria, with fresh context. |
| **`cataloguer`** | Builds and refreshes the knowledge base. Read-only on product repos. |
| **`auditor`** | Read-only drift check, dispatched by `/audit`. Never acts. |
| **`oncall-guide`** | Diagnoses a red build, failed CI run, or broken deploy — including from a pasted PR number. Read-only: it reports the root cause and ranked next steps, it never fixes. Dispatched in the background whenever you ask "why is this failing?" |

## Where the work lives

```
_ai-bridge-<group>/
├── objectives/       what you're actually trying to achieve
├── projects/         active work → each with tasks (draft → ready → in-review → done)
├── knowledge/        services, findings, runbooks, teams — what's been learned
├── todos.md          quick personal reminders
├── log.md            the durable event log
└── AWAITING.md       what needs a decision from you (derived; delete it to opt out)
```

Projects come in two kinds:

- **`build`** (default) — ships code to a repo as pull requests. Agents execute; you merge.
- **`research`** — produces deliverables *inside* the bundle (docs, marp/pptx decks, assets). No repo, no PRs, human-driven. These are the strategic entry points: their conclusions graduate into `knowledge/` and spawn objectives and build projects.

**The knowledge base is pull-based.** It's never auto-loaded into context (that would bloat every session). Agents scan a one-line-per-entry index first and open only the two or three documents that matter — so nobody re-derives what the last agent already figured out.

## The safety rails

The things that stop a fleet of background agents from making a mess:

- **Two human authorities.** Promoting `draft → ready` and merging the PR are both yours **by default** — the PM does neither, and it has no way to grant itself either one. A project can explicitly delegate one or both to the loop (see the autonomy table above); absent that, they stay yours absolutely.
- **Nobody grades their own homework.** Before any PR merges it's checked by an **independent** reviewer with fresh context — CodeRabbit where the repo configures it, otherwise the `qa-reviewer` agent — judged on real signals (acceptance criteria met, CI actually green), never the implementing agent's say-so. The implementing agent self-reviews first, but that's a cheap pre-filter, not the gate.
- **One review per PR.** Left at defaults, CodeRabbit re-reviews on *every push* and replies to *every comment*, so a PR whose findings an agent then fixes burns several paid sessions re-confirming a clean diff. Agents fix, push, and reply once — they never ask for a re-review to confirm their own fix. Pin it in the target repo's `.coderabbit.yaml` (`auto_incremental_review: false`, `chat.auto_reply: false`); [this repo's own](./.coderabbit.yaml) is a working example.
- **Isolation.** Each agent gets its own git worktree and its own package store, so parallel work can't corrupt a shared checkout. Finished worktrees get reclaimed automatically.
- **No PII, no secrets.** Never in task documents, commits, PR text, logs, or the knowledge base.
- **Per-agent authorship.** Commits inside the control panel are attributed to the role that made them, so `git shortlog` tells you who did what. (Never in the product repos — many forbid AI attribution.)

## Are the agents actually helping?

`/pm-loop` optimises throughput. **`/audit`** is the independent check that the throughput is moving your real goals — run it weekly, or after a batch of projects close. The read-only `auditor` grounds each objective's success criteria against live `gh`/`git` reality and flags the four ways a busy control panel drifts:

1. **Goodhart** — lots of tasks closed, goal unmoved
2. **Measurement decay** — knowledge that's gone stale
3. **Green but not progressing** — projects that look healthy and aren't
4. **Weakened anchors** — a human gate or the verification gate quietly slipping, or a project with delegated merge authority merging PRs no independent reviewer cleared

It writes a dated report to `log.md` and **never acts**. Responding is your call.

## Setting up a control panel

First [install the defaults](#getting-started), then stamp out an instance:

```bash
mkdir -p ~/workspace/<group>/_ai-bridge-<group>
~/path/to/ai-setup/ai-bridge/install.sh ~/workspace/<group>/_ai-bridge-<group>
cd ~/workspace/<group>/_ai-bridge-<group>
$EDITOR instance.config.json          # set org, reposRoot, authorEmail
git init && git add -A && git commit -m "chore: bootstrap control panel"
gh repo create <user>/_ai-bridge-<group> --private --source=. --push
```

Then `claude` — from inside that directory — and run `/pm-loop` as a DRY RUN to see the shape of things.

A few things worth knowing:

- **The instance lives *beside* your product repos, never above them.** The group folder (`~/workspace/<group>/`) is a plain directory, not a repo. Nesting the instance above the repos would tell every product-repo session it's a control panel.
- **The leading underscore** pins it to the top of the folder listing and keeps it visible (unlike a dotfile).
- **Launch Claude from the instance directory.** Your editor's open folder doesn't decide which config loads — the working directory does.
- **The machinery is symlinked, not copied**, so a `git pull` on `ai-setup` updates every instance immediately. Your instance data is copied once and never clobbered. Re-run `install.sh` only when the template *adds* new files.
- **Want one tree in your editor?** Open the seeded `<group>.code-workspace` (VS Code / Cursor / Antigravity) for a multi-root view. Zed users: open the group folder.

**One `/pm-loop` per instance at a time.** The "one tick at a time" guarantee is per session and there's no cross-session lock — a second session looping the same instance would double-dispatch tasks and race pushes.

## Tuning: cost, speed, and depth

Set in `instance.config.json`:

- **`models` + `roleTiers`** — routes each role to a cost-appropriate model (`light`/`standard`/`deep`/`apex`, mapped to aliases like haiku/sonnet/opus/fable so they track the latest release). The PM bumps a complex task up a tier and drops a trivial one down. Omit both and everything just uses the session model.
- **`maxAgentsInFlight`** (default **10**) — how many role agents run at once. With worktree isolation this is a throughput/cost throttle, not a safety lock: raise it on a big machine, lower it on a laptop.

**Optional: local code intelligence.** Agents navigate a repo faster with a [CodeGraph](https://www.npmjs.com/package/@colbymchenry/codegraph) index than with blind grep. It's opt-in and 100% local — `npm i -g @colbymchenry/codegraph`, `codegraph install`, then `scripts/index-kb.sh` from the instance root. No index present, and agents just grep as before.

**Optional: browser access.** A project can let its agents drive a real Chrome — read a logged-in page, click through a flow, screenshot — with `browser: claude-for-chrome`. See [Browser control](#browser-control-claude-for-chrome) for what that involves.

→ **Full technical reference: [`ai-bridge/README.md`](ai-bridge/README.md)** — schema, upgrade path, per-instance settings, the lot.

---

# Layer 2: the Claude Code defaults

The everyday coding config the control panel runs on — and perfectly useful on its own. These install into `~/.claude` and apply in every project.

## Getting started

The recommended setup is **user-wide**: run `install.sh` once, and every project picks up the agents, commands, skills, and defaults automatically.

```bash
brew install jq   # or: apt install jq — the status line needs it
git clone https://github.com/cbmono/ai-setup.git ~/path/to/ai-setup
cd ~/path/to/ai-setup
./install.sh
```

`jq` is the only external dependency, and only the [status line](#status-line) uses it. Skip it and everything else works; the status line just prints a reminder instead of your cost and context.

`install.sh` symlinks this repo's tracked defaults **into** your existing `~/.claude` one entry at a time (not a whole-directory symlink), so your plugins, sessions, and `settings.local.json` stay put and Claude Code's runtime state never leaks into the repo. It's idempotent and auto-discovers what to link from what git tracks — re-run it after a `git pull` that adds a new top-level entry. See [Install](#install) for the details and the per-project alternative.

Then in any project: `claude`, then `/init` to bootstrap the project's `CLAUDE.md`. Project-state files (`/scan`, `/techdebt`, `/plan` outputs) land in the project's local `.claude/`, created lazily on first write.

Note that `install.sh` deliberately never touches `ai-bridge/` — the control panel installs into per-group instances, not into `~/.claude`.

## Agents (`.claude/agents/`)

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

## Slash commands (`.claude/commands/`)

One `.md` per command; filename becomes `/<name>`. No frontmatter required; `$ARGUMENTS` expands to whatever the user typed after the command. See [`.claude/README.md`](./.claude/README.md) for the command-vs-skill distinction and editing guidelines.

| Command        | What it does                                                                                  | Dispatches agents             |
| -------------- | --------------------------------------------------------------------------------------------- | ----------------------------- |
| `/acp`         | Stage, commit with a generated message, and push (stack-aware)                                | —                             |
| `/dave`        | Critique current diff/plan via Dave AI (Alteos-internal — requires `dave` CLI)                | —                             |
| `/grill`       | Adversarial fan-out over your own diff — find what's wrong before a reviewer does             | diff-grill workflow; code-architect (fallback) |
| `/plan`        | Draft → adversarial workflow grill → save plan to `.claude/plans/<slug>.md` (rides with the stack) | plan-grill workflow; plan-architect (fallback) |
| `/rabbit`      | Run CodeRabbit review on the current branch against `main`                                    | —                             |
| `/codex-handoff` | Hand this session to Codex when tokens run low; `back` pulls Codex's work in and verifies it against the real diff | requires the opt-in `codex` plugin |
| `/scan [dir]`  | Deep bug scan of a folder; appends findings to `.claude/potential-bugs.md`                    | deep-bug-scan                 |
| `/stack`       | gh-stack wrapper (bare = smart recommendation, args = specific actions)                       | stack-navigator (no args)     |
| `/techdebt`    | Scan for duplication/dead code; defer/apply/reject per item. Backlog in `.claude/techdebt.md` | —                             |
| `/verify`      | Pre-PR gate: typecheck / lint / test / build. `--deep` = full install + e2e                   | build-validator, oncall-guide |

**Picking among the review commands:** `/plan` and `/grill` are the same adversarial fan-out aimed at opposite ends of the work — `/plan` attacks an _approach_ before code exists, `/grill` attacks the _diff_ after you've written it (often both on the same task: `/plan` to decide how, `/grill` once it's built). `/grill` reviews the current diff (diff-scoped, ephemeral, pre-PR). `/scan` hunts bugs in existing code (folder-scoped, durable backlog at `.claude/potential-bugs.md`). `/techdebt` finds structural cleanup opportunities across the **whole repo** (deferred backlog at `.claude/techdebt.md`); for the same kind of cleanup scoped to the current diff, use the built-in `/simplify` skill. See [`.claude/README.md`](./.claude/README.md) for the full workflow patterns.

## Skills (`.claude/skills/`)

Auto-invocable capabilities — Claude fires them on intent match (no `/<name>`). One subdirectory per skill with a `SKILL.md`.

| Skill             | Fires when                       | What it does                                                                                                                  |
| ----------------- | -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| **test-locators** | Building or editing frontend UI  | Adds stable test locators (`data-testid`/`data-test`) and a11y handles with business-meaningful kebab-case names, so E2E tests don't go flaky |

The skill is the canonical definition of the convention — `/grill` and `/plan` also pull it in as a `locators` review lens on frontend changes (the lens carries a short, in-sync copy of the rules). `/dave` restates the rules inline in its prompt and CodeRabbit applies them from its **web** review-instruction settings — both run outside Claude Code and can't reach the skill.

## Settings (`.claude/settings.json`)

Pre-allows common safe operations so you see fewer permission prompts:

- Read-only git and `gh` commands
- `gh stack` navigation (view, up, down, top, bottom, checkout)
- Package-manager `run` / `install` / `test` for npm, pnpm, yarn, bun (scoped — `yarn`, `bunx`, `pnpm dlx` are **not** wildcarded)
- `npx tsc`, `eslint`, `prettier`, `vitest`, `jest` (and `bunx` / `yarn` equivalents)
- `Read` / `Edit` / `Write` scoped to the current repo (`./**`) — not the whole filesystem

And denies dangerous defaults: `git push --force …` and `git push -f …` (flag-first only), `git reset --hard …`, `git clean -f …`, `rm -rf /` / `~` / `$HOME`, `.env` reads **and** writes, SSH private keys (read/edit/write), AWS credentials (read/edit/write), `sudo`.

> **Note on deny patterns.** Mid-pattern wildcards (e.g. `git push * --force`) are documented but fragile — Anthropic's own docs warn that argument-constraint rules don't survive flag re-ordering, redirects, env-var substitution, or extra whitespace. So the deny rules above only catch flag-first force-push orderings (`git push --force origin main`, not `git push origin main --force`). If you need stronger coverage, add a `PreToolUse` hook in `settings.local.json` that inspects the full command line.

It also ships a [status line](#status-line) (spend and context at a glance) and enables the plugins below. Per-machine overrides go in `.claude/settings.local.json` (gitignored) — that's also where you'd opt into an [output style](#output-styles-claudeoutput-styles).

## Plugins enabled by default

`settings.json` enables three plugins from the official marketplace (`claude-plugins-official`) for everyone who adopts these defaults — no `extraKnownMarketplaces` needed, since the official marketplace is registered automatically:

| Plugin           | Why it's a default                                                                                            |
| ---------------- | ------------------------------------------------------------------------------------------------------------- |
| [`superpowers`](https://github.com/obra/superpowers) | Skills framework — brainstorming, subagent-driven development, systematic debugging, red/green TDD          |
| [`typescript-lsp`](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/typescript-lsp) | Adds the `LSP` tool (go-to-definition, find-references, hover, workspace-symbol) backed by a TS language server, for the Node/TS stack this repo targets |
| [`security-guidance`](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/security-guidance) | Surfaces secure-coding guidance during development; additive, no overlap with shipped commands              |

The set is intentionally small. Most other official plugins (`code-review`, `pr-review-toolkit`, `code-simplifier`, `commit-commands`, `feature-dev`) **duplicate commands this repo already ships** (`/grill` + `code-architect`, `/rabbit`, `/techdebt`, `/acp`, `/plan`) — enabling them would just create overlap.

> **Trust gate, not silent install.** On a fresh clone Claude Code first shows the "trust this folder?" prompt; only after you trust it do the plugins auto-enable. To disable one without forking, set it `false` in your own `settings.local.json` (e.g. `"superpowers@claude-plugins-official": false`).

**Opt-in, MCP-backed plugins** — `github`, `linear`, and `context7` are **not** in the baseline, following the same rule as MCP servers (kept out so consumers choose to wire them up). Copy the entries you want from [`.claude/settings.plugins.example.json`](./.claude/settings.plugins.example.json) into your own `settings.json`.

## Codex as a failover (when Claude tokens run low)

Opt-in, and the one integration here whose purpose is **not** adding a capability but **surviving the loss of one**: when you're running low on Claude tokens, hand the expensive work to [Codex](https://developers.openai.com/codex) instead of stopping. Usage counts against your *Codex* limits, which is the whole point.

It comes from OpenAI's [`codex-plugin-cc`](https://github.com/openai/codex-plugin-cc) — a Claude Code plugin, so Codex runs from inside the workflow you already have. Take the entries from [`.claude/settings.codex.example.json`](./.claude/settings.codex.example.json) and **merge them key-by-key** into your own settings: the `openai-codex` key goes *into* any existing `extraKnownMarketplaces`, and `codex@openai-codex` *into* your existing `enabledPlugins`. Pasting whole blocks over the top would drop other marketplaces or switch off the baseline plugins. Or skip the files entirely and install interactively:

```bash
/plugin marketplace add openai/codex-plugin-cc
/plugin install codex@openai-codex
/reload-plugins
/codex:setup          # reports whether Codex is ready; can install it for you
```

Needs a ChatGPT subscription (Free included) or an OpenAI API key, plus Node ≥ 18.18 and the `@openai/codex` CLI.

**The playbook — the distinction that matters:**

| Situation | Command | Why |
| --- | --- | --- |
| **Running low** | `/codex:rescue --background <task>` | Delegates real, write-capable work to Codex. Claude spends a few tokens orchestrating while Codex does the heavy lifting. Threads are resumable via `--resume`. ⚠️ See the concurrent-writes warning below. |
| **About to run out** | `/codex:transfer` | Converts *this* Claude session into a resumable Codex thread and hands back a `codex resume <session-id>`. Run it **before** you're empty. |
| **Already out** | — | Nothing in Claude Code can help: `rescue` still needs a working Claude session to orchestrate. This is why `transfer` is worth running early. |

**Prefer [`/codex-handoff`](#slash-commands-claudecommands) over raw `/codex:transfer`.** The plugin's transfer frequently fails with *"Could not identify the current Claude transcript"* — it can't reliably find the session's `.jsonl` (transcripts are keyed by **working directory**, so a session started elsewhere lives under a different project folder). `/codex-handoff` resolves it from the current directory and passes `--source` for you, records the returned session ID, and — the part the plugin has no answer for — `/codex-handoff back` brings Codex's work *into* Claude by having Codex summarise itself, then reconciling that summary against the real `git diff` rather than trusting it.

> **Round-tripping is asymmetric.** Claude→Codex is a genuine session transfer: the turn history moves, and Codex can answer questions about the earlier conversation. Codex→Claude has no equivalent primitive — nothing can resume a Claude session *from* Codex — so the return leg is a summary plus verification. Transferring also isn't free: the transcript is re-read into Codex's context (tens of thousands of tokens on a long session). Escaping a token wall justifies it; a quick question doesn't — use `/codex:rescue` for that.
>
> ⚠️ **`--background` writes to the same checkout you're still working in.** `/codex:rescue` is write-capable **by default**, so Codex edits your working tree while Claude keeps going in the same directory. Concurrent edits to the same files can be silently lost or interleaved — whoever writes last wins, and neither side knows. Either **stop editing the affected scope** until the job lands, or give Codex an **isolated worktree/branch** (`git worktree add`). Always `git diff` the result before you trust it. `/codex:status` and `/codex:cancel` tell you whether a job is still live.
>
> **The two install routes differ on pinning.** The example file pins the marketplace to `ref: v1.0.6` — it ships executable commands, a subagent, and lifecycle hooks, so tracking the upstream default branch would let new executable content arrive unreviewed. `/plugin marketplace add` does **not** pin; it follows `main`.

Manage background jobs with `/codex:status`, `/codex:result`, and `/codex:cancel`. The plugin also ships `/codex:review` and `/codex:adversarial-review`, which overlap `/grill` and `/rabbit` — reach for those if you specifically want a second opinion from a different model family, not as a replacement.

> **Why it's opt-in rather than a default plugin.** It needs external credentials (same rule as MCP servers), it lives in a **third-party** marketplace so it needs `extraKnownMarketplaces` unlike the `claude-plugins-official` defaults, and its review commands duplicate this repo's own command surface. Note too that enabling a plugin enables its hooks: this one registers `SessionStart`, `SessionEnd`, and a Stop-time review gate. That gate is **off unless you turn it on** with `/codex:setup --enable-review-gate` — leave it off on any machine running `/pm-loop`, since it makes every stop wait on a Codex review (900s timeout).

## DeepSeek as an alternative backend (opt-in)

Opt-in, off by default, and **architecturally different from the Codex integration above** — the distinction is the whole story, so don't reason about one from the other:

| | Codex (`/codex-handoff`, `/codex:rescue`) | DeepSeek (`deepseek-session.sh`) |
| --- | --- | --- |
| Shape | **Delegation** — Claude stays the driver and hands specific work to a separate `codex` process | **Substitution** — replaces the model *behind Claude Code itself* |
| What leaves | Only what you explicitly hand over | The entire session: prompts, file contents, tool results, diffs |
| Wiring | A plugin, via `enabledPlugins` | Environment variables set **before** `claude` starts — so a launcher, not a settings entry |
| Reach | Per-task, inside a normal session | Per-session, chosen at launch |

Because it's env-var based it cannot be a `settings.*.example.json` like the others — `ANTHROPIC_BASE_URL` has to exist before the process starts. So it ships as one auditable script, [`.claude/scripts/deepseek-session.sh`](./.claude/scripts/deepseek-session.sh), linked to `~/.claude/scripts/` by `install.sh`.

> 🚫 **Scope: check your data-governance rules before using this on anything but your own projects.** Substitution sends the **whole session** — prompts, file contents, tool results — to DeepSeek, so this is a data-governance decision before it's a cost one. It's a good fit for personal and side projects; it is **not** appropriate for client or customer-adjacent code unless your organisation has explicitly cleared that third party. If yours hasn't, the right move is to not install these files at all — the feature is deliberately one script plus this section, so leaving it out costs nothing.

### Set it up (about two minutes, per machine)

Each person uses **their own** DeepSeek key — keys are never shared or committed.

1. **Get a key.** Sign up at [platform.deepseek.com](https://platform.deepseek.com), create an API key, and add credit (a few dollars goes a long way — DeepSeek is roughly an order of magnitude cheaper than Opus).
2. **Make sure the script is linked.** If `~/.claude/scripts/` doesn't exist yet, re-run `./install.sh` from your `ai-setup` checkout — it picks up new top-level entries. Verify:
   ```bash
   ls ~/.claude/scripts/deepseek-session.sh
   ```
3. **Store the key.** Either export it in your shell profile, or drop it in a `.env` in the project you'll use it from:
   ```bash
   echo 'DEEPSEEK_API_KEY=sk-your-key-here' >> .env
   ```
   `.env` is gitignored here — check it's ignored in *your* project too (`git check-ignore .env`) before writing a key into it. See [`.env.example`](./.env.example).
4. **Dry-run before spending anything.** This resolves your key and prints the exact environment it would set, with the key redacted, without starting a session or making an API call:
   ```bash
   ~/.claude/scripts/deepseek-session.sh --print-env
   ```
   The `# redacted, from …` comment tells you *which* source the key came from — useful when you have both an exported var and a `.env`.
5. **Start a session.**
   ```bash
   ~/.claude/scripts/deepseek-session.sh          # then use Claude Code exactly as normal
   ```
   Optionally add `alias deepseek='~/.claude/scripts/deepseek-session.sh'` to your shell profile.

**Going back to Anthropic:** just exit and run `claude`. Nothing is persisted — the script only sets variables for the one process it launches, so there is no mode to turn off and no state to clean up. Your Anthropic login is never read, modified, or invalidated.

**What you keep:** every agent, command, and skill in this repo, plus locally-configured MCP servers. **What changes:** the model answering, and your claude.ai connectors (see below). `--help` lists all overrides.

**Confirming which backend you're on:** every run prints an unsuppressible banner to stderr naming the endpoint, models, key source, and cwd. If you don't see it, you're on Anthropic. That's deliberate — the expensive mistake is forgetting which backend is live and pasting in code that shouldn't leave your infrastructure.

### If something goes wrong

| Symptom | Cause and fix |
| --- | --- |
| `error: no DeepSeek API key found` | Not exported and not in `./.env` or your repo root's `.env`. Run `--print-env` to see what it resolves. |
| `401` / authentication failed | Bad or revoked key, or credit exhausted — check the balance at [platform.deepseek.com](https://platform.deepseek.com). Note the script strips quotes and inline comments from `.env` values, so `KEY="sk-x"  # note` is parsed correctly. |
| `error: 'claude' not found on PATH` | Claude Code isn't installed or isn't on `PATH` for this shell. |
| `ls: ~/.claude/scripts: No such file` | `install.sh` hasn't been re-run since this landed. Re-run it (step 2). |
| Connectors missing (Asana, Slack, …) | Expected, not a bug — see the connectors note below. |
| Responses feel worse than Claude | Also expected. `deepseek-v4-pro` is not Opus. The trade is cost for capability; use it where that trade makes sense. |

**Why our own ~40-line launcher instead of [`aattaran/deepclaude`](https://github.com/aattaran/deepclaude)?** That project (MIT, ~2.2k stars) does more — a local proxy on `:3200`, live `/deepseek` · `/anthropic` switching, cost tracking. But it publishes **no tags and no releases**, so there's nothing to pin, and this repo's rule is to pin third-party *executable* content deliberately (see the Codex note above). A launcher that holds your API key and proxies every request is the wrong place to track a moving default branch. Ours keeps that path auditable in one screen and reads the key by **parsing** `.env` rather than sourcing it, so nothing in a secrets file is ever executed as shell. Want the proxy and live switching? Install deepclaude separately, as a deliberate choice.

Verified live against the API on 2026-08-04: base URL `https://api.deepseek.com/anthropic`, `Authorization: Bearer` auth, and both model IDs (`deepseek-v4-pro` → opus/sonnet/fable tiers, `deepseek-v4-flash` → haiku). A real one-shot Claude Code session on the backend was confirmed working end-to-end.

**Subagents default to the flash tier** — that's DeepSeek's own recommendation and it's right for an ordinary session, but wrong wherever subagents do the real work (an ai-bridge instance dispatches its role agents as subagents, so they'd all silently run on the cheapest model whatever its `roleTiers` says). Raise just that mapping with `DEEPSEEK_SUBAGENT_MODEL=deepseek-v4-pro`, which moves subagents without dragging the haiku tier up too.

> **You lose your claude.ai connectors for that session.** Because an alternative auth source takes precedence over your claude.ai login, Claude Code prints `claude.ai connectors are disabled…` and your org's MCP connectors (Asana, Atlassian, Slack, Supabase, …) are unavailable. Agents, commands, skills, and local MCP servers still work. If a task needs a connector, run it in a normal Anthropic session.

> ⚠️ **A stale model ID costs money silently.** DeepSeek maps an *unrecognised* model name to a working model rather than erroring. Testing showed an unknown name resolving to `deepseek-v4-pro` — the **expensive** tier — which contradicts DeepSeek's docs (they say it falls back to flash). So if DeepSeek renames a model, nothing breaks and nothing warns you; you just pay pro rates. Override with `DEEPSEEK_MODEL_PRO` / `DEEPSEEK_MODEL_FLASH` / `DEEPSEEK_SUBAGENT_MODEL` and re-check the [model list](https://api-docs.deepseek.com/quick_start/pricing) rather than waiting for an error. These IDs are deliberately *not* validated against a whitelist — a hardcoded list of known models would recreate exactly the staleness problem the overrides exist to solve. The startup banner prints the resolved models every run, which is what actually catches a wrong one.

## Browser control (Claude for Chrome)

Letting Claude drive a real browser — read a logged-in page, click through a flow, screenshot — comes from **[Claude for Chrome](https://claude.com/chrome)**, and it is **not** something this repo can ship you. There is nothing to copy into `settings.json`.

The extension **injects** its tools into a live paired session, so they never touch a config file: `claude mcp list` doesn't show `claude-in-chrome`, and there's no stanza in `~/.claude/settings.json` or any project `.mcp.json`. Unlike a stdio server (which is a `command`/`args` block you can commit), this one has no shippable form — so it gets **no `settings.*.example.json` here**; the canonical opt-in-MCP exemplar stays [`.claude/settings.plugins.example.json`](./.claude/settings.plugins.example.json).

To enable it, per machine:

1. Install the Claude for Chrome extension and sign in.
2. Grant it permission **per site**, in the extension — that's the real access gate, not a Claude Code setting.
3. Start a session with the browser paired. `mcp__claude-in-chrome__*` tools appear on their own.

Two behaviors worth knowing before you rely on it:

| Behavior | What it means for you |
| --- | --- |
| **Background subagents inherit the connection** | A background agent really can drive Chrome — it isn't foreground-only. Verified against a live connection. |
| **…but each gets its own tab group** | An agent does **not** see your open tabs. It opens and drives its own, so brief it with an explicit URL rather than "the page I have open". |

> **The baseline allows `mcp__claude-in-chrome__*`.** Without it every browser action prompts, which silently breaks the main use case — a **background** agent stalls waiting for a human who isn't watching, and the task reads as hung rather than blocked. The rule is safe to ship because it's **inert until you opt in at the extension**: no extension installed means the tools never exist and nothing matches. That makes the **extension's per-site permissions** the boundary that actually governs this, so restrict there rather than relying on Claude Code prompts.
>
> **Whether a `git pull` actually delivers it depends on how your `~/.claude/settings.json` got there** — worth checking, because the failure is silent:
>
> | Your setup | Do you get the rule? |
> | --- | --- |
> | `~/.claude/settings.json` is a **symlink** to this repo (what `install.sh` does when you had none) | **Yes**, automatically |
> | You have your **own real** `~/.claude/settings.json` | **No.** `install.sh` deliberately never edits it, so add the rule yourself (below) |
> | ai-bridge **instances** | **Yes** — they read `ai-bridge/symlink/.claude/settings.json`, which is symlinked, so no per-machine step |
>
> If you're in the middle row, add this to your own `settings.json` (or `settings.local.json`) — one line, no need to adopt the whole baseline:
>
> ```json
> { "permissions": { "allow": ["mcp__claude-in-chrome__*"] } }
> ```
>
> Two consequences worth being deliberate about. It applies to **ordinary sessions too**, not just ai-bridge — so once a browser is paired, Claude can act (including submitting forms) without asking anywhere. And it's a server-level rule: it can't distinguish read-only navigation from writes, because the tool names are injected by the extension and aren't enumerable from config. To keep prompts, shadow it in your own `settings.local.json`:
>
> ```json
> { "permissions": { "ask": ["mcp__claude-in-chrome__*"] } }
> ```

## Status line

`settings.json` ships a status line, because spend is the one thing Claude genuinely cannot report: ask it what a session cost and it will guess. The harness feeds the script real numbers instead.

```text
Opus · 34% ctx · $1.62 · +212/-48 · 5h 24%
```

Model · context window used · estimated session cost · lines added/removed · share of your 5-hour rate limit burned. Every field is optional and gets dropped rather than faked — cost is `0` before any work, `rate_limits` only exists for Claude.ai Pro/Max subscribers, and context percentage is `null` before the first API call and right after `/compact`. On a fresh session you just see `Opus`.

Needs [`jq`](https://jqlang.org/) — the one external dependency in this repo (`brew install jq`, or `apt install jq`). Without it the line renders a one-line reminder in place of the stats rather than going blank, and `install.sh` warns you at the end. Malformed JSON and empty stdin both exit 0.

To turn it off without editing the baseline, override the whole key in `.claude/settings.local.json`:

```json
{ "statusLine": { "type": "command", "command": "true" } }
```

One caveat: `/statusline` rewrites whichever settings file currently defines `statusLine`. If that file is the symlink into this repo, it edits the repo — so prefer the local override above.

## Output styles (`.claude/output-styles/`)

An output style changes how Claude *talks*, not how it codes. This repo ships one and **enables it by default**.

**`Brief`** — the outcome in line one, then a `Needs you:` section *only when something actually blocks*, written as numbered imperative steps with the URL or path inline. It also carries three rules worth having on their own:

1. **Answer vs deliverable.** An answer says its point and stops; a doc, plan, spec, or PR body runs as long as the work needs. Trims the reply, never the reasoning.
2. **Never invent state.** Unknown is "unknown". A fabricated status is worse than a missing one — and cost never goes in prose, because the status line has the real figure.
3. **One structural emoji per line**, never decoration: ✅ approve · ❓ answer · 🔀 merge · ⛔ unblock · 🏁 close. Never in code, commits, or PR bodies.

**To get the stock Claude Code voice back**, set the built-in `Default` style in `.claude/settings.local.json` (project) or your own user settings — no need to fork the baseline. `/config` → *Output style* does the same thing and writes to the project's local settings.

```json
{ "outputStyle": "Default" }
```

Styles apply to the **main conversation only** — subagents run their own prompt, so chat formatting can't leak into a PR body an agent writes. (A [fork](https://code.claude.com/docs/en/sub-agents) is the exception: it inherits the parent's whole system prompt.) The style body is ~450 tokens of input, added once per session and cached after the first request.

Prior art: [attention-span](https://github.com/alexgreensh/attention-span) (AGPL-3.0), a nice collection of ADHD-friendly styles worth a look. `Brief` is written independently for this MIT repo — nothing vendored — but the *answer vs deliverable* split and the "emoji marks structure, never decorates" rule are theirs, and the credit is due.

## Hooks shipped in the baseline

`settings.json` wires up one hook by default — anything narrower stays in opt-in `.example.json` files.

| Hook                 | Event                       | Behavior                                                                                                                                                                                                                  |
| -------------------- | --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `format-on-write.sh` | `PostToolUse` (Write\|Edit) | Formats the file Claude just wrote, if the nearest `package.json` declares `@biomejs/biome` (preferred) or `prettier`. Uses `npx --no-install`, so a missing or uninstalled formatter is a silent no-op. Never blocks the tool. |

The script self-detects — projects without a declared formatter, files outside the project, and unsupported extensions all no-op cleanly. `settings.json` points at it as `"${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/hooks/format-on-write.sh` — the configured Claude config directory, defaulting to `~/.claude` — so it resolves the same from any project. (A bare relative `.claude/hooks/…` would resolve against whatever directory you launched Claude in, and fail everywhere else.) `install.sh` resolves its install target the same way, so if you relocate your config dir with `CLAUDE_CONFIG_DIR` the hook follows it. To disable, remove the `hooks` block from your `settings.json` or shadow it in `settings.local.json`.

---

# Install

## Option A — Adopt as user-wide defaults

Clone the repo and run `install.sh`:

```bash
git clone https://github.com/cbmono/ai-setup.git ~/path/to/ai-setup
cd ~/path/to/ai-setup
./install.sh
```

The script symlinks each tracked default (`agents/`, `commands/`, `skills/`, `hooks/`, `output-styles/`, `scripts/`, `MEMORY.md`, `claude-defaults.md`) **into** your real `~/.claude`, rather than replacing `~/.claude` with one big symlink. Two reasons this matters:

- **Your `~/.claude` keeps owning its runtime state** — `plugins/`, `sessions/`, `projects/`, `history.jsonl`, `settings.local.json`. A whole-directory symlink would either nest inside an existing `~/.claude` (a silent no-op) or relocate all that state into the repo, where it'd clutter the working tree.
- **It auto-discovers what to link from `git ls-files`**, so a new top-level default added to the repo is picked up on the next run — there's no list to maintain. Re-running is idempotent; anything it would overwrite is backed up to `*.bak.<timestamp>`. Entries are linked whole, so if `~/.claude` already has a real `commands/`/`agents/`/`skills/` of your own, that directory is moved aside to `*.bak.<timestamp>` (recoverable) and replaced by the symlink — keep personal global commands per-project (`<project>/.claude/commands/`) instead, since `~/.claude/commands/` now points into this repo.

`settings.json` is handled deliberately. If you don't already have one it's linked, so the repo's permission + plugin baseline applies user-wide. If you do, **your permissions, env, and plugins are never touched** — the script prints how to adopt the full baseline and leaves the choice to you.

The exception is the two **display-only** keys, `statusLine` and `outputStyle`, which the installer merges into your existing file — otherwise the status line and output style would only ever reach people who had no `settings.json` at all, which is nobody with an established install. That merge is narrow on purpose:

- It only ever **adds a key that's absent**. If you've set your own `outputStyle`, yours wins and re-running never reverts it.
- It **backs your file up** first (`settings.json.bak.<timestamp>`), and uses `jq` so the file is parsed as JSON rather than edited line-wise. Invalid JSON or no `jq` means it's left alone with a printed instruction instead.
- **Only display keys are eligible.** Nothing that changes what Claude is *allowed to do* is ever merged in — silently granting a permission during an install is the surprise this script exists to avoid.

Pull updates anytime with `git pull` — because the links are live, content changes and new files inside linked dirs apply immediately, no re-sync. To back out, `./install.sh --uninstall` removes only the symlinks it created, leaving your runtime state, real files, and backups untouched.

## Option B — Per-project

Use this when you want stability per project (**frozen** defaults that *don't* track the repo), or for project-specific tweaks. This is a **copy**, not a link — so unlike Option A it won't pick up later repo changes; re-run it to refresh.

For a fresh project (no existing `.claude/`):

```bash
cp -r ~/path/to/ai-setup/.claude ~/path/to/your-project/.claude
```

For a project that already has a `.claude/`:

```bash
rsync -a --exclude='settings.local.json' ~/path/to/ai-setup/.claude/ ~/path/to/your-project/.claude/
```

That single exclusion is enough — this repo's `.claude/` no longer carries `potential-bugs.md`, `techdebt.md`, or `plans/`. Those project-state artifacts are auto-created in the target by their respective commands (`/scan`, `/techdebt`, `/plan`) on first run, and stay gitignored. `CLAUDE.md` at the project root is also never touched. If you've customised `.claude/MEMORY.md`, back it up before syncing — it will be overwritten.

## Bootstrap a CLAUDE.md

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

# Stacked pull requests (gh-stack)

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

# Opus 4.8

This config targets Opus for planning and review, Sonnet for implementation (model
aliases, so they track the current release rather than pinning a version that goes stale).

Key behaviours worth internalizing:

- **Default effort is `xhigh`.** Use `/model` to adjust — `high` for concurrent sessions, `max` for gnarly problems only.
- **Adaptive thinking.** Fixed thinking budgets aren't supported; nudge with "think carefully and step-by-step" or "respond directly."
- **Less delegation by default.** Tell it explicitly: "Spawn subagents in parallel for each..."
- **Fewer tool calls.** Tell it explicitly: "Grep thoroughly before answering."
- **Front-load the spec.** Every turn adds reasoning overhead — state constraints, acceptance criteria, and file locations in turn one.

---

# Customizing

- **Add a command:** drop an `.md` file in `.claude/commands/` — the filename (minus `.md`) becomes the `/command`. Use `$ARGUMENTS` for user-supplied args. No frontmatter needed. **Don't put a `README.md` in `.claude/commands/`** — Claude Code scans every `.md` there as a command, so a README becomes `/README`. See [`.claude/README.md`](./.claude/README.md) for the command-vs-skill distinction.
- **Add an agent:** drop an `.md` file in `.claude/agents/` with YAML frontmatter (`name`, `description`, optional `model`, `isolation: worktree`).
- **Adjust permissions:** edit `.claude/settings.json` for team-shared rules, `.claude/settings.local.json` for this machine only.
- **Change the control panel's machinery:** edit files under `ai-bridge/symlink/` — every instance picks the change up immediately, since they symlink it. Keep it generic: org, repo, path, team, and channel names belong in an instance's `instance.config.json`, never in the template.
- **Compounding engineering:** when Claude does something wrong, add the rule to your project's `CLAUDE.md` so it doesn't recur.

> **Restart after adding commands or agents.** Claude Code scans `.claude/commands/` and `.claude/agents/` at session start. New files aren't picked up until you `/exit` and relaunch `claude`. If `/<your-new-command>` returns "Unknown command", that's why.
>
> **Commands vs skills:** this repo uses `.claude/commands/` for explicit `/name` invocations. If you want Claude to auto-invoke a capability based on user intent, use `.claude/skills/<name>/SKILL.md` with YAML frontmatter instead — see the Claude Code docs on skills.

---

# Conventions in this repo

- `.claude/settings.json` — checked in, team-shared permissions baseline
- `.claude/settings.local.json` — gitignored, per-machine overrides
- `.claude/settings.plugins.example.json` — reference only, opt-in MCP-backed plugins (github, linear, context7)
- `.claude/settings.codex.example.json` — reference only, opt-in Codex failover (`/codex:rescue` when tokens run low, `/codex:transfer` before they run out)
- `.claude/potential-bugs.md`, `.claude/techdebt.md`, `.claude/plans/` — gitignored, auto-created by `/scan`, `/techdebt`, `/plan` on first run; never seeded in this repo
- `ai-bridge/` — the control-panel template: `symlink/` (machinery, shared live by every instance) and `seed/` (starting content, copied once). A separate subtree; the user-wide `install.sh` never touches it
- `CLAUDE.md` (this repo's root) — guidance for Claude when editing **this config repo itself**, not a template
- `.coderabbit.yaml` — this repo's own CodeRabbit settings; **not** installed into `~/.claude` (the installer only touches `.claude`). Tuned for **one review per PR**: no re-review on each push, no auto-reply to every comment. Copy it into your own repos if agent-authored PRs are burning review sessions there too

---

## License

MIT. See [LICENSE](./LICENSE).
