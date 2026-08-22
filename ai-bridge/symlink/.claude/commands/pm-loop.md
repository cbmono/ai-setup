---
description: Start the Project Manager loop as a SERIAL, completion-driven loop (one tick at a time) in this control-panel instance repo
argument-hint: "[gap]  pause between ticks, default 10m  (e.g. 0m for back-to-back, 30m)"
allowed-tools: Bash(pwd), Bash(ls:*), Agent, ScheduleWakeup, CronList, CronDelete
---

Start the **Project Manager loop** — but as a **SERIAL, completion-driven** loop:
**exactly one tick runs at a time.**

## Why this shape, and not `/goal` (v2 audit, 2026-08)

The looping **mechanism here is already first-party**: `ScheduleWakeup` is the same
primitive `/loop`'s dynamic mode uses. This command is a policy layer over it — the
serial guarantee, the instance-root preconditions, the in-flight check, and what a
tick may do — not a hand-rolled loop engine.

`/goal` was considered and does **not** fit. It terminates on a condition, while this
loop runs until a human stops it; its evaluator judges only what is in the transcript
and **calls no tools**, so it cannot see whether a PR merged; and it defers evaluation
while background work runs, which is the normal state of a tick that has dispatched
role agents. Wrong shape on all three counts — so the mechanism stays as it is.

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
   advances/reflects PRs, reports finished worktrees, proposes closing completed
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

   **After a compaction, that memory is gone — so trust the disk, not your
   recollection.** This loop is long-lived and its context gets summarised; the
   in-flight set is answered from session history, which is exactly what
   compaction discards. Re-derive it from the root `log.md` tick ledger — whose
   entry the PM **opens before dispatching**, precisely so a tick that dies
   mid-flight still leaves a trace, and whose open-with-no-close state is the
   only thing on disk that distinguishes "dispatched, waiting" from "never
   ran" — then the task documents' own `status:`, then `git log`, in that order, and treat all three
   as outranking anything you seem to remember. The failure this prevents is
   re-dispatching a task sequence that already finished, which costs a full set of
   agent runs and can open duplicate PRs; it is the most expensive failure observed
   in loops of this shape. If the ledger and a task's `status:` disagree, the task
   document wins and the ledger was written by a tick that died before curating.
   **An open entry does not mean its agents are alive.** Nothing on disk can show
   that — which is why the notification is the only finished signal in the first
   place. So an open entry is a reason to report and stop, never to re-dispatch or
   to silently adopt the work as your own in-flight set; a stale open entry would
   otherwise miscount the `maxAgentsInFlight` cap in both directions.
3. **On completion**, schedule the next tick after the gap: call `ScheduleWakeup`
   with `delaySeconds` = the gap, and `prompt` = `/pm-loop <gap>` so this skill
   re-enters and dispatches the next tick. (If gap is `0m`, dispatch the next
   tick immediately instead of scheduling.)
   **Always pass `noop` and `reason`.** `noop: true` when the tick changed nothing
   (no dispatch, no status change, no `AWAITING.md` edit); `noop: false` when it did.
   Consecutive `noop: true` ticks collapse into one streak line in the human's
   terminal instead of one wakeup line each — an idle loop should be nearly silent,
   and this is the whole difference between a loop you leave running and one you
   turn off because it scrolls. `reason` is one specific sentence about what this
   tick is waiting on ("holding for qa-reviewer on #214"), not "waiting".
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
- **An answered question is MOVED, never deleted.** Folding an answer in shifts that
  `open_questions` entry into the task's `answered_questions` list — one flat line,
  `<ISO 8601> · <the entry verbatim>` (see `SCHEMA.md`). `open_questions` must still
  **empty**, because that is the signal promotion keys on; an entry left in both lists
  blocks the draft forever. `answered_questions` is a human audit record — nothing reads
  it — and it carries **no customer PII**, since it persists for the life of the repo.
- Concurrency cap: **at most `maxAgentsInFlight` role agents in flight** (from
  `instance.config.json`; fall back to 5 if the key is absent), and each must use its own
  worktree under the instance's `worktreeRoot` (from `instance.config.json`, never
  inside the synced `reposRoot`; if the key is absent, `<reposRoot>/_wt`)
  + a **private package store** (e.g.
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
- **Worktree hygiene.** `scripts/prune-worktrees.sh` (≤ once per tick) **reports
  only — it never deletes anything.** It scans `worktreeRoot` plus the legacy
  `<reposRoot>/_wt` and classifies each worktree, printing `git worktree remove`
  commands for a human. Surface its `REMOVABLE` and `RECLAIMABLE` sets on the board
  rather than acting on them yourself. **Run it only when your in-flight count is
  zero** — a report that races a live dispatch misclassifies it.
  The script's `PRUNE_ACTIVE_MINUTES` mtime veto (default 120) is a backstop, not a
  substitute: an agent that writes nothing for longer than the window looks idle, so
  your in-flight count stays the primary guard.
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
- Each tick also refreshes `SNAPSHOT.json` (via `scripts/write-snapshot.sh --quiet`,
  at the end of the tick) — the derived, gitignored feed for the cross-instance board
  that `scripts/build-board.sh` renders. Same rule and same off switch: the writer
  rewrites the file **only when it already exists** and never creates it, so
  `rm SNAPSHOT.json` takes this instance off the board for good and
  `touch SNAPSHOT.json` puts it back. Which instances a board shows comes from
  `boardInstances` in `instance.config.json`; **if that key is absent or empty, the
  board is just this instance.**
