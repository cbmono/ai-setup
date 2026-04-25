Grill the current changes before they become a PR. Play devil's advocate against your own work.

## Steps

1. Read the current diff: `git diff` and `git diff --cached`.
2. **Dispatch `code-architect` in parallel** with the rest of these steps. It covers the architecture lens — layering, naming, dependency choices, abstraction shape — that this command intentionally doesn't. Pass it the same diff. Run as a single subagent call, then merge its findings into your final report under an "Architecture review" heading.
3. For each hunk, generate the toughest question a senior reviewer would ask. Categories:
   - **Correctness** — What input breaks this? What edge case is assumed away?
   - **Concurrency** — What if two callers hit this simultaneously? What if a request is retried?
   - **Failure modes** — What happens on network error, disk full, parse error, null?
   - **Observability** — How would we notice if this silently misbehaved in prod?
   - **Testing** — What does the test actually assert? Could it pass without the code under test doing anything?
   - **Scope** — What was added that the task didn't require?
4. Answer each question honestly. If the answer is "I don't know" or "not handled", call it out.
5. List BLOCKERS at the top — things that must be fixed before PR. Include both your own findings and any BLOCKERs surfaced by `code-architect`.

Don't be polite. The goal is to find what's wrong before a human reviewer does.

If the diff is *only* doc/config changes (no executable code), skip the `code-architect` dispatch — it has nothing to chew on.
