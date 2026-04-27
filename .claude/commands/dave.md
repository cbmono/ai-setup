Get a second opinion on the current change or plan from Dave AI (Alteos-internal assistant) via the `dave` CLI. Single round — Dave's reply is rendered back verbatim, then Claude follows up with its own evaluation.

Use this when you want an outside read before opening a PR or before implementing a plan. Dave has access to the Alteos GitHub codebase, Confluence, and Jira — let it pull broader context itself.

> Requires the [`dave` CLI](https://github.com/alteos-gmbh/dave-cli) and `jq`. Alteos-internal — not useful in a fork without it.

## Steps

1. Verify dependencies: `command -v dave` and `command -v jq`. If `dave` is missing, tell the user "Dave CLI not installed — see https://github.com/alteos-gmbh/dave-cli." and stop. If `jq` is missing, tell the user "`jq` not installed — install via `brew install jq`." and stop.
2. Detect the repo's default branch — don't assume `main`. Try `git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'`; fall back to `main` if empty. Call this `BASE`.
3. Decide what to review. Detection order:
   - An active plan in this session → candidate: plan.
   - Uncommitted changes (`git status --porcelain` non-empty) → candidate: working diff.
   - Commits ahead of `BASE` (`git log $BASE..HEAD` non-empty) → candidate: branch diff.
   - If exactly one candidate matches, use it. If multiple match (e.g. plan + working diff), ask the user which to review before continuing. If none match, ask the user what to review and stop.
4. Treat `$ARGUMENTS` as a focus hint (e.g. "auth flow", "migration safety"). Empty is fine.
5. Sanity-check the diff for secrets before sending — scan for `.env` content, API keys, tokens, private keys. Dave is internal but the request may be logged. If anything looks sensitive, flag it to the user and ask them to confirm before sending; only stop if they decline.
6. Build the prompt. Shape:
   - Repo + current branch.
   - Related Jira tickets: grep the current branch name and the last 5 commit subjects for `\b[A-Z]{2,}-\d+\b`, dedupe, and inline as "Related tickets: …" so Dave doesn't have to guess. The `{2,}` and word boundaries avoid false positives like `UTF-8` or `SHA-1`.
   - What is being reviewed (plan / working diff / branch diff).
   - Plan text or diff inline. For diffs >3000 lines, replace the LLM-summary approach with a mechanical condensation: include `git diff --stat` for the full file list, then full diff for the top ~10 files by churn — and hard-cap the inlined diff at ~3000 lines total (`head -n 3000` after concatenation) so a single huge file can't blow up the prompt. Don't paraphrase code.
     - **Branch diff:** check the branch is pushed first (`git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null` non-empty, or `git ls-remote --heads origin <branch>` returns a hit). If pushed, include the branch name and tell Dave it can fetch the rest from GitHub. If not pushed, treat it like a working diff and inline `git diff $BASE...HEAD`.
     - **Working diff:** Dave can only read pushed commits — don't tell it to fetch; inline `git diff HEAD` so both staged and unstaged changes are captured.
   - Focus hint from `$ARGUMENTS` if present.
   - Explicit ask: "Critique this. Flag risks, missing edge cases, hidden assumptions, scope creep, and better alternatives. Use Jira/Confluence if relevant. Be terse — bullet points, no preamble."
7. Send via a quoted heredoc. Capture stderr and check the exit code before `jq`, otherwise plain-text errors get swallowed. Dave can be slow on large contexts — set the Bash tool's `timeout` parameter (not a shell `timeout` command) to ~300000 ms. After the exit-code check, validate that the output is parseable JSON with a non-null `.reply` field before extracting it.

   ```bash
   PROMPT=$(cat <<'EOF'
   ...prompt body...
   EOF
   )
   OUT=$(dave --json "$PROMPT" 2>&1); rc=$?
   if [ $rc -ne 0 ]; then
     printf 'dave exited %d:\n%s\n' "$rc" "$OUT" >&2
     exit $rc
   fi
   if ! printf '%s' "$OUT" | jq -e '.reply != null' >/dev/null 2>&1; then
     printf 'dave reply not parseable:\n%s\n' "$OUT" >&2
     exit 7
   fi
   printf '%s\n' "$OUT" | jq -r .reply
   ```

8. Render the `reply` field verbatim first, in its own block. The user wants Dave's words intact before any commentary.
9. Map non-zero `dave` exit codes to actionable errors: `2` = not configured (`dave login`), `3` = auth failed (`dave login`), `4` = webhook 404, `5` = network, `6` = server 5xx, `7` = malformed reply. For any other non-zero code (including `1`), surface the captured stderr verbatim and the numeric code so the user can diagnose.
10. After rendering Dave's reply, evaluate it: agree/disagree per point with brief reasoning, flag any items that depend on bad context Claude gave Dave, and propose specific edits or follow-ups. **Wait for user approval before applying any changes.**

One round, one reply — Dave has no resume primitive yet. Don't fan out into multiple `dave` calls.
