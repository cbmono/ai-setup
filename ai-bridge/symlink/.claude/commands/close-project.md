---
description: Close a completed project — final KB consolidation, log the closeout, roll up status, then remove the project folder (git history + KB are the record; no archive). Human-gated; run once a project's tasks are all done/cancelled.
argument-hint: <project-slug>  [--dry-run] [--force]
allowed-tools: Bash(date:*), Bash(scripts/commit-as.sh:*), Bash(scripts/prune-worktrees.sh:*), Bash(git rm:*), Bash(git add:*), Bash(git log:*), Bash(ls:*), Read, Write, Edit, Glob, Agent
---

**Close a completed Project.** This is the human-triggered form of the closeout the
PM only ever *proposes* (it never closes a project autonomously). Use it when a
project's work is finished: it consolidates any remaining knowledge into
`knowledge/`, records the closeout in the log, rolls up status, and **removes the
project folder**. The bundle's `git` history and the KB are the durable record —
there is **no `archive/`**.

> **Generic template file** (symlinked from the `ai-bridge` template). Reads the
> bundle's own `SCHEMA.md` (see "Project & objective completion") and
> `instance.config.json` — never hardcode org/repo/path literals here.

## Inputs
`$ARGUMENTS` = the project slug (the `projects/<slug>/` directory name), plus:
- `--dry-run` — report what closeout *would* do; change nothing.
- `--force` — proceed even if some tasks are **not** terminal (records which). Use
  sparingly — normally every task should be `done`/`cancelled` first.

If no slug is given, list projects whose tasks are all terminal (the close
candidates) and ask which to close.

## Steps

> **`--dry-run` short-circuits every mutation.** Do step 1 (read-only checks),
> then for steps 2–6 *report exactly what you would do* — do **not** dispatch the
> cataloguer, edit `log.md`/`index.md`/`project.md`/objective, prune worktrees, or
> commit/remove anything. Only a run without the flag actually changes state.

1. **Resolve & check.** Confirm `projects/<slug>/` exists (else stop and report).
   Read its `project.md` and every `tasks/*.md`. Unless `--force`, verify **all**
   tasks are terminal (`done` or `cancelled`); if any are still open, **stop** and
   list the non-terminal ones — the project isn't ready to close.

2. **Consolidate knowledge.** Dispatch the `cataloguer` (subagent) for a final pass:
   capture/link any remaining durable `Finding`s from this project, refresh the
   `Service`/`Runbook` docs it touched, and cross-link them. For a **research**
   project, decide with the user which `deliverables` graduate into `knowledge/` and
   have the cataloguer fold them in. Skip only if the project produced nothing
   durable (trivial/superseded) — say so.

3. **Record the closeout.** Get a timestamp (`date -u +%Y-%m-%dT%H:%M:%SZ`). Prepend
   a dated **Project closed** entry to the root `log.md` (newest-first) naming the
   project, its merged PR(s) as `[<repo>#<n>](url)`, the `Finding`(s) it produced
   (KB links), and a one-line outcome. (The removing commit SHA is added by step 6's
   commit — reference it as "removed in the closing commit".)

4. **Roll up status.** Set `project.md` `status: done`. Remove the project's bullet
   from the active `## Projects` list in `index.md`. Update its objective's
   "Projects serving this objective" list to mark it delivered; if **all** of that
   objective's projects are now terminal, **ask** whether to set the objective
   `status: achieved` (don't flip it silently).

5. **Reclaim worktrees.** Run `scripts/prune-worktrees.sh` to remove any finished
   worktrees left by this project's build tasks (safe — merged/closed + clean only).

6. **Remove & commit.** Unless `--dry-run`: `git rm -r projects/<slug>/`, stage the
   `index.md` / `log.md` / objective / KB edits by explicit path, and commit via
   `scripts/commit-as.sh human "chore: close <slug> project"`. Print the closing
   commit SHA and the `log.md` entry. Remind the user the full record stays
   recoverable via `git log -- projects/<slug>/`.

## Notes
- **No archive.** Removal is deliberate — a done project left live costs context on
  every PM tick, and `git` + the KB already hold the record. Recover with
  `git revert <sha>` or `git show <sha>:projects/<slug>/...` if ever needed.
- This repo commits straight to `main` (see `CLAUDE.md`) — the human gate here is
  *deciding to close*, not a PR.
- No customer PII in the log or any KB doc written during closeout.
