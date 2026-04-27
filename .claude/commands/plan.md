Draft an implementation plan, dispatch a staff-engineer reviewer, and — once the user approves — save the refined plan as a checked-in artifact that rides with the stacked PRs.

Use this for any non-trivial task where a weak plan would compound into a bad implementation.

## Steps

1. Derive a slug for the plan file:
   - Grep the current branch name and the last 5 commit subjects for `\b[A-Z]{2,}-\d+\b`. If a Jira-style key matches (e.g. `AUTH-1234`), slug = that key.
   - Otherwise, build a 3–5 kebab-case word summary of `$ARGUMENTS`, prefixed with a verb when one fits — `feat-rotate-oauth-keys`, `fix-auth-race`, `chore-bump-deps`, `refactor-payments-module`. If no prefix fits, drop it (`migrate-to-rsc`).
   - If `$ARGUMENTS` is empty or too thin to summarise, ask the user for a slug before continuing.
2. Draft a plan based on `$ARGUMENTS` (the task). Structure:
   - **Goal** — one sentence.
   - **Files to touch** — concrete paths.
   - **Steps** — GitHub-checkbox list (`- [ ] step`); each small enough that progress is observable as work lands.
   - **Edge cases** — concurrency, retries, partial failure, untrusted inputs.
   - **Out of scope** — explicit non-goals.
   - **Acceptance criteria** — how we'll know it's done.
3. Dispatch the `plan-architect` agent with the plan as input. It reviews plans (not diffs) for missing edge cases, wrong layering, scope creep, and better alternatives.
4. Present the plan and the reviewer verdict to the user side by side. **Do not save anything yet.** Wait for the user to accept, redirect, or revise. Do not start implementation either.
5. Once the user accepts:
   - Apply the architect findings the user explicitly approved.
   - Check whether `.claude/plans/<slug>.md` already exists. If it does, ask the user whether to overwrite, pick a new slug, or merge into the existing file before writing.
   - Save the final plan to `.claude/plans/<slug>.md`.
6. Close with this reminder verbatim:

   > Tick checkboxes as steps land. Once the work merges to main (the last PR in the stack, if stacked), delete `.claude/plans/<slug>.md`.

Keep the plan tight. A good plan is 10–20 bullet points, not an essay.
