Write a plan for the current task, then spin up a second Claude as staff-engineer reviewer to critique it before implementation starts.

Use this for any non-trivial task where a weak plan would compound into a bad implementation.

## Steps

1. Draft a plan based on `$ARGUMENTS` (the task). Include:
   - Goal and acceptance criteria
   - Files to touch
   - Step-by-step approach
   - Edge cases and risks
   - Out-of-scope (explicitly)
2. Dispatch the `code-architect` agent in a subagent call with the plan as input. Ask it to review **the plan, not the code** — look for missing edge cases, wrong layering, scope creep, and better alternatives.
3. Present both the plan and the review to the user side by side.
4. Wait for the user to accept, redirect, or revise. Do not start implementation until the user confirms.

Keep the plan tight. A good plan is 10–20 bullet points, not an essay.
