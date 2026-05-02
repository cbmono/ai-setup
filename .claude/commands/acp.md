Stage all changes, create a commit with a descriptive message, and push to the remote. Stack-aware.

## Steps

1. `git add -A` to stage all changes.
2. Run `git diff --cached` and `git status` to understand what's being committed.
3. Write a concise, descriptive commit message based on the changes. If `$ARGUMENTS` is provided, use it verbatim as the commit message instead.
4. Commit.
5. **Decide how to push:**
   - If the current branch is part of a `gh stack` (run `gh stack view` and check it doesn't error), run `gh stack submit` — it both pushes the stack and creates/updates the PRs in one step, so the PR list and the remote tips stay aligned. (`gh stack push` only pushes branches; PRs would still update via the new tip, but `submit` also reconciles PR titles/descriptions with stack ordering, which is what we want after a commit.)
   - Otherwise, `git push` on the current branch (add `-u origin <branch>` if the branch has no upstream).
6. Report the commit SHA and, for stacked branches, the PR URL from `gh stack view`. If the diff you read in step 2 suggests a follow-up review pass would catch something — substantial logic changes, a new module, a refactor across several files in one area, a large delete — append a one-line "consider `/verify`" / "consider `/grill`" / "consider `/scan` on `<dir>`" / "consider `/techdebt`" suggestion tied to the actual signal. Skip the suggestion entirely for doc-only, config-only, dep-bump, or formatting commits. Don't run the suggested command — the user picks.

## Guardrails

- Never use `git push --force` or `-f`. In stacked context, `gh stack submit` handles force-with-lease correctly.
- If the working tree has only whitespace or generated-file changes, ask before committing.
- Skip files that look like secrets (`.env*`, `*.pem`, credentials files) — warn if the user explicitly staged them.
