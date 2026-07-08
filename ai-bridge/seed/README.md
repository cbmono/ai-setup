# Control Center (instance)

An [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
(OKF) **Knowledge Bundle** that acts as a **control panel** for a team of
background AI agents working on this group's product repositories.

This is an **instance** of the `ai-bridge` template. The generic machinery
(`SCHEMA.md`, `agents/`, `scripts/`, the role agents, the `/status`, `/pm-loop`,
`/new-project`, `/close-project`, `/pr-review-request`, `/todo`, and `/fanout`
commands, and the
`SessionStart` hooks) is **symlinked in** from the template and gitignored; this
repo tracks only its own **content**: `objectives/`, `projects/`, `knowledge/`,
`log.md`, and `instance.config.json`.

For a unified tree (this control panel pinned on top, the group's product repos
below):
- **VS Code / Cursor / Antigravity** — open **`<group>.code-workspace`**
  (*Open Workspace from File…*).
- **Zed** (no workspace-file support) — just open the **group folder**; the
  instance's `_`-prefix already sorts it to the top.

Either way the repos stay physical peers on disk (never nested under this
instance), so product-repo sessions never inherit this control-panel `CLAUDE.md`.

**Launching Claude is the same in every editor:** the editor folder is only for
viewing. To drive the panel, open a terminal, `cd` **into this instance dir**, and
run `claude` there — that's what loads the role agents and `/pm-loop`. Starting
Claude in the group folder instead gives you the umbrella's shared commands but
*not* the panel's agents.

## Configure
Edit `instance.config.json`:
- `org` — the GitHub org for `target_repo` values.
- `reposRoot` — where this group's product repos are cloned locally.
- `authorEmail` — shared commit email for per-agent authorship.
- `defaultRepo` — optional; default repo for `/pr-review-request` (bare name is
  qualified with `org`, or give `owner/name`).
- `prReviewSlackChannel` — optional; channel name or id for `/pr-review-request`.

Per-instance permission/env overrides go in `.claude/settings.local.json`
(gitignored) — never edit the symlinked `.claude/settings.json`, which is shared
across all instances.

## How it works
```
Objective ──► Project ──► Task ──► (PM refines) ──► (human approves) ──► (PM dispatches) ──► role agent ──► PR ──► you merge
```
The spine you drive is **`/new-project` → approve `draft → ready` → `/pm-loop` → merge**.
You set direction and approve at two gates; the PM and role agents do the rest in
the background. **Steer, don't watch** — track state with the dashboard, not by
reading each agent's steps.

See `SCHEMA.md` for the types and lifecycle, and `CLAUDE.md` for the operational
rules (two human gates, per-agent authorship, parallel-safety).

## Add a project
Run **`/new-project <one-line description>`** from a session in this instance. It
scaffolds `projects/<slug>/` (schema-valid `project.md`, `index.md`, `log.md`, and
seed `draft` tasks), links it to an objective, registers it in the bundle
index/log, and commits.

Two kinds (see `SCHEMA.md`):
- **`kind=build`** (default) — ships code to a product repo via PRs; role agents
  execute, you merge. Tokens: `repo=<name>`.
- **`kind=research`** — produces **deliverables inside the bundle** (docs, marp/pptx
  decks, assets) under `projects/<slug>/deliverables/`; no repo, no PRs. *You* work
  the tasks in-session (the PM tracks but never dispatches them); split by
  domain/team gives one task + deliverable per chunk. Tokens: `deliverables="a; b"`.
  These are the strategic entry points whose conclusions graduate into `knowledge/`
  and spawn objectives + build projects.

Other tokens: `objective=<slug>`, `--no-commit`. Everything lands `draft` — you
then promote `draft → ready`. (To hand-roll one instead, copy the shape in `SCHEMA.md`.)

## Finish a project
When a project's tasks are all `done`/`cancelled`, the PM flags it on the board as
**ready to close** — it never closes one on its own. Close it with:
```
/close-project <slug>
```
Closeout does a final `knowledge/` consolidation (durable learnings live on in the
KB), records a **Project closed** entry in `log.md` (with the merged PRs and the
removing commit), rolls the project to `status: done`, and then **removes the
project folder**. There is **no `archive/`** — git history + the KB are the record,
and a done folder left live would only cost context on every PM tick. Recover the
full trail anytime with `git log -- projects/<slug>/`. Finished build worktrees
under `<reposRoot>/_wt/` are reclaimed automatically (also each PM tick, via
`scripts/prune-worktrees.sh`).

## Run the Project Manager
From a fresh session **in this instance directory** (so the role agents, the
clones, and `gh` are available):
```
/pm-loop 10m
```
A SERIAL, completion-gated loop — exactly one tick at a time. Preview safely with
a **DRY RUN**: *"run the project-manager in DRY RUN — refine and report the
dispatch you would do, without spawning agents."*

You control the two gates: promote a task `draft → ready` to approve it, and
merge the PR when satisfied (the PM then marks the task `done`).

## Monitor progress
```
/status            # full board
/status mine       # only what's awaiting you
/status <slug>     # one project
```
`/status` renders a board of every task grouped by what it needs — **🔴 awaiting
you** (approve · answer · merge · unblock) · **🟡 in flight** · **🟢 next** ·
**⛔ blocked** — and writes it to `DASHBOARD.md`. It's **read-only** (never
dispatches, promotes, or merges), so it's safe to run anytime, even while a
`/pm-loop` is running. Each PM tick refreshes `DASHBOARD.md` too, and a
`SessionStart` hook surfaces its "awaiting you" items when you launch Claude here —
so you see what needs a decision without reading the loop. `DASHBOARD.md` is a
**derived view** (regenerated from the task docs, gitignored) — never hand-edit it.

## Quick todos
`/todo <text>` jots a reminder, `/todo` lists them, `/todo done <text>` closes one
— all in a single `todos.md`. A `SessionStart` hook surfaces open todos when
you launch Claude here. These are **lightweight notes** for you, separate from the
formal `projects/` work agents execute — promote a todo to `/new-project` once it's
real, trackable work.

## Re-link the machinery
If the template moves or you add machinery, re-run the template's installer:
```
<ai-setup>/ai-bridge/install.sh <path-to-this-instance>
```
