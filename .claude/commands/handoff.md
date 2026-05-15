Write the current session's state to a handoff file so a fresh session can resume the task without context loss. Use this proactively when context is filling up, not at the breaking point.

## Steps

1. Derive a slug the same way `/plan` does:
   - Grep the current branch name and last 5 commit subjects for `\b[A-Z]{2,}-\d+\b`. If a Jira-style key matches (e.g. `AUTH-1234`), slug = that key.
   - Otherwise, build a 3–5 kebab-case word summary of `$ARGUMENTS` or the active task, verb-prefixed when one fits — `feat-rotate-oauth-keys`, `fix-auth-race`, `chore-bump-deps`. If no prefix fits, drop it.
   - If nothing fits, ask the user for a slug before continuing.
2. Write `.claude/handoffs/<slug>.md` with these sections — be concrete, no fluff:
   - **Task** — one sentence: what we're trying to do and why.
   - **Status** — what's done, what's in flight, what's blocked. Reference commits/PRs by SHA/number.
   - **Key files** — paths the resuming session must read first, with a one-line note on each.
   - **Decisions made** — non-obvious choices (`chose X over Y because …`) so the next session doesn't relitigate them.
   - **Open questions** — anything waiting on the user or external input.
   - **Next step** — the literal next action to take on resume.
   - **Resume prompt** — a copy-pasteable sentence the user can fire after `/clear`, e.g. `Read .claude/handoffs/<slug>.md and continue from the "Next step" section.`
3. If `.claude/handoffs/<slug>.md` already exists, ask whether to overwrite, merge, or pick a new slug before writing.
4. Print the file path and the resume prompt. Remind the user: `/clear` discards this session — re-launching reads the handoff fresh.

## Guardrails

- Don't dump raw tool output. Summarise.
- Don't include secrets, tokens, or PII pulled from logs.
- Delete the handoff file once the work merges to main (or once the resuming session no longer needs it).
