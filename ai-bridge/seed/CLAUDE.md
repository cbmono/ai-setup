# Control panel — instance instructions

This repository is an **OKF Knowledge Bundle** acting as a **control panel**. It
contains no product code. Work is executed against the product repositories
configured in `instance.config.json`.

## Start here
You steer; background agents do the work. A few commands run everything:

| To… | Run |
|---|---|
| See state & advance work (refine drafts, dispatch `ready` tasks, reflect merges) | **`/pm-loop`** — one safe, idempotent tick. Add `10m` to loop on an interval; say "DRY RUN" to preview without spawning agents. |
| Start a new project | **`/new-project <description>`** — a build project (code → PRs), or add `kind=research` for docs/decks/assets (no repo). |
| Request grouped PR reviews | **`/pr-review-request <filter>`** |
| Jot / list / close a quick reminder | **`/todo <text>`** · `/todo` to list · `/todo done <text>` (lightweight notes in `todos.md`, separate from formal `projects/` work) |
| Fan a batch of independent ad-hoc asks out to parallel background agents | **`/fanout`** — or just give the assistant ≥2 independent asks at once and it acts as coordinator: dispatch each, report results as they land (see _Ad-hoc requests vs. the project loop_) |

Your two gates: promote a task `draft → ready`, then merge the PR (build) or
approve the deliverable (research). **New here?** Run `/pm-loop` as a DRY RUN to
see what exists and what awaits you, or open [`index.md`](index.md) for the map.
When a request matches one of these, **invoke the command** — don't improvise its steps.

**At the start of a session, surface any open todos** from `todos.md` (a
`SessionStart` hook injects them) so they're not forgotten — then carry on.

> Loaded only when you launch Claude inside this instance (its `.claude/agents`
> and `/pm-loop` load here). Group-wide *coding* rules belong one level up, in
> `../CLAUDE.md`, which cascades into every repo in the group — keep those out of
> this file so product-repo sessions aren't told they are a control panel.

## Where things are
- Target repos are cloned locally under `reposRoot` (see `instance.config.json`)
  and pushed to `github.com/<org>/<repo>` (`org` from the same file). Default
  branches vary (`main`/`master`/`next`) — always detect the default branch.
- This bundle's structure and the task lifecycle are defined in `SCHEMA.md`.
- The agent roster and routing rules are in `agents/index.md`.

## How work flows
- Tasks are created `draft`. The `project-manager` runs as an **idempotent loop**:
  it refines drafts (fills `acceptance_criteria`; records `open_questions` when
  blocked on a human answer), dispatches human-approved `ready` tasks to role
  agents, monitors their PRs, and reflects merges as `done`.
- **Two human authorities** (see `SCHEMA.md`): only the human promotes
  `draft → ready`, and only the human merges PRs. The PM must **never** set
  `ready` and **never** merges.
- Role agents (`software-engineer`, `devops-engineer`, `qa-reviewer`) implement
  tasks in the target repos and open PRs — never merging.
- Run the PM loop with `/pm-loop` from a session **in this repo** (so the role
  agents load and the clones + `gh` are available).
- **One active `/pm-loop` per instance at a time.** The loop's "one tick at a time"
  guarantee is per-session and there is no cross-session lock — a second session
  looping this same instance would double-dispatch tasks, corrupt in-flight
  worktrees, and race pushes to `main`. Before starting a loop, make sure no other
  session is already running one here.

## Ad-hoc requests vs. the project loop
Two different modes — don't conflate them:
- **Tracked work** (anything that becomes a PR or a `projects/` deliverable) flows
  through the gated loop above: `/new-project` → you promote `draft → ready` →
  `/pm-loop` dispatches role agents → you merge/approve. Heavyweight on purpose.
- **Ad-hoc chat requests** (rephrase a doc, rename a folder, "status of X",
  "challenge this approach") are **not** project tasks and must **not** be funnelled
  through `/pm-loop` — that's slower, not faster.

**Default for ad-hoc batches:** when the user sends **≥2 independent,
well-specified asks** in a turn, the main session acts as a **coordinator** —
dispatch each to a **background `general-purpose` agent** (`run_in_background`) in a
single message so they run in parallel, then report each result as it lands instead
of working them serially. `/fanout` forces this explicitly.

**When NOT to fan out (handle in-thread instead):**
- the ask needs an **interactive decision** (a subagent can't ask the user) —
  settle it in-thread first, then dispatch the *execution*;
- it's a **trivial lookup** where an agent round-trip costs more than reading the
  file yourself;
- two asks would **write the same files** — serialise them, or give each its own
  worktree, so they don't clobber.

Subagents run **without this conversation's context** and return only their final
message, so brief each one completely; they inherit this bundle's rules (no PII,
metric units, BI-routing) from this `CLAUDE.md`.

## Git workflow (this repo)
- **This control-panel repo commits directly to `main` and pushes — no feature
  branches, no PRs.** It is operational state, co-edited with the user and by the
  PM loop; PRs would defeat the autonomous loop. This is a deliberate exception
  to any global "never commit to main" rule.
- That global rule **still applies to the target product repos** under `reposRoot`
  — role agents always branch and open PRs there.
- **Per-agent authorship (this repo only):** an agent committing here must do so
  under its own author identity for provenance. Stage changes, then commit via
  `scripts/commit-as.sh <role> "<message>"` (roles: `project-manager`,
  `software-engineer`, `devops-engineer`, `qa-reviewer`, `cataloguer`; `human` for
  direct edits). It sets the author **name** to the role while keeping the shared
  `authorEmail` from `instance.config.json`, so the host still links to the human's
  account but `git log`/`git shortlog -sn` separate work per agent. **Never** use
  this in the target product repos — many forbid AI attribution.

## Conventions for role agents working in target repos
**This is the single source of truth for shared role-agent behaviour.** The
symlinked role agents (`software-engineer`, `devops-engineer`, `qa-reviewer`)
reference this section instead of restating it — **keep them in sync**: change a
rule here, not in each agent.

- Read `instance.config.json` for `reposRoot` (where target repos are cloned).
  Honor this `CLAUDE.md` for data-handling, units, and commit-attribution.
- **Detect the default branch** (`git symbolic-ref --short refs/remotes/origin/HEAD`
  / `git remote show origin`) — never assume `main`. Never work on it.
- Create a feature branch (or a git worktree under `<reposRoot>/_wt/`) per task.
- Conventional commits; **no AI attribution / `Co-Authored-By` lines.** Push to
  `origin` early (don't wait until the end) so an interrupted worktree loses nothing.
- PR title format: `<type>: <subject> [<task-id>]` (OKF task id, e.g.
  `[ci-hardening/task-001]`). Target the default branch. **Never merge.**
- Run the repo's build, lint, and tests green before opening a PR. If you can't
  get them green, report rather than open the PR.
- Write the PR URL and a `# Result` summary back into the task document, and set
  the task `status: in-review` (or `blocked`, with why, if you can't proceed).
- **No customer PII** in code, commits, or PR text; **never echo, print, or log
  secrets or environment variables** (rely on existing env / `.npmrc` for auth).
- **Capture knowledge:** if you discover something durable and reusable, write or
  update a `Finding` in `knowledge/findings/` (per `SCHEMA.md`) and link it from
  the task, so the next agent doesn't re-derive it.
- **Parallel-safety:** if the product repos share one clone / one package store,
  each agent uses its own worktree under `<reposRoot>/_wt/` and a **private package
  store** (e.g. `pnpm install --store-dir <worktree>/.pnpm-store`), and pushes
  early. Create the worktree explicitly with `git worktree add <path> -b <branch>
  origin/<default-branch>` — don't rely on the `EnterWorktree` tool, which may be
  unavailable to you as a subagent. (`settings.json` sets `worktree.bgIsolation:
  none` so the control panel manages worktrees itself; harness isolation would
  only isolate this repo, not the product repos.)

## Knowledge base
- `knowledge/` is an OKF knowledge base in this bundle — a `Service` catalog,
  `Finding`s (decisions/learnings), `Runbook`s, and `Team`s (see `SCHEMA.md`).
- The `cataloguer` agent builds/refreshes it (read-only on product repos); task
  agents **capture `Finding`s as a byproduct** of their work and link them from
  the task.
- **Use it index-first, to avoid re-deriving what's already known.** Before
  researching or implementing, scan `knowledge/index.md` (a compact one-line-per-
  entry catalog) for the service/area you're touching, then open only the 1–3
  specific `Finding`s / `Service` / `Runbook` docs that match — **never bulk-read
  `knowledge/`**. If a relevant `Finding` already answers a question, cite it and
  move on. The KB is **pull-based** (read on demand); it is deliberately *not*
  auto-loaded into context, so it never bloats a session.

## Data handling
- This is a control panel for engineering work. **Do not put customer PII** into
  task documents, logs, or PR descriptions.
- Set your default units and route authoritative data questions to the owning
  team in `knowledge/teams/` (customize this line for your group).

## Session defaults
@~/.claude/claude-defaults.md

<!-- Pulls in the shared ai-setup behavioral defaults (planning, parallelism,
verification) so a bridge session has them even if this group has no umbrella
CLAUDE.md. Requires ai-setup's installer to have linked them into ~/.claude. If
this group's ../CLAUDE.md already imports the same file, this is a harmless
duplicate — drop one. -->

