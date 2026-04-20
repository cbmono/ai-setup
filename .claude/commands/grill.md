Grill the current changes before they become a PR. Play devil's advocate against your own work.

## Steps

1. Read the current diff: `git diff` and `git diff --cached`.
2. For each hunk, generate the toughest question a senior reviewer would ask. Categories:
   - **Correctness** — What input breaks this? What edge case is assumed away?
   - **Concurrency** — What if two callers hit this simultaneously? What if a request is retried?
   - **Failure modes** — What happens on network error, disk full, parse error, null?
   - **Observability** — How would we notice if this silently misbehaved in prod?
   - **Testing** — What does the test actually assert? Could it pass without the code under test doing anything?
   - **Scope** — What was added that the task didn't require?
3. Answer each question honestly. If the answer is "I don't know" or "not handled", call it out.
4. List BLOCKERS at the top — things that must be fixed before PR.

Don't be polite. The goal is to find what's wrong before a human reviewer does.

## Sibling

`/grill` covers correctness and edge cases. For architecture, patterns, dependency choices, and naming, dispatch the `code-architect` agent separately (or run `/plan-review` earlier, before the diff exists). The two views complement each other — use both on non-trivial changes.
