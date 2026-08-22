# Control Center (instance)

An [Open Knowledge Format](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
(OKF) **Knowledge Bundle** that acts as a **control panel** for a team of
background AI agents working on this group's product repositories.

This is an **instance** of the `ai-bridge` template. The generic machinery
(`SCHEMA.md`, `agents/`, `scripts/`, the role agents, the `/pm-loop`,
`/new-project`, `/close-project`, `/pr-review-request`, `/answer`, `/audit` and
`/fanout` commands, and the
`SessionStart` hook) is **symlinked in** from the template and gitignored; this
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
- `worktreeRoot` — where agent build worktrees live. Keep it **outside** any synced
  folder (Dropbox/iCloud rewrite files inside a worktree mid-run). Absent this key,
  worktrees fall back to `<reposRoot>/_wt`, which is also still swept as the legacy root.
- `authorEmail` — commit email for per-agent authorship. Used when `people` (below)
  has no entry for this clone.
- `people` — optional; a map of **GitHub login → commit email** for everyone who works
  this bundle: `{ "<login>": "<email>", … }`. Recorded once, by whoever knows the
  addresses. `scripts/commit-as.sh` looks up this clone's login, so each clone authors
  its commits as the human running it. **The address is per-instance, not per-person**:
  the same login belongs to a different address in each group's bundle, because the
  address says which entity the work belongs to — which is why this map lives here and
  not anywhere shared, why it is never derived from the login, and why it never moves
  into `instance.config.local.json` (that file says which login this clone *is*). The
  template ships **placeholder logins verified unclaimed on github.com** and addresses
  at `example.com` — replace them here, in your own instance, and verify any new example
  login the same way.
- `defaultOwner` — optional; the GitHub login that owns work no `owner:` names. **Set
  it on any bundle shared by more than one human**: without it an unowned task resolves
  to "mine" on every clone and two loops dispatch it. Tracked on purpose, and **not**
  locally overridable — both clones must agree. Absent, every task is every clone's,
  which is right for a single-human instance and is the old behaviour exactly.

Per-machine values go in **`instance.config.local.json`** beside this file
(gitignored, read first, entirely optional): `ownerGithubUser` (which login this clone
is — the one key a second person needs), `authorEmail`, `reposRoot`, `worktreeRoot`,
`boardInstances`. The full set, and what each means when absent, is listed in one place:
`SCHEMA.md` → "Per-machine config overrides".
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
the background. **Steer, don't watch** — act on what `AWAITING.md` asks of you, not
on each agent's steps.

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
When a project's tasks are all `done`/`cancelled`, the PM flags it in the awaiting-you queue as
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
under `worktreeRoot` (absent that key, `<reposRoot>/_wt`) are **never reclaimed
automatically** — `scripts/prune-worktrees.sh` (each PM tick that has zero agents
in flight, and on demand)
classifies them and prints the `git worktree remove` commands for you to run. The
removal path was deleted after it destroyed three running agents' worktrees, so
draining that root is a periodic human job.

## See the group's repos from in here
`repos/<name>` is a symlink to each clone under `reposRoot`, so `cd repos/<name>`
works without the repos ever being nested inside this instance. Run
`scripts/link-repos.sh` after cloning a new one (the installer does it too). It's
gitignored and safe to delete.

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

**Answering the PM's questions.** A blocked `draft` lists numbered
`open_questions` (`Q1:`, `Q2:`, …). Answer one in the task doc by appending
` --- <answer>` to that line — e.g. `Q1: which region should we default to? --- eu-central-1`.
The next tick treats anything after the ` --- ` as your answer, folds it into the
task, and clears the question; the `draft` becomes promotable once the list empties.
(Answering in chat during a session works too.)

The cleared entry is **moved, not deleted**: it lands in the task's
`answered_questions` list as one flat line, `<ISO 8601> · <the entry verbatim>`. That
list is a human audit record — nothing reads it — and `open_questions` still has to
empty, because that is the promotion signal. **No customer PII in an answer**: unlike a
question you clear, this list persists for the life of the repo.

## What needs you
`AWAITING.md` lists **only** what a human decision unblocks, one line per item with
its verb and a real link:

* ✅ **approve** — a refined `draft`, promote it `draft → ready`
* ❓ **answer** — a `draft` with open questions
* 🔀 **merge** — a PR in review
* ⛔ **unblock** — a blocked task
* 🏁 **close** — a project whose tasks are all terminal

In-flight and upcoming work is deliberately **not** here: it needs no decision from
you, and scrolling past it is how a queue stops getting read. Each `/pm-loop` tick
rewrites the file, and a `SessionStart` hook injects these items when you launch
Claude here — so you see what needs a decision without reading the loop.

**On by default, off by deletion.** The template's installer created this file when
it first stamped out the instance; from then on the loop refreshes it only if it
already exists and never recreates it. So `rm AWAITING.md` turns the queue off for
good — a later installer re-run won't resurrect it — and `touch AWAITING.md` turns
it back on. Derived and gitignored — never hand-edit it. With it off, ask the
assistant directly and it reads the task docs.

## Re-link the machinery
If the template moves or you add machinery, re-run the template's installer:
```
<ai-setup>/ai-bridge/install.sh <path-to-this-instance>
```
