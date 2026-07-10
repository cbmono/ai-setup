# Design: `oncall-guide` diagnostic role for the ai-bridge

**Date:** 2026-07-10
**Status:** approved (pending spec review)
**Repos affected:** `ai-setup` and `alteos/claude-code-setup` (parity — both carry the `ai-bridge/` subtree)

## Problem

When working inside a bridge instance, the user frequently asks the main session
to diagnose a failing build, a red GitHub Actions run, or a failed deployment.
Diagnosis is long-running and read-only, but it currently runs **on the main
thread**, blocking any other interaction until it finishes.

The bridge already has the mechanism to fix this — `/fanout` dispatches ad-hoc
work to **background** agents so the main session stays free as a coordinator —
but there is (a) no diagnostic role for the bridge to dispatch, and (b) nothing
that auto-routes a "why is X failing" ask to the background instead of handling
it in-thread.

## Goal

Give the bridge a **read-only diagnostic role** (`oncall-guide`) that is
dispatched as a **background agent**, so diagnosis never blocks the main thread.
Auto-trigger it on failure phrasings — including when the user pastes a PR
number or URL.

## Non-goals (explicitly out of scope)

- No `/pm-loop` hook. Diagnosis is read-only and ad-hoc; `/pm-loop` is for
  tracked `projects/` work that produces PRs.
- No new `/diagnose` command. `/fanout` + the auto-trigger cover both the batch
  and single-ask cases.
- No `aws` CLI wiring. AWS failures are diagnosed **as they surface in CI/deploy
  logs**, keeping the agent portable (no cloud-cred dependency).
- The agent does **not** write or commit anything (see "Read-only" below).

## Design

### Component 1 — New agent `ai-bridge/symlink/.claude/agents/oncall-guide.md`

A bridge-tailored, **strictly read-only** diagnostician. It lives in `symlink/`
so it is symlinked live into every instance (self-contained; no dependency on
ai-setup being installed on the host machine, and it stays in sync automatically).

**Frontmatter:**
- `name: oncall-guide`
- `description:` — action-shaped dispatch trigger: diagnoses CI/build/deploy
  failures across the group's repos, read-only, reports back with a ranked next
  steps + an optional Finding draft; dispatched ad-hoc / **not a task assignee**;
  never modifies files.
- `model: sonnet`
- `tools: Read, Glob, Grep, Bash` — **no `Write`/`Edit`**, so it is provably
  side-effect-free and safe to fire as a background agent.

**Body:**
- References the **read-only subset** of the shared "Conventions for role agents
  working in target repos" in the instance `CLAUDE.md`: read
  `instance.config.json` for `reposRoot`, resolve `target_repo` under it, detect
  the default branch, honor no-PII / never-echo-secrets. Explicitly states it
  **does not** branch, create worktrees, open PRs, or change code — unlike
  `devops-engineer`.
- Invokes `superpowers:systematic-debugging` (root cause before fixes; it won't
  auto-load as a subagent, so it invokes it itself).
- **Two input modes:**
  1. **PR reference** (a pasted PR number or URL) — first-class entry point.
     Resolve the failing checks before diagnosing:
     `gh pr checks <ref>` / `gh pr view <ref> --json statusCheckRollup,headRefName`
     → identify the failed check(s) → `gh run view <run-id> --log-failed`
     (or `--log` for full output). Map the PR to its repo under `reposRoot`.
  2. **Branch-local / free-form** — the failure is described without a PR.
     `gh run list --branch "$(git branch --show-current)" --status failure
     --limit 3` → `gh run view <run-id> --log-failed`, alongside any locally
     captured output.
- **Diagnosis steps** (adapted from the generic `.claude/agents/oncall-guide.md`):
  1. Gather context — failing logs, error messages, stack traces, offending
     files. Shallow CI clones may lack history (`fetch-depth: 1`): check
     `git rev-parse HEAD~3` and step down to `HEAD~2`/`HEAD~1`; never fall back
     to `HEAD`. Note when only 1–2 commits were available.
  2. Check recent changes — `git log --oneline -10`, `git diff HEAD~3 -- <paths>`;
     correlate the failure location with what changed.
  3. Classify — one of: **regression** (name the suspect commit), **flake**,
     **environment**, **test data**, **configuration**. For AWS/deploy failures,
     read what the pipeline logs show (permissions, missing resource, region,
     timeout) — do not attempt direct AWS calls.
  4. Next steps — concrete, ranked action plan with exact local repro commands.
- **Finding draft (read-only):** when the root cause is durable and reusable,
  the agent **includes a `Finding` draft in its returned report** (formatted per
  `SCHEMA.md`, ready to paste into `knowledge/findings/`). It does **not** write
  or commit it — persistence stays a curated step owned by the human / PM /
  cataloguer. This keeps every dispatch clean and commit-free.
- **Return value:** a tight structured report — resolved PR/run links, root
  cause, classification, ranked next steps with repro commands, and (optional)
  the Finding draft.

### Component 2 — Roster `ai-bridge/symlink/agents/index.md`

Add `oncall-guide` to the Roles list as a **non-assignee diagnostic helper**
(same treatment as `cataloguer` / `project-manager`, marked "Not a task
assignee"). Add a routing note distinguishing it from `devops-engineer`:

> Diagnosing a red CI / build / deploy **without changing code** →
> `oncall-guide` (read-only, reports back). **Fixing** it → `devops-engineer`
> (branches + opens a PR).

### Component 3 — `/fanout` `ai-bridge/symlink/.claude/commands/fanout.md`

In step 4 ("use a more specific agent type when one fits"), add `oncall-guide`
to the examples alongside `deep-bug-scan`, `cataloguer`, `Explore`, so batched
diagnostic asks route to it.

### Component 4 — Auto-trigger `ai-bridge/seed/CLAUDE.md`

Extend the "Ad-hoc requests vs. the project loop" section so that **even a
single** failure-diagnosis ask dispatches a **background `oncall-guide`** instead
of diagnosing in-thread (diagnosis is long-running + read-only — the archetypal
thing that should not block the main thread).

Trigger phrasings (non-exhaustive) — any of these, **including when accompanied
by a pasted PR number or PR URL**:
- "why is the build/CI/action failing", "build failed", "CI failed",
  "the action failed / is red"
- "the PR is red", "PR isn't green", "checks are failing" (+ a PR ref)
- "deployment failed", "the deploy is broken"
- a pasted PR number/URL with any "red / failing / not green / broken" note

The main session hands the agent a complete standalone brief (the PR ref or the
failure description, the repo, "report back root cause + ranked next steps + a
Finding draft if durable"), dispatches it with `run_in_background: true`, tells
the user it was dispatched, and reports the result when it lands — without
blocking. Keep the existing "when NOT to fan out" carve-outs (interactive
decision needed, trivial lookup).

**Propagation note:** `seed/CLAUDE.md` is **copied once** into an instance, so
this edit only reaches **new** instances. Existing instances keep their own
`CLAUDE.md` copy and need the trigger snippet pasted in manually. The exact
snippet to paste will be included in the implementation plan / PR description so
it can be dropped into live instances. (Components 1–3 live in `symlink/` and
propagate to existing instances automatically.)

### Component 5 — Docs sync

- `ai-bridge/README.md` — add `oncall-guide` to the `symlink/.claude/agents/*`
  machinery inventory line.
- `ai-setup/CLAUDE.md` — add `oncall-guide` to the `ai-bridge/` bullet's list of
  symlinked role agents.
- Confirm the three-places inventory rule from the root `CLAUDE.md` (agent
  `description:`, `.claude/README.md`, root `README.md`) — the bridge agents are
  not listed in the top-level ai-setup READMEs (they're bridge-internal), so no
  change needed there; verify during implementation.

### Component 6 — Parity mirror (`alteos/claude-code-setup`)

`alteos/claude-code-setup` carries the same `ai-bridge/` subtree and its own
`.claude/agents/oncall-guide.md`. Per the ai-setup ↔ claude-code-setup parity
convention, all of the above (Components 1–5) must be mirrored there. Per the
convention, **confirm with the user before landing in only one repo.**

## Verification

Config-only (markdown + JSON), no build/test suite. Per the repo's verification
loop:
1. `/exit` and relaunch `claude` inside a bridge instance so `.claude/agents/`
   re-scans and `oncall-guide` registers (no `skills:` prefix).
2. Paste a PR URL of a red PR with "this is red" and confirm the session
   dispatches a **background** `oncall-guide` (main thread stays free) and later
   reports root cause + ranked next steps.
3. Confirm the agent never writes/commits (no `knowledge/findings/` change, no
   git mutation) — only a Finding **draft** in its report.
4. Confirm `/fanout` offers `oncall-guide` for a batched diagnostic ask.

## Open questions

None outstanding. (Read-only + Finding-draft chosen over auto-write; fanout +
auto-trigger chosen over pm-loop hook; AWS via CI logs, no `aws` CLI.)
