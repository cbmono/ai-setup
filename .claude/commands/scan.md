Deep-scan a folder for real bugs using the `deep-bug-scan` agent.

## Usage

- `/scan` — scan the current working directory
- `/scan <folder>` — scan a specific folder

## What it does

1. Dispatch the `deep-bug-scan` agent against `$ARGUMENTS` (or `.` if empty). For large trees, tell it to spawn subagents per top-level subfolder and run them in parallel.
2. The agent revalidates existing entries in `.claude/potential-bugs.md` (removes ones already fixed) and appends new findings, deduped by file + bug pattern. The agent must list every removed entry in its final message with a one-line justification.
3. Print a short digest: count by severity (BLOCKER / WARNING / INFO), the top 5 findings, and any pruned entries surfaced by the agent.

After the scan, offer: "Want me to fix the BLOCKERs first?" Do not auto-fix without approval. When the user accepts a fix, remove the corresponding entry from `.claude/potential-bugs.md` after the fix lands so the file stays a current-state report, not a historical log.
