Find and remove duplicated logic, dead code, and low-value abstractions in the current repo. Run this at the end of a session to keep tech debt from accumulating.

## Steps

1. **Load the backlog.** Read `.claude/techdebt.md` if it exists — that's the curated list of known tech debt the user previously chose to defer. Use it to skip re-reporting items already on the backlog.
2. **Scan** in parallel. Spawn subagents (or run Grep/Glob in parallel) across the main source tree, excluding `node_modules`, build output, generated code, and vendored deps. If `$ARGUMENTS` names a folder, scope the scan there.
3. **Look for:**
   - Near-duplicate functions (same body, different names)
   - Copy-pasted blocks of 6+ lines across files
   - Dead exports: exported symbols with zero imports
   - Wrapper functions that only forward to one other function
   - Utility files reimplementing something already in `lodash` / `remeda` / node built-ins already present in `package.json`
   - Commented-out blocks older than a week (`git blame` to confirm)
4. **Report** findings as a ranked list (highest confidence first), each with file paths, line numbers, and the suggested action. Mark items already in the backlog so the user sees them in context.
5. **Ask** per finding: fix now, defer, or reject.
6. **Apply** approved fixes directly. Keep edits surgical — match surrounding style, preserve public API shapes, don't introduce new dependencies. If a fix would change behaviour (not just structure), flag it and skip.
7. **Update the backlog** at `.claude/techdebt.md`:
   - Append newly deferred findings.
   - Remove items that were fixed or rejected this session.
   - Dedupe: if a new finding matches an existing entry (same file + rough location + same category), keep the existing one, don't add a duplicate.
   - One line per item: `- <category> — <file>:<line> — <one-line description>`. No prose.
   - Create the file if it doesn't exist. Single top heading, nothing else — it's a rolling backlog, not a report.

The backlog holds accepted tech debt only. Don't log resolved items; don't let it grow indefinitely.

For cleaning up only the **most recent diff** (not a whole-repo scan), use the built-in `/simplify` skill instead — it's scoped to changed files.
