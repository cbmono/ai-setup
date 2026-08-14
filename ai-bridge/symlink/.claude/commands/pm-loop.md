---
description: Start the Project Manager loop as a SERIAL, completion-driven loop (one tick at a time) in this control-panel instance repo
argument-hint: "[gap]  pause between ticks, default 10m  (e.g. 0m for back-to-back, 30m)"
allowed-tools: Bash(pwd), Bash(ls:*), Agent, ScheduleWakeup, CronList, CronDelete
---

Start the **Project Manager loop** — but as a **SERIAL, completion-driven** loop:
**exactly one tick runs at a time.**

## Why serial (do not revert to a fixed interval)

A LIVE tick can take a long time because it dispatches real role agents that
build/test/push, and those agents may share **one clone + one package store**. A
fixed-interval loop shorter than a tick (e.g. a naive `/loop 15m`) makes ticks
**overlap** → concurrent PMs double-dispatch the same task (two PRs for one slice)
and a sibling's package install corrupts an in-flight worktree. So this loop is
gated on **completion**, never on a clock.

**This guarantee is per-session only — there is no cross-session lock.** The
"one tick at a time" serialization lives in *this* session's wakeup chain; a
second Claude session running `/pm-loop` against the **same instance** reintroduces
exactly the overlap bug (double-dispatch, shared-store corruption, racing pushes
to the control panel's `main`). **Run at most one active `/pm-loop` per instance
at a time** — that's a human responsibility, not something the loop can enforce.
Before starting, make sure no other session is already looping this instance.

**Diagnosing it: suspect your own second tick first.** Interleaved writers on one
control panel read like another session in the bundle, and usually aren't — a tick
dispatched after misreading step 2's signal produces the same symptoms from inside
one session. Two things that look like evidence and are not: **author names**
(`commit-as.sh` sets the role per commit, so one process batching commits leaves
three roles at the same second), and a **tick's own account of a collision it is
part of** — check `git reflog show main`, which is per-clone and therefore answers
whether `main` actually moved backwards, before reporting corruption.

## Preconditions

1. Must run from a **control-panel instance root**, so the `.claude/agents` role
   agents, the target-repo clones, and `gh` load. **Detect** the instance root by
   confirming `SCHEMA.md` + `.claude/agents` + `instance.config.json` exist in the cwd; if
   not, tell the user to `cd` into the instance and stop. (Do not hardcode a path —
   instances live under different group folders.)
2. Read `instance.config.json` for `reposRoot` (where target repos are cloned) and
   `org` (the GitHub org for `target_repo` values).
3. **Kill any fixed-interval PM cron** from an older approach: `CronList`, and if a
   job's prompt is `run the project-manager agent for one LIVE tick`, `CronDelete`
   it — that job is the overlap bug. Do **not** create a cron here.

## How the serial loop works

Parse `$ARGUMENTS` as the inter-tick **gap** (default **10m**). Then:

1. **Run one tick now.** Spawn the `project-manager` agent
   (`subagent_type: project-manager`) for ONE LIVE tick (background), with the
   standing guardrails below. **Run the tick on the orchestrator's configured model:**
   resolve `project-manager` in `roleTiers` (default `deep`) → an alias via `models`
   (default `deep` → `opus`), and pass that as the tick's model. If `models`/`roleTiers`
   are absent, inherit the session model. (The top `apex`/`fable` tier is reserved for
   the rarest, deepest reasoning — the `plan-architect` critique — not the routine tick.) A LIVE tick refines drafts, dispatches `ready` tasks,
   advances/reflects PRs, reclaims finished worktrees, proposes closing completed
   projects (all tasks terminal), and — **after reflecting merges** — may dispatch
   the `cataloguer` to refresh `knowledge/` from the merged work (throttled to one
   per tick; skipped on idle/trivial ticks).
2. **Wait for it to finish.** Do **not** start another tick while one is in
   flight. **That tick's `<task-notification>` is the only valid "finished"
   signal** — no tool listing and no amount of elapsed time substitutes for it. A
   tick that reads as complete or idle in a status listing may still be running:
   the agent resumes and the same task-id notifies again, so one that has looked
   done for *hours* is not done until its notification arrives. Don't poll for a
   verdict; a quiet repo proves nothing either (a tick holding for its own
   subagents is quiet by definition).
3. **On completion**, schedule the next tick after the gap: call `ScheduleWakeup`
   with `delaySeconds` = the gap, and `prompt` = `/pm-loop <gap>` so this skill
   re-enters and dispatches the next tick. (If gap is `0m`, dispatch the next
   tick immediately instead of scheduling.)
4. **When `/pm-loop` re-fires from that wakeup:** "still in flight" means **this
   session dispatched a tick and has not yet seen its notification** — that is the
   whole check, and it is answered from this session's own history, never by
   querying a tool. If one is still in flight, just reschedule the gap and skip
   (never overlap); otherwise dispatch the next tick (step 1) and repeat.
5. **Stop** when the user says so (e.g. "stop the PM loop"): dispatch no further
   ticks and cancel any pending wakeup. There is no cron to delete.

This guarantees **at most one PM tick at any moment**, with a `gap` pause between
ticks, regardless of how long a tick runs.

## Standing guardrails for each tick dispatch

- Honor the human gates **per the owning project's `autonomy`** (default `gated`): never
  promote `draft → ready` and never merge. A project may delegate a gate **only** where
  `AUTONOMY.md` exists at the bundle root and defines the mode — then follow that file
  exactly, including its preflight. **No `AUTONOMY.md` ⇒ every project is `gated`** and
  the field is inert. See the PM agent's "Authority boundaries". When `autonomy` is unset,
  act as `gated`.
- Reconcile doc `status:` against live `gh`/`git` before acting; act only on deltas.
- Concurrency cap: **at most `maxAgentsInFlight` role agents in flight** (from
  `instance.config.json`; fall back to 5 if the key is absent), and each must use its own
  worktree under `<reposRoot>/_wt/` + a **private package store** (e.g.
  `pnpm install --store-dir <worktree>/.pnpm-store`) and **push early** — never two
  installs against the shared store at once (see `.claude/agents/project-manager.md`).
- A LIVE tick may also dispatch the **`cataloguer`** to refresh the KB after
  reflecting merges — read-only on product repos, writes only to `knowledge/`. It
  **counts toward the `maxAgentsInFlight` cap**, is **throttled to one per tick**, and (like every
  tick action) **never promotes or merges**. Skipped on idle/docs-only/trivial ticks.
- Commit hygiene in this repo: stage only your own changed files by explicit path
  (never `git add -A`); commit via
  `scripts/commit-as.sh project-manager "<msg>" -- <path>...` — naming the paths is
  required for agent roles, so a sibling agent's staged files can't land under yours;
  never `--no-verify` in target repos.
- **Worktree hygiene.** Reclaim finished worktrees with `scripts/prune-worktrees.sh`
  (≤ once per tick) — it removes only worktrees whose PR is merged/closed (or whose
  branch is merged into the default branch) **and** whose tree is clean, and reports
  (never deletes) dirty ones. `_wt` must not grow unbounded. **Prune only when your
  in-flight count is zero.** An open PR is kept, but a worktree whose PR has just
  merged or closed with a clean tree is removed — and no check the script makes can
  see an agent working inside it, so pruning with agents live can delete the tree
  out from under one.
- **Project close is human-gated.** The PM only *proposes* closing a project (all
  tasks terminal) via the 🔴 board; the human confirms (or runs `/close-project`).
  Closeout removes the folder (`git rm -r`) — git history + KB are the record, there
  is no archive. Never close autonomously.
- Return a tight summary: live-vs-docs deltas, dispatched/reflected, in-flight
  count, and what awaits the human (approvals / answers / merges).

## Notes
- One serial loop per session — and **one active loop per instance** (see "Why
  serial"): don't start a second session looping the same instance. To change the
  gap: stop, then `/pm-loop <gap>`.
- A tick with nothing to do is a fast no-op — the gap keeps idle cycles cheap.
- Each tick refreshes `AWAITING.md` — the queue of what a human decision unblocks —
  **only when that file already exists**; a `SessionStart` hook surfaces its
  "🔴 Awaiting you" items at startup. Deleting the file turns the queue off for
  good (the loop never recreates it); `touch AWAITING.md` turns it back on.
