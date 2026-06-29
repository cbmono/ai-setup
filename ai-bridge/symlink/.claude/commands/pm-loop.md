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
   standing guardrails below.
2. **Wait for it to finish.** Do **not** start another tick while one is in
   flight. The agent's completion arrives as a `<task-notification>`.
3. **On completion**, schedule the next tick after the gap: call `ScheduleWakeup`
   with `delaySeconds` = the gap, and `prompt` = `/pm-loop <gap>` so this skill
   re-enters and dispatches the next tick. (If gap is `0m`, dispatch the next
   tick immediately instead of scheduling.)
4. **When `/pm-loop` re-fires from that wakeup:** if a tick is somehow still in
   flight, just reschedule the gap and skip (never overlap); otherwise dispatch
   the next tick (step 1) and repeat.
5. **Stop** when the user says so (e.g. "stop the PM loop"): dispatch no further
   ticks and cancel any pending wakeup. There is no cron to delete.

This guarantees **at most one PM tick at any moment**, with a `gap` pause between
ticks, regardless of how long a tick runs.

## Standing guardrails for each tick dispatch

- Honor both human gates: **never** promote `draft → ready`, **never** merge PRs.
- Reconcile doc `status:` against live `gh`/`git` before acting; act only on deltas.
- Concurrency cap: **≤3 role agents in flight**, and each must use its own
  worktree under `<reposRoot>/_wt/` + a **private package store** (e.g.
  `pnpm install --store-dir <worktree>/.pnpm-store`) and **push early** — never two
  installs against the shared store at once (see `.claude/agents/project-manager.md`).
- Commit hygiene in this repo: stage only your own changed files by explicit path
  (never `git add -A`); commit via `scripts/commit-as.sh project-manager "<msg>"`;
  never `--no-verify` in target repos.
- Return a tight summary: live-vs-docs deltas, dispatched/reflected, in-flight
  count, and what awaits the human (approvals / answers / merges).

## Notes
- One serial loop per session — and **one active loop per instance** (see "Why
  serial"): don't start a second session looping the same instance. To change the
  gap: stop, then `/pm-loop <gap>`.
- A tick with nothing to do is a fast no-op — the gap keeps idle cycles cheap.
