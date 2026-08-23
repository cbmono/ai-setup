Stage all changes, create a commit with a descriptive message, and push to the remote. Stack-aware.

## Steps

1. **Scan for secrets BEFORE staging anything.** `git add -A` stages every non-ignored path, so a
   secret staged first is a secret the rest of this flow has to un-stage. List the paths git would
   stage — `git status --porcelain --untracked-files=all` (`--untracked-files=all` matters: plain
   `--porcelain` collapses an untracked directory to `dir/` and would hide `dir/.env`) — and match the
   **paths only** against: `.env` and `.env.*` except the templates `.env.example` / `.env.template` /
   `.env.sample`; `*.pem`, `*.key`, `*.p12`, `*.pfx`, `*.keystore`, `*.jks`; `id_rsa` / `id_ed25519` /
   `id_ecdsa` / `id_dsa`; `credentials`, `service-account*.json`, `*.kubeconfig`, `.npmrc`, `.netrc`.
   If anything matches, **stop before staging** and report the matching paths and the `.gitignore` /
   `git rm --cached` fix. Only continue if the user tells you explicitly to include that path.
2. `git add -A` to stage all changes.
3. Run `git diff --cached` and `git status` to understand what's being committed.
4. Write a concise, descriptive commit message based on the changes. If `$ARGUMENTS` is provided, use it verbatim as the commit message instead.
5. Commit.
6. **Decide how to push:**
   - If the current branch is part of a `gh stack` (run `gh stack view` and check it doesn't error), run `gh stack submit` — it both pushes the stack and creates/updates the PRs in one step, so the PR list and the remote tips stay aligned. (`gh stack push` only pushes branches; PRs would still update via the new tip, but `submit` also reconciles PR titles/descriptions with stack ordering, which is what we want after a commit.)
   - Otherwise, `git push` on the current branch (add `-u origin <branch>` if the branch has no upstream).
7. Report the commit SHA and, for stacked branches, the PR URL from `gh stack view`. If the diff you read in step 3 suggests a follow-up review pass would catch something — substantial logic changes, a new module, a refactor across several files in one area, a large delete — append a one-line "consider `/verify`" / "consider `/grill`" / "consider `/scan` on `<dir>`" / "consider `/techdebt`" suggestion tied to the actual signal. Skip the suggestion entirely for doc-only, config-only, dep-bump, or formatting commits. Don't run the suggested command — the user picks.

## Guardrails

- Never use `git push --force` or `-f`. In stacked context, `gh stack submit` handles force-with-lease correctly.
- If the working tree has only whitespace or generated-file changes, ask before committing.
- **Never print the contents of a secret candidate.** Not `cat`, not `git diff`, not `git diff
  --cached` scoped to it, not an excerpt "to check whether it's real" — name the path and stop.
  Standing rule: never echo, print, or log secrets or environment variables. If the user does
  authorise including such a path, still skip it when reading the diff in step 3.
- Step 1 is the only secret gate, and it runs before `git add`. Don't move it after staging, and
  don't replace it with an un-stage step: a file that reached the index is a file a later `-A` or a
  stray `git commit -a` can still carry.
