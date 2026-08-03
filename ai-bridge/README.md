# ai-bridge (template)

A reusable **OKF Knowledge Bundle control panel** for orchestrating background AI
agents against a group's product repositories. This directory is the **generic
template**; you stamp out one **instance** per group (work, side project, …),
each its own git repo.

```
ai-setup/ai-bridge/        # this template (lives in the ai-setup repo)
├── install.sh                    # stamp out / refresh an instance
├── symlink/                      # generic machinery → symlinked into instances (gitignored there)
│   ├── SCHEMA.md  agents/index.md  scripts/commit-as.sh
│   └── .claude/{agents/*, commands/{status,pm-loop,new-project,pr-review-request,todo,fanout}.md, hooks/{show-awaiting,show-todos}.sh, settings.json}
└── seed/                         # starting content → copied into an instance once (then yours)
    ├── instance.config.json  CLAUDE.md  README.md  index.md  log.md  .gitignore
    ├── bridge.code-workspace     # multi-root editor view; install.sh seeds it as <group>.code-workspace
    ├── todos.md            # quick personal reminders (/todo); shown at session start
    └── objectives/  projects/  knowledge/{services,findings,runbooks,teams}/
```

## Why template + instance

Only `CLAUDE.md` cascades through parent directories in Claude Code — subagents,
commands, skills, and `settings.json` load only from `~/.claude` or a **project
root** `.claude/`. So a group-level overlay can't exist; instead each group gets a
project-root control panel whose role agents load **only** when you launch Claude
inside it (never polluting `~/.claude`). The generic machinery stays DRY via
symlinks; each instance keeps its own git history (work vs. personal stay separate).

## Create an instance

Name the instance directory **`_ai-bridge-<group>`** (e.g. `_ai-bridge-acme`). The
leading underscore pins it to the top of the group folder and keeps it visible
(unlike a dotfile); the `-<group>` suffix disambiguates it from this template dir
(`ai-bridge`) and from other groups' instances. It lives **inside** the group
folder, beside that group's product repos:

```bash
mkdir -p ~/workspace/<group>/_ai-bridge-<group>
ai-setup/ai-bridge/install.sh ~/workspace/<group>/_ai-bridge-<group>
cd ~/workspace/<group>/_ai-bridge-<group>
$EDITOR instance.config.json          # set org, reposRoot, authorEmail
git init && git add -A && git commit -m "chore: bootstrap control panel"
# create a uniquely-named private remote — keep the leading underscore so a fresh
# `git clone` lands a `_ai-bridge-<group>/` dir that matches this convention:
gh repo create <user>/_ai-bridge-<group> --private --source=. --push
```

The group folder itself (`~/workspace/<group>/`) is **not** a repo — it's a plain
directory holding this instance plus the group's product repos side by side, each
its own repo. Start a Claude session **inside the instance** (`cd
~/workspace/<group>/_ai-bridge-<group> && claude`) so the role agents and
`/pm-loop` load; a group-wide `~/workspace/<group>/CLAUDE.md` cascades in
automatically (keep control-panel rules out of it — it also cascades into the
product repos).

`install.sh` symlinks the machinery in (gitignored), copies the seed content once
(never clobbering data on re-run), and manages the machinery block in the
instance's `.gitignore`. It is idempotent; `install.sh --uninstall <dir>` removes
only the symlinks it created.

## Run it
The spine, from inside an instance:

> **`gated` (default):** `/new-project <description>` → you approve `draft → ready` → `/pm-loop 10m` → you merge the PR
>
> **`yolo` (all-out):** `/new-project <description> /yolo` → `/pm-loop 10m` — the loop promotes clean build drafts, dispatches, and merges each PR on a clean review + green CI. You just answer its questions (`/answer`) and watch for drift (`/audit`).**

`/pm-loop` is a serial, completion-gated loop (one tick at a time). Two human gates
stay yours by default: promote `draft → ready`, and merge the PR (build) / approve the
deliverable (research). The idea is to **steer, not watch** — role agents run in the
background and bubble up results and questions, not every step. **A project's `autonomy`
(default `gated`) can hand the loop those gates:** `yolo` runs it **all-out** —
auto-promotes fully-refined drafts with no open questions (build tasks only; research
stays human-driven) **and** merges a PR once its independent review has no unaddressed
comments and CI is fully green (merging the exact verified commit). Pair yolo with
[`/audit`](#audit-loop-slow-counter-metric) — the counter-metric that watches an
autonomous loop for drift.

**Answering the PM's questions:** when a `draft` is blocked it lists numbered
`open_questions` (`Q1:`, `Q2:`, …). Answer one **in the task doc** by appending
` --- <answer>` to that line — e.g. `Q1: which region should we default to? --- eu-central-1`.
The next tick treats anything after the ` --- ` as your answer, folds it into the task,
and clears the question; the `draft` becomes promotable once the list empties. (Answering
in chat during a session works too.)

**Monitor without driving:** `/status` renders a board of every task grouped by what
it needs — 🔴 awaiting you (approve · answer · merge · unblock) · 🟡 in flight ·
🟢 next · ⛔ blocked — and writes it to a **derived, gitignored `DASHBOARD.md`**.
It's read-only (never dispatches/promotes/merges), safe to run even mid-loop; each
`/pm-loop` tick refreshes the board too, and a `SessionStart` hook surfaces its
"awaiting you" items when you launch Claude in the instance. Run **one `/pm-loop`
per instance** at a time (the serial guarantee is per-session; see `pm-loop.md`).

## Projects: build & research
Projects come in two `kind`s (see `symlink/SCHEMA.md`):
- **`build`** (default) — ships code to a `target_repo` as PRs; role agents execute,
  you merge. The full `draft → ready → dispatch → PR → merge` loop.
- **`research`** — produces **deliverables inside the bundle** (docs, marp/pptx decks,
  assets under `projects/<slug>/deliverables/`); no repo, no PRs, **human-driven**
  (the PM tracks but never dispatches them). These are the strategic entry points
  whose conclusions graduate into `knowledge/` and spawn objectives + build projects.

`/new-project` scaffolds either; pass `kind=research` for the latter. It also takes
optional capability flags — `autonomy=gated|yolo` (`/yolo`),
`clis="…"` (`/cli …`), and `browser=claude-for-chrome` (`/claudeforchrome`) — and
**interactively asks for any you don't pass** (pre-filling detected CLIs/MCPs). They're
recorded on `project.md` and honored by later machinery (yolo by the PM loop, browser by
the claude-in-chrome integration); creating a project never itself promotes or merges.

After scaffolding, `/new-project` runs an **advisory second-opinion review of the new
project** with the **CodeRabbit CLI** (`cr`) when it's installed and signed in — scoped to
`projects/<slug>`, with `SCHEMA.md` + the instance `CLAUDE.md` passed in as review
instructions. It ships a triage list so lifecycle features aren't "fixed" as defects (empty
`acceptance_criteria` belong to the PM's refine; a research project's `deliverables/*.md`
stubs are unwritten work; `draft` is the human's gate), and it records what was applied
**and what was rejected, with reasons** in the project's `log.md`. No CLI (or `--no-commit`)
→ skipped with a one-line note; the review never gates creation.

## Browser access (`browser: claude-for-chrome`)
A project can let its role agents **drive a real browser** — read a logged-in page, click
through a flow, screenshot — via **Claude for Chrome**. Opt in at creation
(`/claudeforchrome`) or by setting `browser: claude-for-chrome` on `project.md`; default
`off`. Agent-facing rules live in `symlink/SCHEMA.md` → "Browser access".

There is **nothing to configure in the instance**. The Chrome extension *injects* the
`mcp__claude-in-chrome__*` tools into a live paired session — no `mcpServers` stanza, no
`.mcp.json`, and `claude mcp list` doesn't even show it. Machine-level setup is: install the
extension, then grant it **per-site** permissions there.

What this means in practice:
- **Background role agents can use it.** The connection is inherited by background
  subagents, so this is *not* foreground-only — `/pm-loop`-dispatched agents can drive
  Chrome. To make that reachable, `software-engineer`, `devops-engineer`, and `qa-reviewer`
  carry `ToolSearch, mcp__claude-in-chrome__*` in their `tools:` allowlist (a closed
  allowlist otherwise excludes every MCP tool). The pattern resolves to nothing when the
  extension isn't paired, which is harmless — the rest of the allowlist still resolves.
- **Each agent gets its own tab group**, not the human's open tabs. Agents must navigate
  from an explicit URL; they can't "look at the tab you have open".
- **A headless/cron tick has no browser.** Agents degrade to a non-browser route and say
  so, rather than reporting the task blocked.
- **Writes follow the project's `autonomy`.** Under `yolo` browser writes are permitted
  (forms included) — the loop already self-promotes and self-merges, so carving out the
  browser would be inconsistent. Under `gated`, ask first. Read-only navigation and
  screenshots need no permission either way.
- **`yolo` alone isn't enough to make it autonomous — mind the second gate.** Claude Code's
  tool permissions sit *underneath* a project's `autonomy`. If `mcp__claude-in-chrome__*`
  is left prompting (the shipped default), a background agent stalls waiting on a human who
  isn't watching, and the task looks hung rather than blocked. To get genuinely autonomous
  browser work, allowlist those tools in the machine's `settings.local.json` as well — and
  from that point the extension's **per-site permissions** are the boundary that actually
  holds, so restrict there.

> **Upgrading an existing instance:** re-running `install.sh` picks up `SCHEMA.md` and the
> role agents (symlinked), but **not** `CLAUDE.md` — seed content is copied only when
> absent, never clobbered. Add the **Browser** bullet from `seed/CLAUDE.md`'s "Conventions
> for role agents working in target repos" to your instance's `CLAUDE.md` by hand.

## Editor view (control panel + repos in one tree)
The product repos stay **physical peers** of the instance, never nested inside it
— nesting would drag the instance's control-panel `CLAUDE.md` into the cascade of
every product-repo session (telling them they're a control panel that commits to
`main`). To still see everything in one tree:
- **VS Code / Cursor / Antigravity** — open the seeded **`<group>.code-workspace`**
  (*Open Workspace from File…*): a multi-root view, control panel pinned on top,
  group repos below. A generic `files.exclude` glob (`_ai-bridge-*`) hides the
  instance from the repos pane so it isn't shown twice.
- **Zed** (no workspace-file support) — open the **group folder**; the instance's
  `_`-prefix already sorts it to the top.

It only changes the editor display; nothing moves on disk. **Regardless of editor,
launch Claude by `cd`-ing into the instance dir and running `claude` there** — the
editor's open folder doesn't affect which `.claude/` loads; the working directory
does.

## Per-instance settings
`.claude/settings.json` is **shared machinery** (symlinked) — editing it changes
every instance. For permissions or env an instance needs on its own (e.g. allow
`Bash` in that group's repos), put them in `.claude/settings.local.json` in the
instance: it's local, gitignored, layered on top, and never touches the template.

## Verification gate
Before any PR merges, it's checked by an **independent** reviewer — fresh context,
judged on real signals (acceptance criteria met, CI actually green), never the
implementing agent's self-report. Role agents embed the task's `acceptance_criteria`
in the PR body so the reviewer evaluates against them. The reviewer is an external one
(e.g. CodeRabbit) when the repo configures it, otherwise the `qa-reviewer` agent is the
fallback. Before *that*, the implementing agent **self-reviews its own diff** and fixes
findings (`code-architect` / a careful pass) — a pre-filter that
shifts cheap issues left, **not** a replacement for the independent gate.

**One review per PR (cost control).** The gate needs *one* fresh-context review, not a
review per push. Left at its defaults CodeRabbit re-runs on **every push** and replies to
**every comment**, so a PR whose findings an agent then fixes burns several sessions to
re-confirm a diff that's already clean. Three rules keep it to one:
1. **Pin it in the target repo's `.coderabbit.yaml`** — `reviews.auto_review.auto_incremental_review: false`
   (stop re-reviewing each push) and `chat.auto_reply: false` (stop replying to every
   comment; it still answers an explicit `@coderabbitai`). Both default to `true`. This
   repo's own [`.coderabbit.yaml`](../.coderabbit.yaml) is a working, commented example.
2. **Don't pay for the same reviewer twice.** If CodeRabbit reviews the PR, the
   pre-filter self-review uses the *free local* reviewer (`code-architect`), not the
   `coderabbit` CLI. `qa-reviewer` likewise **reads** an existing CodeRabbit review off the
   PR (via the structured `--json reviews`, not `--comments`) rather than re-running the CLI
   over the same diff — and when the repo is configured but hasn't been reviewed *yet*, it
   reports the gate as pending instead of substituting a CLI run.
3. **Never re-review to confirm a fix.** Agents address findings, push, and reply once
   with what changed. A re-review is requested only after a rewrite substantial enough to
   invalidate the original review.
**Recommended: set branch protection to require CI green + a review from that
reviewer** (e.g. CodeRabbit as a required reviewer, or a dedicated verifier status
check). Note GitHub only enforces *that* CI passed and a review happened — whether the
reviewer actually checked the acceptance criteria is the reviewer's job, not something
branch protection can guarantee. Under `yolo` this same clean-review + green gate is what
lets the loop merge; under `gated` it's surfaced for you (see the PM loop).

## Audit loop (slow counter-metric)
`/pm-loop` optimizes throughput; **`/audit`** is the independent check that the
throughput is actually moving the real goals. Run it on a **slow cadence** (weekly, or
after a batch of projects close): the read-only `auditor` grounds each objective's
`success_criteria` against live `gh`/`git` reality and flags the four ways a busy
control panel drifts — **Goodhart** (lots closed, goal unmoved), **measurement decay**
(stale `Finding`s), **green-but-not-progressing** projects, and any **weakened anchor**
(a human gate or the verification gate slipping, or a `yolo` project merging PRs an
independent reviewer hasn't cleared). It writes a dated audit to `log.md` and **never acts** — responding
(adjust targets, re-validate findings) is your governance call. It's the independent
signal that catches a `yolo` loop gaming itself — a periodic, advisory guardrail, not a
merge-blocking guarantee.

## Model routing
Role dispatches are routed to a cost-appropriate model. Two knobs in
`instance.config.json`:
- `models` — maps tiers to model aliases: `{ "light": "haiku", "standard": "sonnet",
  "deep": "opus", "apex": "fable" }`. Aliases track the latest model in each tier, so
  you retune per instance without editing agents.
- `roleTiers` — each role's default tier (e.g. `project-manager` → `deep`, `qa-reviewer`
  → `deep`, `cataloguer` → `light`, engineers → `standard`). The top **`apex`** tier
  (`fable`) is reserved for the **deepest, rarest reasoning** — the `plan-architect`
  critique the PM dispatches on genuinely complex tasks — where a frontier model earns
  its cost. The orchestrator itself runs on `deep` (opus): plenty for routing, and it
  ticks often. Retune per instance as cost dictates.

Per tick the PM starts from the role's default tier, **bumps a complex build task
up** (multi-file/service, or heavily-inferred `acceptance_criteria`) and **drops a
trivial one down**, then resolves the tier via `models` and passes that model on
dispatch. A task can force a specific model with a `model:` field (a tier or a raw
alias) — the PM honors it verbatim. Omit both maps and everything just inherits the
session model.

## Concurrency
`maxAgentsInFlight` (in `instance.config.json`, default **10**) caps how many role agents
the PM runs at once. With worktree isolation + private package stores the old corruption
risk is gone, so this is a **throughput/cost throttle**, not a safety lock — tune it to the
machine and account: raise it on a well-resourced box with mostly-independent tasks, lower
it (e.g. 5) on a laptop or when role agents lean on `Workflow` fan-outs. One hard rule holds
regardless of the number: never two package installs against the **same repo's store** at
once (the PM staggers deps-touching tasks across ticks). A role agent's own `Workflow`
fan-out is a separate layer, bounded by the Workflow tool's own concurrency.

## Local code intelligence (codegraph, optional)
Role agents navigate product repos faster with a local **CodeGraph** index than with
blind grep. It's opt-in and 100% local (no code leaves the machine) — the replacement
for the old mempalace memory hook.

1. **Install the CLI:** `npm i -g @colbymchenry/codegraph`.
2. **Expose it to agents (MCP):** `codegraph install` wires the codegraph MCP into
   Claude Code (writes the MCP config + an auto-allow permissions list). Use
   `codegraph install -y` for non-interactive, or `--print-config <id>` to inspect first.
3. **Index the repos:** from the instance root, run `scripts/index-kb.sh` — it reads
   `reposRoot`, indexes every product repo (incremental on re-run), and skips
   worktrees (`_wt`), instance dirs (`_ai-bridge-*`), and non-git dirs. Add infra/
   assets repos with no useful call graph via `codegraphSkip` in
   `instance.config.json` (space-separated) or `$CODEGRAPH_SKIP`. `--with-serena`
   also warms a Serena LSP cache when Serena is installed.

Each repo gets a `.codegraph/` index and a defensive `codegraph.json` exclude. Role
agents detect the index and use it automatically (see the "Conventions for role
agents" section of an instance's `CLAUDE.md`); with no index present they just grep
as before.

## Machinery is machine-local
The symlinks point at absolute paths into this template and are gitignored in the
instance, so a clone on another machine has the committed instance data but
**dangling** machinery until you re-run `install.sh` there. That's intentional —
the machinery is sourced from `ai-setup`, not vendored into each instance.

## Updating the machinery
Edit files under `symlink/` here and commit to `ai-setup`. Because instances
symlink them, every instance picks up the change immediately — re-run `install.sh`
on an instance only when you **add** new machinery files (to refresh its symlink
set and `.gitignore` block). Keep machinery generic: no org, repo, path, team, or
channel literals — those belong in each instance's `instance.config.json` /
`CLAUDE.md`.

## Upgrading an existing instance
When the template gains new machinery or new seed keys, bring an already-stamped
instance up to date:

1. **Pull the template** you stamped from (`ai-setup`, or your fork) to `main`. The
   symlinked machinery — agents, commands, `SCHEMA.md`, scripts — updates **immediately**
   (the instance symlinks it); no reinstall needed for *changed* files.
2. **Re-run the installer** to link any **new** files and refresh the gitignore block:
   `ai-setup/ai-bridge/install.sh <instance-dir>`. Idempotent — it never clobbers your
   instance data.
3. **Merge new seed keys by hand.** Seed content (`instance.config.json`, the instance
   `CLAUDE.md`) is copied **once** and never overwritten, so new keys don't auto-arrive.
   In particular, if `instance.config.json` lacks the model-routing block, add it —
   otherwise model routing stays off and everything runs on the session model:
   ```json
   "maxAgentsInFlight": 10,
   "models":    { "light": "haiku", "standard": "sonnet", "deep": "opus", "apex": "fable" },
   "roleTiers": { "project-manager": "deep", "software-engineer": "standard",
                  "devops-engineer": "standard", "qa-reviewer": "deep",
                  "cataloguer": "light", "auditor": "deep", "plan-architect": "apex" }
   ```
   Optionally fold any new conventions from the template's `seed/CLAUDE.md` into your
   instance's `CLAUDE.md`.
4. **Restart Claude Code** in the instance (`/exit`, then `claude`) so new agents and
   commands register.
5. **Verify.** Invoke a changed command or agent (e.g. `/audit`, or a `/pm-loop` dry
   run) and confirm it registers (no `skills:` prefix) **and** that model routing
   resolves as configured — the deepest `plan-architect` critique routes to the `apex`
   tier (Fable), workers to their lower tiers. If a command reports "Unknown command",
   re-check step 2 and the restart.
