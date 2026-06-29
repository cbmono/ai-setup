---
description: Fan a batch of independent ad-hoc requests out to parallel background agents — the main session coordinates and reports results as they land
argument-hint: "<task; task; task>  |  (empty) = fan out the independent asks already in this turn"
allowed-tools: Agent, Read, Glob, Grep, Bash(ls:*)
---

Dispatch independent **ad-hoc** requests to **parallel background agents** so the
main session stays free as a coordinator, instead of working them one at a time.

> **Generic template file** (symlinked from the `ai-bridge` template). This is for
> **ad-hoc chat requests** (rephrase a doc, rename a folder, research a question) —
> **not** tracked `projects/` work. Anything that becomes a PR or a `projects/`
> deliverable goes through `/new-project` → promote `ready` → `/pm-loop`, never here.

## Input
`$ARGUMENTS` is an optional `;`-separated list of tasks. If empty, fan out the set
of independent asks the user has already given in this turn.

## Steps
1. **Split into units.** Identify the genuinely independent asks. If one depends on
   another's output, say so and sequence those — only fan out what's truly parallel.
2. **Filter — keep in-thread anything that shouldn't dispatch:**
   - needs an **interactive decision** (a subagent can't ask the user) → settle it
     with the user first, then dispatch the *execution*;
   - **trivial lookup** → just answer it (an agent round-trip is slower);
   - **writes the same files** as another unit → serialise them, or give each its
     own worktree (`isolation: worktree`), so they don't clobber.
3. **Brief each agent fully.** Subagents have **none** of this conversation's
   context — write each a complete, standalone prompt (goal, exact files/paths,
   acceptance, "report back X"). They inherit this bundle's rules (no PII, metric
   units, BI-routing) from `CLAUDE.md`.
4. **Dispatch in one message.** Spawn all units as **`general-purpose` agents with
   `run_in_background: true`** in a single turn so they run concurrently. Use a more
   specific agent type when one fits (e.g. `deep-bug-scan`, `cataloguer`, `Explore`).
5. **Coordinate.** Tell the user what was dispatched — and what you kept in-thread
   and why. As each agent finishes, **report its result**; don't block the session
   waiting on all of them.

## Notes
- This command **dispatches, it doesn't gate** — no `draft → ready` promotion, no
  merge. Those gates exist only for tracked `projects/` work.
- Cap concurrency to a sensible handful; if there are many units, batch them.
- No customer PII in any agent prompt.
