Deep-scan a folder for real bugs using the `deep-bug-scan` agent.

## Usage

- `/scan` — scan the current working directory
- `/scan <folder>` — scan a specific folder

## What it does

1. Dispatch the `deep-bug-scan` agent against `$ARGUMENTS` (or `.` if empty). For large trees, tell it to spawn subagents per top-level subfolder and run them in parallel.
2. The agent appends findings to `.claude/potential-bugs.md` (deduped against existing entries).
3. Print a short digest: count by severity (BLOCKER / WARNING / INFO) and the top 5 findings.

After the scan, offer: "Want me to fix the BLOCKERs first?" Do not auto-fix without approval.
